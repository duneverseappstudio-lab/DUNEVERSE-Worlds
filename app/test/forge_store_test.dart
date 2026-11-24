import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/forge_store.dart';

void main() {
  test('newer database version is rejected without modification', () {
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA user_version=3');
    expect(() => ForgeStore(db), throwsStateError);
    expect(db.select('PRAGMA user_version').first.values.first, 3);
    expect(
      db.select("SELECT name FROM sqlite_master WHERE type='table'"),
      isEmpty,
    );
    db.close();
  });
  test('file storage enables durable WAL commits', () {
    final dir = Directory.systemTemp.createTempSync('iwf-wal-');
    final s = ForgeStore(sqlite3.open('${dir.path}/world.db'));
    expect(s.db.select('PRAGMA journal_mode').first.values.first, 'wal');
    expect(s.db.select('PRAGMA synchronous').first.values.first, 2);
    s.close();
    dir.deleteSync(recursive: true);
  });
  test('SQLite reopen preserves stable IDs and coordinates', () {
    final dir = Directory.systemTemp.createTempSync('iwf-test-');
    final path = '${dir.path}/world.db';
    var s = ForgeStore(sqlite3.open(path));
    s.ensureWorld('a', 'عالم');
    s.save('a', const SpaceObject('planet-1', 'planet', 'كوكب', .2, .3, .04));
    s.close();
    s = ForgeStore(sqlite3.open(path));
    final o = s.objects('a').single;
    expect(o.id, 'planet-1');
    expect(o.x, .2);
    expect(o.name, 'كوكب');
    expect(s.db.select('PRAGMA integrity_check').first.values.first, 'ok');
    s.close();
    dir.deleteSync(recursive: true);
  });
  test('world crossing and invalid geometry rejected transactionally', () {
    final s = ForgeStore(sqlite3.openInMemory());
    s.ensureWorld('a', 'A');
    s.ensureWorld('b', 'B');
    s.save('a', const SpaceObject('id', 'planet', 'A', .2, .3, .04));
    expect(
      () => s.save('b', const SpaceObject('id', 'planet', 'B', .8, .3, .04)),
      throwsStateError,
    );
    expect(s.objects('a').single.name, 'A');
    expect(s.objects('b'), isEmpty);
    expect(
      () => s.save('a', SpaceObject('bad', 'planet', 'B', double.nan, .3, .04)),
      throwsArgumentError,
    );
    expect(s.db.select('SELECT * FROM changes'), hasLength(1));
    s.close();
  });
}
