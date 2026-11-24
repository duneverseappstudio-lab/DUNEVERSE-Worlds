import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/authored_orbit.dart';

void fixture(ForgeStore s) {
  s.ensureWorld('w', 'Test');
  s.ensureWorld('other', 'Other');
  for (final o in [
    const SpaceObject('s', 'star', 'S', .4, .5, .03),
    const SpaceObject('p', 'planet', 'P', .6, .5, .02),
    const SpaceObject('m', 'moon', 'M', .65, .5, .01),
    const SpaceObject('r', 'rock', 'R', .3, .5, .01),
  ]) {
    s.save('w', o);
  }
  s.save('other', const SpaceObject('alien', 'planet', 'Alien', .8, .5, .03));
}

void main() {
  test(
    'partial old schemas refuse upgrade and preserve original schema/version',
    () {
      for (final ddl in [
        'CREATE TABLE objects(id TEXT PRIMARY KEY)',
        'CREATE TABLE worlds(id TEXT PRIMARY KEY)',
        'CREATE TABLE changes(id INTEGER PRIMARY KEY)',
        'CREATE VIEW objects AS SELECT 1',
      ]) {
        final db = sqlite3.openInMemory();
        db.execute(ddl);
        db.execute('PRAGMA user_version=1');
        final before = db
            .select('SELECT type,name,sql FROM sqlite_master ORDER BY name')
            .toString();
        expect(() => ForgeStore(db), throwsA(anything));
        expect(db.select('PRAGMA user_version').first.values.first, 1);
        expect(
          db
              .select('SELECT type,name,sql FROM sqlite_master ORDER BY name')
              .toString(),
          before,
        );
        db.close();
      }
    },
  );

  test('independent periods directions and moving host never snap initial geometry', () {
    final s = ForgeStore(sqlite3.openInMemory());
    fixture(s);
    s.saveOrbit('w', const AuthoredOrbit('p', 's', 12, false));
    s.saveOrbit('w', const AuthoredOrbit('m', 'p', 4, true));
    s.saveOrbit('w', const AuthoredOrbit('r', 's', 24, false));
    final model = authoredMotion(s.objects('w'), s.orbits('w'));
    for (final o in s.objects('w')) {
      expect(model.at(0)[o.id]!.x, closeTo(o.x - .5, 1e-9));
      expect(model.at(0)[o.id]!.y, closeTo(o.y - .5, 1e-9));
    }
    final one = model.at(1), three = model.at(3);
    expect(one['m']!.x, closeTo(one['p']!.x, 1e-9));
    expect(one['m']!.y - one['p']!.y, closeTo(-.05, 1e-9));
    expect(three['p']!.x, closeTo(-.1, 1e-9));
    expect(three['p']!.y, closeTo(.2, 1e-9));
    expect(model.at(24)['r']!.x, closeTo(-.2, 1e-9));
    expect(model.at(1)['r']!.y, closeTo(-.1 * math.sin(math.pi / 12), 1e-9));
    s.close();
  });
  test('cycles self hosts other worlds invalid speed and zero radius reject atomically', () {
    final s = ForgeStore(sqlite3.openInMemory());
    fixture(s);
    s.saveOrbit('w', const AuthoredOrbit('p', 's', 12, false));
    final before = s.db.select('select * from authored_orbits').toString();
    for (final o in [
      const AuthoredOrbit('s', 'p', 24, false),
      const AuthoredOrbit('p', 'p', 24, false),
      const AuthoredOrbit('p', 'alien', 24, false),
      const AuthoredOrbit('alien', 's', 24, false),
      const AuthoredOrbit('p', 's', 0, false),
      const AuthoredOrbit('p', 's', double.nan, false),
      const AuthoredOrbit('p', 's', 3601, false),
    ]) {
      expect(() => s.saveOrbit('w', o), throwsArgumentError);
      expect(s.db.select('select * from authored_orbits').toString(), before);
    }
    final geometry = s.objects('w').map((o) => o.toJson()).toString();
    final journal = s.db.select('select * from changes').toString();
    expect(
      () => s.save(
        'w',
        s.objects('w').firstWhere((o) => o.id == 'p').move(.4, .5),
      ),
      throwsArgumentError,
    );
    expect(s.objects('w').map((o) => o.toJson()).toString(), geometry);
    expect(s.db.select('select * from changes').toString(), journal);
    s.removeOrbit('other', 'p');
    expect(s.orbits('w'), hasLength(1));
    s.removeOrbit('w', 'p');
    expect(s.orbits('w'), isEmpty);
    expect(s.objects('w'), hasLength(4));
    s.close();
  });
  test('v1 upgrade preserves exact objects journals worlds and durable orbit reopen', () {
    final dir = Directory.systemTemp.createTempSync('orbits-migration-');
    final path = '${dir.path}/synthetic.sqlite';
    final db = sqlite3.open(path);
    db.execute(
      'CREATE TABLE worlds(id TEXT PRIMARY KEY,name TEXT NOT NULL,schema_version INTEGER NOT NULL)',
    );
    db.execute(
      'CREATE TABLE objects(id TEXT PRIMARY KEY,world_id TEXT NOT NULL REFERENCES worlds(id),kind TEXT NOT NULL,name TEXT NOT NULL,x REAL NOT NULL,y REAL NOT NULL,radius REAL NOT NULL CHECK(radius>0))',
    );
    db.execute(
      'CREATE TABLE changes(id INTEGER PRIMARY KEY AUTOINCREMENT,world_id TEXT NOT NULL REFERENCES worlds(id),object_id TEXT NOT NULL,before_json TEXT,after_json TEXT NOT NULL)',
    );
    db.execute("INSERT INTO worlds VALUES('w','Synthetic',1)");
    db.execute(
      "INSERT INTO objects VALUES('s','w','star','S',.4,.5,.03),('p','w','planet','P',.6,.5,.02)",
    );
    db.execute(
      "INSERT INTO changes(world_id,object_id,after_json) VALUES('w','p','synthetic')",
    );
    db.execute('PRAGMA user_version=1');
    final before = [
      for (final table in ['objects', 'worlds', 'changes'])
        db.select('SELECT * FROM $table').toString(),
    ];
    db.close();
    var s = ForgeStore(sqlite3.open(path));
    expect(s.db.select('pragma user_version').first.values.first, 2);
    expect([
      for (final table in ['objects', 'worlds', 'changes'])
        s.db.select('SELECT * FROM $table').toString(),
    ], before);
    s.saveOrbit('w', const AuthoredOrbit('p', 's', 17, true));
    s.close();
    s = ForgeStore(sqlite3.open(path));
    expect(s.orbits('w').single.seconds, 17);
    expect(s.orbits('w').single.clockwise, isTrue);
    expect(s.db.select('pragma integrity_check').first.values.first, 'ok');
    expect(s.db.select('pragma foreign_key_check'), isEmpty);
    s.close();
    dir.deleteSync(recursive: true);
  });
  test('failed additive upgrade rolls schema and version back', () {
    final db = sqlite3.openInMemory();
    db.execute('CREATE VIEW authored_orbits AS SELECT 1');
    db.execute('PRAGMA user_version=1');
    expect(() => ForgeStore(db), throwsStateError);
    expect(db.select('pragma user_version').first.values.first, 1);
    expect(
      db.select("SELECT name FROM sqlite_master WHERE type='table'"),
      isEmpty,
    );
    db.close();
  });
}
