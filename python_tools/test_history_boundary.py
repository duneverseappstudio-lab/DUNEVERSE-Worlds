"""Review regressions with disposable project fixtures, never real app data."""
import hashlib
import json
import os
import sqlite3
import unittest
from unittest.mock import patch
import zipfile
import worldpack as w
import test_project_backup as fixtures

class HistoryBoundary(unittest.TestCase):
    def fixture(self):
        f=fixtures.ProjectBackupTest();f.setUp();self.addCleanup(f.tearDown);return f

    def reject(self,sql):
        f=self.fixture();c=sqlite3.connect(f.db);c.executescript(sql);c.close()
        before=f.db.read_bytes()
        with self.assertRaises(ValueError):w.export(f.db,f.pack,project=True)
        self.assertFalse(f.pack.exists());self.assertEqual(f.db.read_bytes(),before)
        m=dict(format='iwfproject',schema_version=2,world_ids=['a','b'],sha256=hashlib.sha256(before).hexdigest())
        with zipfile.ZipFile(f.pack,'w') as z:
            z.writestr('manifest.json',json.dumps(m));z.writestr('world.sqlite',before)
        with self.assertRaises(ValueError):w.restore(f.pack,f.root/'rejected')
        self.assertFalse((f.root/'rejected').exists())

    def test_history_foreign_object_and_world_identity(self):
        for sql in ("UPDATE changes SET object_id='missing'", "UPDATE changes SET object_id='r'", "UPDATE changes SET world_id='b'", "UPDATE changes SET id=0"):
            with self.subTest(sql=sql):self.reject(sql)

    def test_history_json_shape_and_identity(self):
        for sql in ("UPDATE changes SET after_json='bad'", "UPDATE changes SET before_json='[]'", "UPDATE changes SET after_json='{}'", "UPDATE changes SET after_json=NULL", "UPDATE changes SET after_json=replace(after_json,'\"p\"','\"r\"')"):
            with self.subTest(sql=sql):self.reject(sql)

    def test_history_geometry_and_names(self):
        for sql in ("UPDATE changes SET after_json=replace(after_json,'0.6','1e300')", "UPDATE changes SET after_json=replace(after_json,'\"P\"','\"\"')", "UPDATE changes SET before_json=replace(after_json,'0.02','true')"):
            with self.subTest(sql=sql):self.reject(sql)

    def test_world_metadata(self):
        for sql in ("UPDATE worlds SET name=''", "UPDATE worlds SET schema_version=99", "UPDATE worlds SET name='x'||char(8238)||'y'"):
            with self.subTest(sql=sql):self.reject(sql)

    def test_duplicate_history_ids_without_declared_constraints(self):
        self.reject('CREATE TABLE old_changes AS SELECT * FROM changes; DROP TABLE changes; ALTER TABLE old_changes RENAME TO changes; INSERT INTO changes SELECT * FROM changes;')

    def test_valid_before_and_after_snapshots_match_real_app_shapes(self):
        f=self.fixture();c=sqlite3.connect(f.db)
        before=dict(id='p',world_id='a',kind='planet',name='Old',x=.5,y=.4,radius=.02)
        c.execute('UPDATE changes SET before_json=?',(json.dumps(before),));c.commit();c.close()
        w.export(f.db,f.pack,project=True);w.restore(f.pack,f.root/'valid')
        self.assertTrue((f.root/'valid/world.sqlite').is_file())

    def test_world_writable_parent_refused(self):
        f=self.fixture();shared=f.root/'shared';shared.mkdir();shared.chmod(0o777)
        with self.assertRaises(PermissionError):w.export(f.db,shared/'x',project=True)
        w.export(f.db,f.pack,project=True)
        with self.assertRaises(PermissionError):w.restore(f.pack,shared/'x')
        self.assertEqual(list(shared.iterdir()),[])

    def test_restore_staging_directory_replacement_detected(self):
        f=self.fixture();w.export(f.db,f.pack,project=True)
        def hook(stage):
            if stage=='restore_before_publish':
                p=next(f.root.glob('.iwf-restore-*'));p.rename(f.root/'original-stage');p.mkdir();(p/'world.sqlite').write_bytes(b'replacement')
        with patch.object(w,'_checkpoint',hook),self.assertRaises(ValueError):w.restore(f.pack,f.root/'rejected')
        self.assertFalse((f.root/'rejected').exists())

    def test_same_inode_restore_modification_detected(self):
        f=self.fixture();w.export(f.db,f.pack,project=True)
        def hook(stage):
            if stage=='restore_before_publish':next(f.root.glob('.iwf-restore-*')).joinpath('world.sqlite').write_bytes(b'changed')
        with patch.object(w,'_checkpoint',hook),self.assertRaises(ValueError):w.restore(f.pack,f.root/'rejected')
        self.assertFalse((f.root/'rejected').exists())

    def test_export_staging_replacement_and_modification_detected(self):
        for rename in (False,True):
            with self.subTest(rename=rename):
                f=self.fixture()
                def hook(stage):
                    if stage=='export_before_publish':
                        p=next(f.root.glob('.iwf-export-*'))
                        if rename:p.rename(f.root/'original-stage')
                        p.write_bytes(b'changed')
                with patch.object(w,'_checkpoint',hook),self.assertRaises(ValueError):w.export(f.db,f.pack,project=True)
                self.assertFalse(f.pack.exists())
