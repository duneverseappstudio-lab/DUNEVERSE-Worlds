"""Exact-source review regressions, disposable synthetic fixtures only."""
import hashlib
import json
import sqlite3
import unittest
import zipfile
import worldpack
import test_project_backup as fixtures

class ReviewBoundary(unittest.TestCase):
    def test_untrusted_project_schema_and_geometry_never_publish(self):
        mutations = [
            "CREATE TRIGGER surprise AFTER UPDATE ON objects BEGIN UPDATE worlds SET name='changed'; END",
            'CREATE VIEW extra AS SELECT * FROM objects',
            'CREATE TABLE extra(payload TEXT)',
            'CREATE INDEX extra_index ON objects(name)',
            "ALTER TABLE objects ADD COLUMN extra TEXT",
            "UPDATE objects SET x=1e200,y=-1e200,radius=50 WHERE id='p'",
            "UPDATE objects SET x=1.1 WHERE id='p'",
            "UPDATE objects SET radius=.001 WHERE id='p'",
            "UPDATE objects SET name='safe'||char(8238)||'name' WHERE id='p'",
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                f=fixtures.ProjectBackupTest();f.setUp()
                try:
                    c=sqlite3.connect(f.db);c.execute(mutation);c.commit();c.close()
                    before=f.db.read_bytes()
                    with self.assertRaises(ValueError):worldpack.export(f.db,f.pack,project=True)
                    self.assertFalse(f.pack.exists());self.assertEqual(f.db.read_bytes(),before)
                    # A forged checksum is no authorization for executable schema.
                    data=f.db.read_bytes(); m=dict(format='iwfproject',schema_version=2,world_ids=['a','b'],sha256=hashlib.sha256(data).hexdigest())
                    with zipfile.ZipFile(f.pack,'w') as z:
                        z.writestr('manifest.json',json.dumps(m));z.writestr('world.sqlite',data)
                    with self.assertRaises(ValueError):worldpack.restore(f.pack,f.root/'rejected')
                    self.assertFalse((f.root/'rejected').exists())
                finally:f.tearDown()
    def test_restored_wal_snapshot_publishes_only_exact_validated_main_file(self):
        f=fixtures.ProjectBackupTest();f.setUp()
        try:
            c=sqlite3.connect(f.db);c.execute('pragma journal_mode=WAL');c.execute("UPDATE worlds SET name='latest' WHERE id='a'");c.commit()
            worldpack.export(f.db,f.pack,project=True);_,data=worldpack.validate(f.pack)
            worldpack.restore(f.pack,f.root/'restored')
            self.assertEqual(sorted(p.name for p in (f.root/'restored').iterdir()),['world.sqlite'])
            self.assertEqual((f.root/'restored/world.sqlite').read_bytes(),data)
            c.close()
        finally:f.tearDown()
    def test_empty_schema_has_consistent_validation_error(self):
        f=fixtures.ProjectBackupTest();f.setUp()
        try:
            empty=f.root/'empty.sqlite';sqlite3.connect(empty).close()
            with self.assertRaises(ValueError):worldpack._check_database(empty,project=True)
        finally:f.tearDown()
    def test_legacy_format_cannot_launder_executable_trigger(self):
        f=fixtures.ProjectBackupTest();f.setUp()
        try:
            c=sqlite3.connect(f.db);c.execute("DELETE FROM authored_orbits");c.execute("DELETE FROM changes");c.execute("DELETE FROM objects WHERE world_id='b'");c.execute("DELETE FROM worlds WHERE id='b'")
            c.execute("CREATE TRIGGER surprise AFTER UPDATE ON objects BEGIN UPDATE worlds SET name='changed'; END");c.commit();c.close()
            with self.assertRaises(ValueError):worldpack.export(f.db,f.pack)
            self.assertFalse(f.pack.exists())
        finally:f.tearDown()

    def test_legacy_envelope_cannot_skip_project_geometry_checks(self):
        f=fixtures.ProjectBackupTest();f.setUp()
        try:
            c=sqlite3.connect(f.db);c.execute('DELETE FROM authored_orbits');c.execute('DELETE FROM changes');c.execute("DELETE FROM objects WHERE world_id='b'");c.execute("DELETE FROM worlds WHERE id='b'");c.execute("UPDATE objects SET radius=50 WHERE id='p'");c.commit();c.close()
            with self.assertRaises(ValueError):worldpack.export(f.db,f.pack)
            self.assertFalse(f.pack.exists())
        finally:f.tearDown()
