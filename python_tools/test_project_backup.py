"""Disposable synthetic Flutter-schema project snapshots, no user databases."""
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
import zipfile
import worldpack

class ProjectBackupTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.db=self.root/'synthetic.sqlite';self.pack=self.root/'project.iwfproject'
        c=sqlite3.connect(self.db)
        c.executescript("""PRAGMA user_version=2;
        CREATE TABLE worlds(id TEXT PRIMARY KEY,name TEXT,schema_version INTEGER);
        CREATE TABLE objects(id TEXT PRIMARY KEY,world_id TEXT REFERENCES worlds(id),kind TEXT,name TEXT,x REAL,y REAL,radius REAL);
        CREATE TABLE changes(id INTEGER PRIMARY KEY,world_id TEXT,object_id TEXT,before_json TEXT,after_json TEXT);
        CREATE TABLE authored_orbits(body_id TEXT PRIMARY KEY REFERENCES objects(id),center_id TEXT REFERENCES objects(id),seconds REAL,clockwise INTEGER);
        INSERT INTO worlds VALUES('a','A',1),('b','B',1);
        INSERT INTO objects VALUES('s','a','star','S',.4,.5,.03),('p','a','planet','P',.6,.5,.02),('m','a','moon','M',.65,.5,.01),('r','b','rock','R',.2,.3,.01);
        INSERT INTO authored_orbits VALUES('p','s',60,0),('m','p',12,1);
        INSERT INTO changes VALUES(1,'a','p',NULL,'synthetic');""")
        c.close()
    def tearDown(self):self.tmp.cleanup()
    def rows(self,path):
        c=sqlite3.connect(path)
        try:return {t:c.execute('select * from '+t+' order by rowid').fetchall() for t in ('worlds','objects','changes','authored_orbits')}
        finally:c.close()
    def test_complete_project_roundtrip_includes_worlds_journal_paths_and_speeds(self):
        before=self.db.read_bytes();expected=self.rows(self.db)
        worldpack.export(self.db,self.pack,project=True)
        manifest,_=worldpack.validate(self.pack)
        self.assertEqual(manifest['world_ids'],['a','b'])
        worldpack.restore(self.pack,self.root/'restored')
        self.assertEqual(self.rows(self.root/'restored/world.sqlite'),expected)
        self.assertEqual(self.db.read_bytes(),before)
        with self.assertRaises(FileExistsError):worldpack.restore(self.pack,self.root/'restored')
        with self.assertRaises(FileExistsError):worldpack.export(self.db,self.pack,project=True)
    def test_legacy_export_still_refuses_multiworld(self):
        with self.assertRaises(ValueError):worldpack.export(self.db,self.pack)
        self.assertFalse(self.pack.exists())
    def test_invalid_world_and_cycle_or_zero_radius_never_publish(self):
        for update in ("UPDATE authored_orbits SET center_id='r' WHERE body_id='p'", "INSERT INTO authored_orbits VALUES('s','m',24,0)", "UPDATE objects SET x=.4,y=.5 WHERE id='p'", "UPDATE authored_orbits SET seconds=0"):
            c=sqlite3.connect(self.db);c.execute('BEGIN');c.execute(update);c.commit();c.close()
            with self.assertRaises(ValueError):worldpack.export(self.db,self.pack,project=True)
            self.assertFalse(self.pack.exists())
            self.tearDown();self.setUp()
    def test_tampered_manifest_and_bytes_rejected_no_restore(self):
        worldpack.export(self.db,self.pack,project=True)
        manifest,data=worldpack.validate(self.pack)
        for identity in (['b','a'],['a'],['a','a'],[True]):
            manifest['world_ids']=identity
            bad=self.root/'bad.zip'
            with zipfile.ZipFile(bad,'w') as z:z.writestr('manifest.json',json.dumps(manifest));z.writestr('world.sqlite',data)
            with self.assertRaises(ValueError):worldpack.restore(bad,self.root/'bad-restore')
            self.assertFalse((self.root/'bad-restore').exists())
        manifest['world_ids']=['a','b']
        with zipfile.ZipFile(bad,'w') as z:z.writestr('manifest.json',json.dumps(manifest));z.writestr('world.sqlite',data+b'x')
        with self.assertRaises(ValueError):worldpack.validate(bad)
    def test_live_wal_snapshot_is_committed_consistent_and_source_not_changed(self):
        c=sqlite3.connect(self.db);c.execute('pragma journal_mode=WAL');c.execute("UPDATE worlds SET name='Committed' WHERE id='b'");c.commit()
        expected=self.rows(self.db)
        c.execute("UPDATE worlds SET name='Uncommitted' WHERE id='b'")
        worldpack.export(self.db,self.pack,project=True)
        worldpack.restore(self.pack,self.root/'wal-copy')
        self.assertEqual(self.rows(self.root/'wal-copy/world.sqlite'),expected)
        c.rollback();c.close()
