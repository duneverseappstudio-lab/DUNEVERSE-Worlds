import 'dart:convert';

import 'authored_orbit.dart';

import 'package:sqlite3/sqlite3.dart';

/// Phase-zero persistence spike. Not the final world schema.
class ForgeStore {
  final Database db;
  ForgeStore(this.db) {
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version > 2) {
      throw StateError('Database is newer than this build; refusing to open');
    }
    db.execute('PRAGMA foreign_keys=ON');
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=FULL');
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute(
        '''CREATE TABLE IF NOT EXISTS worlds(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, schema_version INTEGER NOT NULL)''',
      );
      db.execute('''CREATE TABLE IF NOT EXISTS objects(
      id TEXT PRIMARY KEY, world_id TEXT NOT NULL REFERENCES worlds(id),
      kind TEXT NOT NULL, name TEXT NOT NULL, x REAL NOT NULL, y REAL NOT NULL,
      radius REAL NOT NULL CHECK(radius>0))''');
      db.execute('''CREATE TABLE IF NOT EXISTS changes(
      id INTEGER PRIMARY KEY AUTOINCREMENT, world_id TEXT NOT NULL REFERENCES worlds(id),
      object_id TEXT NOT NULL, before_json TEXT, after_json TEXT NOT NULL)''');
      db.execute('''CREATE TABLE IF NOT EXISTS authored_orbits(
        body_id TEXT PRIMARY KEY REFERENCES objects(id),
        center_id TEXT NOT NULL REFERENCES objects(id),
        seconds REAL NOT NULL CHECK(seconds>=1 AND seconds<=3600),
        clockwise INTEGER NOT NULL CHECK(clockwise IN(0,1)))''');
      // Refuse partial/conflicting base tables before advancing the version.
      for (final entry in {
        'worlds': 'id,name,schema_version',
        'objects': 'id,world_id,kind,name,x,y,radius',
        'changes': 'id,world_id,object_id,before_json,after_json',
      }.entries) {
        final type = db.select('SELECT type FROM sqlite_master WHERE name=?', [
          entry.key,
        ]);
        if (type.length != 1 || type.single['type'] != 'table') {
          throw StateError('Invalid base storage schema');
        }
        db.select('SELECT ${entry.value} FROM ${entry.key} LIMIT 0');
      }
      // IF NOT EXISTS must not accept a conflicting view or malformed table.
      final orbitTable = db.select(
        "SELECT type FROM sqlite_master WHERE name='authored_orbits'",
      );
      if (orbitTable.length != 1 || orbitTable.single['type'] != 'table') {
        throw StateError('Invalid orbit storage schema');
      }
      db.select(
        'SELECT body_id,center_id,seconds,clockwise FROM authored_orbits LIMIT 0',
      );
      db.execute('PRAGMA user_version=2');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
  void ensureWorld(String id, String name) =>
      db.execute('INSERT OR IGNORE INTO worlds VALUES(?,?,1)', [id, name]);
  List<ForgeWorld> worlds() => db
      .select('SELECT id,name FROM worlds ORDER BY rowid')
      .map((row) => ForgeWorld(row['id'] as String, row['name'] as String))
      .toList();
  void createWorld(String id, String name) {
    validateObjectName(name);
    if (id.trim().isEmpty) throw ArgumentError('World ID cannot be empty');
    db.execute('INSERT INTO worlds(id,name,schema_version) VALUES(?,?,1)', [
      id,
      name.trim(),
    ]);
  }

