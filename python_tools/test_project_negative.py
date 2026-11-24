"""Reject partial or semantically corrupt disposable project snapshots."""
import sqlite3
import unittest
import worldpack
import test_project_backup as fixtures

class NegativeProjectTest(unittest.TestCase):
    def test_reject_partial_schemas_without_publishing_or_source_changes(self):
        for mutation in [
            'DROP TABLE authored_orbits',
            'DROP TABLE changes',
            'DROP TABLE objects',
            'ALTER TABLE objects RENAME COLUMN radius TO wrong_radius',
            'DROP TABLE authored_orbits; CREATE VIEW authored_orbits AS SELECT 1',
            "UPDATE objects SET radius=-1 WHERE id='p'",
            "UPDATE objects SET x='not a number' WHERE id='p'",
            "UPDATE objects SET world_id='missing' WHERE id='p'",
            "UPDATE changes SET world_id='missing'",
            "UPDATE authored_orbits SET seconds='wrong' WHERE body_id='p'",
            "UPDATE authored_orbits SET clockwise=7 WHERE body_id='p'",
            "UPDATE objects SET name='' WHERE id='p'",
        ]:
            with self.subTest(mutation=mutation):
                f=fixtures.ProjectBackupTest();f.setUp()
                try:
                    c=sqlite3.connect(f.db);c.executescript(mutation);c.close()
                    before=f.db.read_bytes()
                    with self.assertRaises((ValueError,sqlite3.DatabaseError)):
                        worldpack.export(f.db,f.pack,project=True)
                    self.assertFalse(f.pack.exists())
                    self.assertEqual(f.db.read_bytes(),before)
                finally:f.tearDown()
