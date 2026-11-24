"""Experimental one-world backup. Fail-closed Linux publication, copies only.

Existing destinations are never replaced. No in-place restore is provided.
A successful return means validated bytes were published and directory sync
completed, not a guarantee against failing hardware or hostile filesystem code.
"""
from pathlib import Path, PurePosixPath
import ctypes
import errno
import hashlib
import json
import os
import shutil
import sqlite3
import stat
import sys
import tempfile
import zipfile

LIMIT = 64 * 1024 * 1024


def _checkpoint(stage):
    """Private no-op seam for disposable-fixture failure injection."""


def _sync_dir(fd):
    os.fsync(fd)


def _parent(path):
    """Pin an existing directory chain, rejecting every symlink component.

    Publication is intentionally unavailable on untested platforms/filesystems.
    Each component is opened relative to the previous pinned directory.
    """
    if not sys.platform.startswith('linux'):
        raise OSError('Publication requires audited Linux dirfd/no-replace support')
    raw = Path(os.path.abspath(os.fspath(path)))
    if raw.name in {'', '.', '..'}:
        raise ValueError('Destination filename required')
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in raw.parent.parts[1:]:
            nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = nxt
        return raw, fd
    except BaseException:
        os.close(fd)
        raise


def _absent(fd, name):
    try:
        os.stat(name, dir_fd=fd, follow_symlinks=False)
    except FileNotFoundError:
        return
    raise FileExistsError('Existing destination must not be overwritten')


def _rename_new_dir(fd, source, destination):
    libc = ctypes.CDLL(None, use_errno=True)
    rename = getattr(libc, 'renameat2', None)
    if rename is None:
        raise OSError('Atomic no-replace directory publication unavailable')
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(fd, os.fsencode(source), fd, os.fsencode(destination), 1) != 0:
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code))