  List<SpaceObject> objects(String worldId) => db
      .select('SELECT * FROM objects WHERE world_id=? ORDER BY rowid', [
        worldId,
      ])
      .map(SpaceObject.fromRow)
      .toList();
  void save(
    String worldId,
    SpaceObject object, {
    SpaceObject? expectedGeometry,
    String? expectedName,
  }) {
    if (![object.x, object.y, object.radius].every((n) => n.isFinite) ||
        object.radius <= 0) {
      throw ArgumentError('Invalid geometry');
    }
    if (expectedGeometry != null && expectedName != null) {
      throw ArgumentError('One edit domain per transaction');
    }
    if (expectedName != null) validateObjectName(object.name);
    db.execute('BEGIN IMMEDIATE');
    try {
      final previous = db.select('SELECT * FROM objects WHERE id=?', [
        object.id,
      ]);
      if (previous.isNotEmpty && previous.first['world_id'] != worldId) {
        throw StateError('Object belongs to another world');
      }
      if (expectedGeometry != null) {
        if (previous.length != 1) {
          throw StateError('Preview target no longer exists');
        }
        final durable = SpaceObject.fromRow(previous.single);
        if (durable.x != expectedGeometry.x ||
            durable.y != expectedGeometry.y ||
            durable.radius != expectedGeometry.radius ||
            durable.id != expectedGeometry.id) {
          throw StateError('Target geometry changed during preview');
        }
        // Geometry edits do not own a concurrent rename.
        object = SpaceObject(
          durable.id,
          durable.kind,
          durable.name,
          object.x,
          object.y,
          object.radius,
        );
      }
      if (expectedName != null) {
        if (previous.length != 1 || previous.single['name'] != expectedName) {
          throw StateError('Name changed or target no longer exists');
        }
        final durable = SpaceObject.fromRow(previous.single);
        object = SpaceObject(
          durable.id,
          durable.kind,
          object.name.trim(),
          durable.x,
          durable.y,
          durable.radius,
        );
        if (object.name == durable.name) {
          db.execute('COMMIT');
          return;
        }
      }
      db.execute(
        '''INSERT INTO objects VALUES(?,?,?,?,?,?,?) ON CONFLICT(id)
        DO UPDATE SET name=excluded.name,x=excluded.x,y=excluded.y,radius=excluded.radius''',
        [
          object.id,
          worldId,
          object.kind,
          object.name,
          object.x,
          object.y,
          object.radius,
        ],
      );
      authoredMotion(objects(worldId), orbits(worldId));
      db.execute(
        'INSERT INTO changes(world_id,object_id,before_json,after_json) VALUES(?,?,?,?)',
        [
          worldId,
          object.id,
          previous.isEmpty ? null : jsonEncode(previous.first),
          jsonEncode(object.toJson()),
        ],
      );
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<AuthoredOrbit> orbits(String worldId) => db
      .select(
        'SELECT a.* FROM authored_orbits a JOIN objects o ON a.body_id=o.id WHERE o.world_id=? ORDER BY a.rowid',
        [worldId],
      )
      .map(
        (r) => AuthoredOrbit(
          r['body_id'] as String,
          r['center_id'] as String,
          (r['seconds'] as num).toDouble(),
          r['clockwise'] == 1,
        ),
      )
      .toList();

  void saveOrbit(String worldId, AuthoredOrbit orbit) =>
      changeOrbit(worldId, orbit.bodyId, orbit);

  void removeOrbit(String worldId, String bodyId) {
    if (!objects(worldId).any((o) => o.id == bodyId)) return;
    changeOrbit(worldId, bodyId, null);
  }

  /// Read, compare and write under one transaction. Expected null means absent.
  void changeOrbit(
    String worldId,
    String bodyId,
    AuthoredOrbit? next, {
    bool compare = false,
    AuthoredOrbit? expected,
  }) {
    db.execute('BEGIN IMMEDIATE');
    try {
      if (!objects(worldId).any((o) => o.id == bodyId) ||
          (next != null && next.bodyId != bodyId)) {
        throw ArgumentError('Orbit body does not belong to this world');
      }
      final existing = orbits(worldId);
      final matching = existing.where((o) => o.bodyId == bodyId);
      final current = matching.isEmpty ? null : matching.single;
      if (compare && !sameOrbit(current, expected)) {
        throw StateError('Orbit changed since this edit');
      }
      final proposed = existing.where((o) => o.bodyId != bodyId).toList();
      if (next != null) proposed.add(next);
      authoredMotion(objects(worldId), proposed);
      if (next == null) {
        db.execute('DELETE FROM authored_orbits WHERE body_id=?', [bodyId]);
      } else {
        db.execute(
          'INSERT INTO authored_orbits VALUES(?,?,?,?) ON CONFLICT(body_id) DO UPDATE SET center_id=excluded.center_id,seconds=excluded.seconds,clockwise=excluded.clockwise',
          [next.bodyId, next.centerId, next.seconds, next.clockwise ? 1 : 0],
        );
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => db.close();
}

class SpaceObject {
  final String id, kind, name;
  final double x, y, radius;
  const SpaceObject(this.id, this.kind, this.name, this.x, this.y, this.radius);
  factory SpaceObject.fromRow(Map<String, Object?> row) => SpaceObject(
    row['id'] as String,
    row['kind'] as String,
    row['name'] as String,
    (row['x'] as num).toDouble(),
    (row['y'] as num).toDouble(),
    (row['radius'] as num).toDouble(),
  );
  SpaceObject move(double x, double y) =>
      SpaceObject(id, kind, name, x, y, radius);
  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind,
    'name': name,
    'x': x,
    'y': y,
    'radius': radius,
  };
}

/// Prototype limit, measured in Unicode code points, not UTF-16 code units.
void validateObjectName(String value) {
  final name = value.trim();
  if (name.isEmpty ||
      name.runes.length > 80 ||
      name.runes.any(
        (c) => c < 32 || (c >= 127 && c <= 159) || c == 0x2028 || c == 0x2029,
      )) {
    throw ArgumentError('Name must contain 1 to 80 visible code points');
  }
}

class ForgeWorld {
  final String id, name;
  const ForgeWorld(this.id, this.name);
}
