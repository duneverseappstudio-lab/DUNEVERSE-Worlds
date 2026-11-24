"""Dangerous-case regressions. Every database is created under TemporaryDirectory."""
from pathlib import Path
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import worldpack as w


class Audit(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='iwf-audit-')
        self.root = Path(self.tmp.name)
        self.db = self.root / 'original-fixture.sqlite'
        c = sqlite3.connect(self.db)
        c.executescript('CREATE TABLE worlds(id TEXT PRIMARY KEY); CREATE TABLE items(id TEXT PRIMARY KEY,world_id TEXT REFERENCES worlds(id),name TEXT);')
        c.execute('insert into worlds values(?)', ('w',))
        c.execute('insert into items values(?,?,?)', ('id', 'w', 'مدينة'))
        c.commit(); c.close()
        self.original = self.db.read_bytes()
        self.pack = self.root / 'backup.iwfpack'
        self.dest = self.root / 'restored'

    def tearDown(self):
        self.assertEqual(self.db.read_bytes(), self.original, 'Fixture source bytes changed')
        self.tmp.cleanup()

    def package(self, data, **fields):
        m = dict(format='iwfpack', schema_version=1, world_id='w', sha256=hashlib.sha256(data).hexdigest())
        m.update(fields)
        with zipfile.ZipFile(self.pack, 'w') as z:
            z.writestr('manifest.json', json.dumps(m)); z.writestr('world.sqlite', data)

    def assert_valid_destination(self):
        self.assertEqual((self.dest / 'world.sqlite').read_bytes(), w.validate(self.pack)[1])
        self.assertEqual(sqlite3.connect(self.dest / 'world.sqlite').execute('pragma integrity_check').fetchone(), ('ok',))

    def test_normalized_same_path(self):
        sub = self.root / 'sub'; sub.mkdir()
        with self.assertRaises(ValueError): w.export(self.db, sub / '..' / self.db.name)

    def test_symlink_source_alias(self):
        link = self.root / 'source-link'; link.symlink_to(self.db)
        with self.assertRaises(ValueError): w.export(link, self.db)

    def test_hardlink_alias(self):
        link = self.root / 'hardlink'; os.link(self.db, link)
        with self.assertRaises(ValueError): w.export(self.db, link)
        self.assertEqual(link.read_bytes(), self.original)

    def test_destination_parent_symlink_rejected(self):
        link = self.root / 'parent-link'; link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(OSError): w.export(self.db, link / 'new.pack')
        self.assertFalse((self.root / 'new.pack').exists())

    def test_restore_parent_symlink_rejected(self):
        w.export(self.db, self.pack)
        link = self.root / 'parent-link'; link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(OSError): w.restore(self.pack, link / 'new-world')
        self.assertFalse((self.root / 'new-world').exists())

    def test_broken_destination_symlink_rejected(self):
        self.pack.symlink_to(self.root / 'missing')
        with self.assertRaises(FileExistsError): w.export(self.db, self.pack)
        self.assertTrue(self.pack.is_symlink())

    def test_empty_source(self):
        empty = self.root / 'empty.sqlite'; empty.touch()
        with self.assertRaises(ValueError): w.export(empty, self.pack)
        self.assertEqual(empty.read_bytes(), b''); self.assertFalse(self.pack.exists())

    def test_corrupt_source(self):
        bad = self.root / 'bad.sqlite'; bad.write_bytes(b'bad database')
        with self.assertRaises(sqlite3.DatabaseError): w.export(bad, self.pack)
        self.assertEqual(bad.read_bytes(), b'bad database'); self.assertFalse(self.pack.exists())

    def test_empty_archive(self):
        self.pack.touch()
        with self.assertRaises(zipfile.BadZipFile): w.restore(self.pack, self.dest)
        self.assertFalse(self.dest.exists())

    def test_corrupt_archive(self):
        self.pack.write_bytes(b'bad archive')
        with self.assertRaises(zipfile.BadZipFile): w.restore(self.pack, self.dest)
        self.assertFalse(self.dest.exists())

    def test_empty_db_in_valid_zip(self):
        self.package(b'')
        with self.assertRaises(ValueError): w.restore(self.pack, self.dest)
        self.assertFalse(self.dest.exists())

    def test_corrupt_db_matching_hash(self):
        self.package(b'SQLite format 3\x00' + b'corrupt' * 30)
        with self.assertRaises(sqlite3.DatabaseError): w.restore(self.pack, self.dest)
        self.assertFalse(self.dest.exists())

    def test_bad_world_identity(self):
        self.package(self.original, world_id='other')
        with self.assertRaises(ValueError): w.restore(self.pack, self.dest)
        self.assertFalse(self.dest.exists())

    def test_broken_foreign_key(self):
        bad = self.root / 'fk.sqlite'; bad.write_bytes(self.original)
        c = sqlite3.connect(bad); c.execute("insert into items values('bad','missing','bad')"); c.commit(); c.close()
        self.package(bad.read_bytes())
        with self.assertRaises(ValueError): w.restore(self.pack, self.dest)
        self.assertFalse(self.dest.exists())

    def test_existing_current_db_directory_preserved(self):
        w.export(self.db, self.pack); self.dest.mkdir(); current = self.dest / 'world.sqlite'; current.write_bytes(b'current fixture')
        with self.assertRaises(FileExistsError): w.restore(self.pack, self.dest)
        self.assertEqual(current.read_bytes(), b'current fixture')

    def test_restore_destination_is_source_file(self):
        w.export(self.db, self.pack)
        with self.assertRaises(FileExistsError): w.restore(self.pack, self.db)

    def test_export_exception_before_publish(self):
        with patch.object(w, '_checkpoint', side_effect=RuntimeError('injected')):
            with self.assertRaises(RuntimeError): w.export(self.db, self.pack)
        self.assertFalse(self.pack.exists()); self.assertFalse(list(self.root.glob('.iwf-export-*')))

    def test_restore_exception_before_publish(self):
        w.export(self.db, self.pack)
        with patch.object(w, '_checkpoint', side_effect=RuntimeError('injected')):
            with self.assertRaises(RuntimeError): w.restore(self.pack, self.dest)
        self.assertFalse(self.dest.exists()); self.assertFalse(list(self.root.glob('.iwf-restore-*')))

    def test_export_validation_failure_no_publish(self):
        with patch.object(w, 'validate', side_effect=ValueError('injected')):
            with self.assertRaises(ValueError): w.export(self.db, self.pack)
        self.assertFalse(self.pack.exists())

    def test_export_fsync_failure_no_publish(self):
        with patch.object(w.os, 'fsync', side_effect=OSError('injected disk error')):
            with self.assertRaises(OSError): w.export(self.db, self.pack)
        self.assertFalse(self.pack.exists())

    def test_restore_fsync_failure_no_publish(self):
        w.export(self.db, self.pack)
        with patch.object(w.os, 'fsync', side_effect=OSError('injected disk error')):
            with self.assertRaises(OSError): w.restore(self.pack, self.dest)
        self.assertFalse(self.dest.exists())

    def test_export_competing_writer_not_overwritten(self):
        def race(stage):
            if stage == 'export_before_publish': self.pack.write_bytes(b'competitor')
        with patch.object(w, '_checkpoint', side_effect=race):
            with self.assertRaises(FileExistsError): w.export(self.db, self.pack)
        self.assertEqual(self.pack.read_bytes(), b'competitor')

    def test_restore_competing_directory_not_overwritten(self):
        w.export(self.db, self.pack)
        def race(stage):
            if stage == 'restore_before_publish': self.dest.mkdir()
        with patch.object(w, '_checkpoint', side_effect=race):
            with self.assertRaises(FileExistsError): w.restore(self.pack, self.dest)
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_after_publish_exception_keeps_valid_backup(self):
        def fail(stage):
            if stage == 'export_after_publish': raise RuntimeError('injected')
        with patch.object(w, '_checkpoint', side_effect=fail):
            with self.assertRaises(RuntimeError): w.export(self.db, self.pack)
        w.validate(self.pack)

    def test_after_publish_exception_keeps_complete_restore(self):
        w.export(self.db, self.pack)
        def fail(stage):
            if stage == 'restore_after_publish': raise RuntimeError('injected')
        with patch.object(w, '_checkpoint', side_effect=fail):
            with self.assertRaises(RuntimeError): w.restore(self.pack, self.dest)
        self.assert_valid_destination()

    def test_process_exit_publication_boundaries(self):
        w.export(self.db, self.pack)
        for operation in ['export', 'restore']:
            for boundary in ['before', 'after']:
                with self.subTest(operation=operation, boundary=boundary):
                    destination = self.root / (operation + boundary)
                    code = ('import os,sys,worldpack as w; '
                            'w._checkpoint=lambda stage: os._exit(71) if stage==sys.argv[1] else None; '
                            'getattr(w,sys.argv[2])(sys.argv[3],sys.argv[4])')
                    proc = subprocess.run([sys.executable, '-c', code, operation + '_' + boundary + '_publish', operation,
                                           str(self.db if operation=='export' else self.pack), str(destination)],
                                          env={**os.environ, 'PYTHONPATH':str(Path(w.__file__).parent)}, timeout=10)
                    self.assertEqual(proc.returncode, 71)
                    if boundary == 'before': self.assertFalse(destination.exists())
                    elif operation == 'export': w.validate(destination)
                    else:
                        self.assertEqual((destination/'world.sqlite').read_bytes(), w.validate(self.pack)[1])

    def test_export_parent_renamed_publication_stays_pinned(self):
        parent = self.root / 'out'; parent.mkdir()
        moved = self.root / 'moved'
        def rename_parent(stage):
            if stage == 'export_before_publish':
                parent.rename(moved); parent.mkdir()
        with patch.object(w, '_checkpoint', side_effect=rename_parent):
            w.export(self.db, parent / 'new.pack')
        self.assertFalse((parent / 'new.pack').exists())
        w.validate(moved / 'new.pack')

    def test_restore_parent_renamed_publication_stays_pinned(self):
        w.export(self.db, self.pack)
        parent = self.root / 'out'; parent.mkdir()
        moved = self.root / 'moved'
        def rename_parent(stage):
            if stage == 'restore_before_publish':
                parent.rename(moved); parent.mkdir()
        with patch.object(w, '_checkpoint', side_effect=rename_parent):
            w.restore(self.pack, parent / 'new')
        self.assertFalse((parent / 'new').exists())
        self.assertEqual((moved / 'new/world.sqlite').read_bytes(), w.validate(self.pack)[1])

    def test_zip_write_failure_leaves_source_and_destination_untouched(self):
        with patch.object(zipfile.ZipFile, 'writestr', side_effect=OSError('simulated disk full')):
            with self.assertRaises(OSError): w.export(self.db, self.pack)
        self.assertFalse(self.pack.exists())

    def test_live_wal_snapshot_includes_committed_data(self):
        c = sqlite3.connect(self.db)
        try:
            c.execute('pragma journal_mode=wal')
            c.execute('insert into items values(?,?,?)', ('wal', 'w', 'committed WAL'))
            c.commit()
            before = self.db.read_bytes()
            wal = Path(str(self.db) + '-wal'); before_wal = wal.read_bytes()
            w.export(self.db, self.pack)
            self.assertEqual(self.db.read_bytes(), before)
            self.assertEqual(wal.read_bytes(), before_wal)
            w.restore(self.pack, self.dest)
            restored = sqlite3.connect(self.dest / 'world.sqlite')
            try:
                self.assertEqual(restored.execute('select count(*) from items').fetchone(), (2,))
            finally: restored.close()
        finally:
            c.close()
            # Writer close checkpoints this disposable fixture independently of export.
            self.original = self.db.read_bytes()

    def test_declared_entry_size_limit_rejected(self):
        w.export(self.db, self.pack)
        with patch.object(w, 'LIMIT', 1):
            with self.assertRaises(ValueError): w.restore(self.pack, self.dest)
        self.assertFalse(self.dest.exists())

    def test_actual_phase0_schema_fixture_roundtrip(self):
        fixture = self.root / 'phase0.sqlite'
        c = sqlite3.connect(fixture)
        c.executescript("""PRAGMA user_version=1;
          CREATE TABLE worlds(id TEXT PRIMARY KEY,name TEXT NOT NULL,schema_version INTEGER NOT NULL);
          CREATE TABLE objects(id TEXT PRIMARY KEY,world_id TEXT NOT NULL REFERENCES worlds(id),kind TEXT NOT NULL,name TEXT NOT NULL,x REAL NOT NULL,y REAL NOT NULL,radius REAL NOT NULL CHECK(radius>0));
          CREATE TABLE changes(id INTEGER PRIMARY KEY AUTOINCREMENT,world_id TEXT NOT NULL REFERENCES worlds(id),object_id TEXT NOT NULL,before_json TEXT,after_json TEXT NOT NULL);
          INSERT INTO worlds VALUES('phase0','fixture',1);
          INSERT INTO objects VALUES('obj','phase0','planet','fixture',.4,.5,.03);
          INSERT INTO changes(world_id,object_id,after_json) VALUES( 'phase0','obj','{"id":"obj","kind":"planet","name":"fixture","x":0.4,"y":0.5,"radius":0.03}' );""")
        c.close()
        before = fixture.read_bytes()
        w.export(fixture, self.pack); w.restore(self.pack, self.dest)
        self.assertEqual(before, fixture.read_bytes())
        c = sqlite3.connect(self.dest / 'world.sqlite')
        try:
            self.assertEqual(c.execute('pragma user_version').fetchone(), (1,))
            self.assertEqual(c.execute('select x,y,radius from objects').fetchone(), (.4,.5,.03))
            self.assertEqual(c.execute('select count(*) from changes').fetchone(), (1,))
        finally: c.close()

    def test_boolean_schema_version_rejected(self):
        self.package(self.original, schema_version=True)
        with self.assertRaises(ValueError): w.restore(self.pack, self.dest)
        self.assertFalse(self.dest.exists())

    def test_duplicate_entries_rejected(self):
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            with zipfile.ZipFile(self.pack, 'w') as z:
                z.writestr('manifest.json', '{}'); z.writestr('manifest.json', '{}')
                z.writestr('world.sqlite', self.original)
        with self.assertRaises(ValueError): w.restore(self.pack, self.dest)
        self.assertFalse(self.dest.exists())

    def test_symlink_archive_entry_rejected(self):
        item = zipfile.ZipInfo('world.sqlite'); item.create_system = 3
        item.external_attr = (0o120777 << 16)
        with zipfile.ZipFile(self.pack, 'w') as z:
            z.writestr('manifest.json', '{}'); z.writestr(item, 'target')
        with self.assertRaises(ValueError): w.restore(self.pack, self.dest)
        self.assertFalse(self.dest.exists())

    def test_export_link_failure_no_destination(self):
        with patch.object(w.os, 'link', side_effect=OSError('unsupported link')):
            with self.assertRaises(OSError): w.export(self.db, self.pack)
        self.assertFalse(self.pack.exists())

    def test_restore_no_replace_unavailable_fails_closed(self):
        w.export(self.db, self.pack)
        with patch.object(w, '_rename_new_dir', side_effect=OSError('unsupported')):
            with self.assertRaises(OSError): w.restore(self.pack, self.dest)
        self.assertFalse(self.dest.exists())

    def test_post_publish_sync_error_reports_failure_keeps_valid_output(self):
        with patch.object(w, '_sync_dir', side_effect=OSError('directory sync failed')):
            with self.assertRaises(OSError): w.export(self.db, self.pack)
        w.validate(self.pack)

    def test_unsupported_platform_fails_closed(self):
        with patch.object(w.sys, 'platform', 'win32'):
            with self.assertRaises(OSError): w.export(self.db, self.pack)
        self.assertFalse(self.pack.exists())