def _check_database(path, expected_world=None, *, project=False):
    c = sqlite3.connect(Path(path).resolve().as_uri() + '?mode=ro', uri=True)
    try:
        c.execute('PRAGMA trusted_schema=OFF')
        if c.execute('pragma integrity_check').fetchone() != ('ok',):
            raise ValueError('Database corruption')
        if c.execute('pragma foreign_key_check').fetchall():
            raise ValueError('Broken references')
        schema = c.execute('SELECT type,name,tbl_name,sql FROM sqlite_master').fetchall()
        # A validated snapshot is data, never executable schema supplied by a pack.
        for kind, name, table, sql in schema:
            if kind in ('trigger', 'view') or (sql and 'CREATE VIRTUAL TABLE' in sql.upper()):
                raise ValueError('Executable or virtual database schema is not allowed')
            if kind == 'index' and (sql is not None or not name.startswith('sqlite_autoindex_')):
                raise ValueError('Application-defined indexes are not allowed')
            if kind not in ('table', 'index'):
                raise ValueError('Unsupported database schema object')
        if not any(kind == 'table' and name == 'worlds' for kind,name,_,_ in schema):
            raise ValueError('Missing worlds table')
        if project:
            allowed = {'worlds', 'objects', 'changes', 'authored_orbits', 'sqlite_sequence'}
            if any(kind == 'table' and name not in allowed for kind,name,_,_ in schema):
                raise ValueError('Unexpected project table')
        rows = c.execute('select id from worlds order by id').fetchall()
        if project:
            import math
            version = c.execute('pragma user_version').fetchone()[0]
            required = {
                'worlds': {'id', 'name', 'schema_version'},
                'objects': {'id', 'world_id', 'kind', 'name', 'x', 'y', 'radius'},
                'changes': {'id', 'world_id', 'object_id', 'before_json', 'after_json'},
            }
            if version == 2:
                required['authored_orbits'] = {'body_id', 'center_id', 'seconds', 'clockwise'}
            for table, columns in required.items():
                entry = c.execute("select type from sqlite_master where name=?", (table,)).fetchall()
                actual = {r[1] for r in c.execute('pragma table_xinfo(' + table + ')')}
                if entry != [('table',)] or columns != actual:
                    raise ValueError('Missing or incompatible project table: ' + table)
            if not rows or any(not isinstance(r[0], str) or not r[0] for r in rows):
                raise ValueError('Nonempty project world identities required')
            ids = [r[0] for r in rows]
            if expected_world is not None and ids != expected_world:
                raise ValueError('Wrong project world identities')
            if c.execute('pragma user_version').fetchone()[0] not in (1, 2):
                raise ValueError('Unsupported project database version')
            world_set = set(ids)
            objects = {}
            for body, world, kind, name, x, y, radius in c.execute('select id,world_id,kind,name,x,y,radius from objects'):
                if (not isinstance(body, str) or not body or body in objects
                        or world not in world_set or not isinstance(kind, str) or not kind
                        or not isinstance(name, str) or not name.strip() or len(name.strip()) > 80
                        or any(ord(ch) < 32 or 127 <= ord(ch) <= 159 or ord(ch) in
                               {0x2028, 0x2029, 0x061c, 0x200b, 0x200e, 0x200f,
                                *range(0x202a, 0x202f), *range(0x2066, 0x206a), 0xfeff} for ch in name)
                        or any(not isinstance(v, (int, float)) or not math.isfinite(v) for v in (x, y, radius))
                        or not 0 <= x <= 1 or not 0 <= y <= 1 or not .01 <= radius <= .25):
                    raise ValueError('Invalid project object')
                objects[body] = (world, x, y)
            if c.execute('select 1 from changes where world_id not in (select id from worlds) or world_id is null limit 1').fetchone():
                raise ValueError('Invalid project history world')
            if c.execute("select 1 from sqlite_master where type='table' and name='authored_orbits'").fetchone():
                import math
                parents = {}
                for body, center, seconds, clockwise in c.execute('select body_id,center_id,seconds,clockwise from authored_orbits'):
                    a, b = objects.get(body), objects.get(center)
                    if (a is None or b is None or body == center or a[0] != b[0]
                            or body in parents or not isinstance(seconds, (int, float))
                            or not math.isfinite(seconds) or not 1 <= seconds <= 3600
                            or clockwise not in (0, 1) or a[1:] == b[1:]):
                        raise ValueError('Invalid project orbit')
                    parents[body] = center
                for body in parents:
                    seen = set()
                    while body in parents:
                        if body in seen:
                            raise ValueError('Orbit dependency cycle')
                        seen.add(body)
                        body = parents[body]
            return ids
        if len(rows) != 1 or not isinstance(rows[0][0], str) or not rows[0][0]:
            raise ValueError('One nonempty world identity required')
        if expected_world is not None and rows != [(expected_world,)]:
            raise ValueError('Wrong world identity')
        # A Flutter project in a legacy envelope still receives full project checks.
        if any(kind == 'table' and name in {'objects', 'changes', 'authored_orbits'}
               for kind,name,_,_ in schema):
            _check_database(path, [rows[0][0]], project=True)
        return rows[0][0]
    finally:
        c.close()


def validate(package):
    with zipfile.ZipFile(package) as z:
        names = z.namelist()
        if len(set(names)) != len(names) or set(names) != {'manifest.json', 'world.sqlite'}:
            raise ValueError('Duplicate or unexpected contents')
        for item in z.infolist():
            p = PurePosixPath(item.filename)
            mode = item.external_attr >> 16
            if (p.is_absolute() or '..' in p.parts or '\\' in item.filename
                    or item.file_size > LIMIT or stat.S_ISLNK(mode) or item.flag_bits & 1):
                raise ValueError('Unsafe entry')
        if z.getinfo('manifest.json').file_size > 16384:
            raise ValueError('Manifest too large')
        m = json.loads(z.read('manifest.json'))
        if not isinstance(m, dict):
            raise ValueError('Manifest must be an object')
        project = m.get('format') == 'iwfproject'
        if (type(m.get('schema_version')) is not int
                or (m['schema_version'], m.get('format')) not in ((1, 'iwfpack'), (2, 'iwfproject'))):
            raise ValueError('Unsupported version')
        if project:
            ids = m.get('world_ids')
            if (not isinstance(ids, list) or not ids or any(not isinstance(i,str) or not i for i in ids)
                    or ids != sorted(set(ids))):
                raise ValueError('Invalid project identities')
        elif not isinstance(m.get('world_id'), str) or not m['world_id']:
            raise ValueError('Invalid world identity')
        data = z.read('world.sqlite')
        if m.get('sha256') != hashlib.sha256(data).hexdigest():
            raise ValueError('Checksum mismatch')
        if not data.startswith(b'SQLite format 3\x00'):
            raise ValueError('Not a SQLite database')
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / 'check.sqlite'
            p.write_bytes(data)
            _check_database(p, m['world_ids'] if project else m['world_id'], project=project)
        return m, data


