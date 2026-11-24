import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
import zipfile
from worldpack import export, restore, validate


class Packages(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.db = self.root / 'source.sqlite'
        c = sqlite3.connect(self.db)
        c.executescript('CREATE TABLE worlds(id TEXT PRIMARY KEY); CREATE TABLE items(id TEXT PRIMARY KEY,world_id TEXT REFERENCES worlds(id),name TEXT);')
        c.execute('INSERT INTO worlds VALUES(?)', ('world-1',))
        c.execute('INSERT INTO items VALUES(?,?,?)', ('item-1', 'world-1', 'مدينة'))
        c.commit(); c.close()
        self.pack = self.root / 'world.iwfpack'

    def tearDown(self):
        self.tmp.cleanup()

    def test_roundtrip_preserves_arabic_ids_and_links(self):
        export(self.db, self.pack)
        restore(self.pack, self.root / 'restored')
        c = sqlite3.connect(self.root / 'restored/world.sqlite')
        self.assertEqual(c.execute('select * from items').fetchone(), ('item-1', 'world-1', 'مدينة'))
        c.close()

    def test_existing_destination_never_overwritten(self):
        export(self.db, self.pack)
        d = self.root / 'existing'; d.mkdir(); (d / 'keep').write_text('original')
        with self.assertRaises(FileExistsError): restore(self.pack, d)
        self.assertEqual((d / 'keep').read_text(), 'original')

    def test_tampered_database_rejected_before_restore(self):
        export(self.db, self.pack)
        with zipfile.ZipFile(self.pack) as z: m = z.read('manifest.json')
        with zipfile.ZipFile(self.pack, 'w') as z:
            z.writestr('manifest.json', m); z.writestr('world.sqlite', b'corruption')
        with self.assertRaises(ValueError): restore(self.pack, self.root / 'bad')
        self.assertFalse((self.root / 'bad').exists())

    def test_unknown_version_rejected(self):
        export(self.db, self.pack)
        with zipfile.ZipFile(self.pack) as z: m, data = json.loads(z.read('manifest.json')), z.read('world.sqlite')
        m['schema_version'] = 99
        with zipfile.ZipFile(self.pack, 'w') as z:
            z.writestr('manifest.json', json.dumps(m)); z.writestr('world.sqlite', data)
        with self.assertRaises(ValueError): validate(self.pack)

    def test_missing_source_is_not_created(self):
        missing = self.root / 'missing.sqlite'
        with self.assertRaises(FileNotFoundError): export(missing, self.pack)
        self.assertFalse(missing.exists())
        self.assertFalse(self.pack.exists())

    def test_wal_snapshot_includes_committed_uncheckpointed_rows(self):
        c = sqlite3.connect(self.db)
        c.execute('pragma journal_mode=WAL')
        c.execute('pragma wal_autocheckpoint=0')
        c.execute('insert into items values(?,?,?)', ('wal-id', 'world-1', 'قمر'))
        c.commit()
        export(self.db, self.pack)
        c.close()
        restore(self.pack, self.root / 'restored-wal')
        c = sqlite3.connect(self.root / 'restored-wal/world.sqlite')
        self.assertEqual(c.execute('select name from items where id=?', ('wal-id',)).fetchone(), ('قمر',))
        c.close()

    def test_nonobject_manifest_rejected(self):
        with zipfile.ZipFile(self.pack, 'w') as z:
            z.writestr('manifest.json', '[]'); z.writestr('world.sqlite', b'')
        with self.assertRaises(ValueError): validate(self.pack)

    def test_export_never_replaces_source_or_existing_output(self):
        original = self.db.read_bytes()
        with self.assertRaises(ValueError): export(self.db, self.db)
        self.assertEqual(self.db.read_bytes(), original)
        self.pack.write_bytes(b'keep original output')
        with self.assertRaises(FileExistsError): export(self.db, self.pack)
        self.assertEqual(self.pack.read_bytes(), b'keep original output')

    def test_export_refuses_symlink_destination(self):
        target = self.root / 'sensitive'
        target.write_bytes(b'keep')
        self.pack.symlink_to(target)
        with self.assertRaises(FileExistsError): export(self.db, self.pack)
        self.assertEqual(target.read_bytes(), b'keep')

    def test_archive_traversal_rejected(self):
        with zipfile.ZipFile(self.pack, 'w') as z: z.writestr('../outside', 'no')
        with self.assertRaises(ValueError): validate(self.pack)

if __name__ == '__main__': unittest.main()