def export(database, destination, *, project=False):
    source_path = Path(database).resolve(strict=True)
    if not source_path.is_file():
        raise ValueError('Regular source database required')
    destination = Path(destination)
    if destination.resolve() == source_path:
        raise ValueError('Package destination cannot replace source database')
    if destination.exists() and os.path.samefile(source_path, destination):
        raise ValueError('Source/output inode alias')
    out, fd = _parent(destination)
    pending = None
    try:
        _absent(fd, out.name)
        # Linux proc-fd path keeps staging in the pinned parent even if renamed.
        parent = Path(f'/proc/self/fd/{fd}')
        with tempfile.TemporaryDirectory() as td:
            snapshot = Path(td) / 'snapshot.sqlite'
            source = sqlite3.connect(source_path.as_uri() + '?mode=ro', uri=True)
            target = sqlite3.connect(snapshot)
            try:
                source.backup(target)
            finally:
                source.close()
                target.close()
            world_id = _check_database(snapshot, project=project)
            data = snapshot.read_bytes()
            manifest = dict(format='iwfproject' if project else 'iwfpack', schema_version=2 if project else 1,
                            sha256=hashlib.sha256(data).hexdigest())
            manifest['world_ids' if project else 'world_id'] = world_id
            temp_fd, temp_path = tempfile.mkstemp(prefix='.iwf-export-', dir=parent)
            pending = Path(temp_path).name
            with os.fdopen(temp_fd, 'w+b') as f:
                with zipfile.ZipFile(f, 'w', zipfile.ZIP_DEFLATED) as z:
                    z.writestr('manifest.json', json.dumps(manifest))
                    z.writestr('world.sqlite', data)
                f.flush()
                os.fsync(f.fileno())
            validate(parent / pending)
            _checkpoint('export_before_publish')
            os.link(pending, out.name, src_dir_fd=fd, dst_dir_fd=fd, follow_symlinks=False)
            _checkpoint('export_after_publish')
            _sync_dir(fd)
    finally:
        if pending is not None:
            os.unlink(pending, dir_fd=fd)
        os.close(fd)


def restore(package, destination):
    out, fd = _parent(destination)
    pending = None
    try:
        _absent(fd, out.name)
        manifest, data = validate(package)
        parent = Path(f'/proc/self/fd/{fd}')
        pending = Path(tempfile.mkdtemp(prefix='.iwf-restore-', dir=parent)).name
        stage = parent / pending
        with open(stage / 'world.sqlite', 'xb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        # validate() already checked these exact bytes on a private temporary copy.
        # Do not reopen the publication stage: a read-only WAL connection creates sidecars.
        if (stage / 'world.sqlite').read_bytes() != data:
            raise ValueError('Staged database differs from validated bytes')
        stage_fd = os.open(pending, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
        try:
            _sync_dir(stage_fd)
        finally:
            os.close(stage_fd)
        _checkpoint('restore_before_publish')
        _rename_new_dir(fd, pending, out.name)
        pending = None
        _checkpoint('restore_after_publish')
        _sync_dir(fd)
        return manifest
    finally:
        if pending is not None:
            shutil.rmtree(Path(f'/proc/self/fd/{fd}') / pending)
        os.close(fd)
