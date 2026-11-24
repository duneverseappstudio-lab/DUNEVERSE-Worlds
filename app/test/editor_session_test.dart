import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/editor_session.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/render_contract.dart';

void main() {
  late ForgeStore store;
  late EditorSession session;
  setUp(() {
    store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('w', 'تجربة');
    store.ensureWorld('other', 'آخر');
    store.save('w', const SpaceObject('a', 'planet', 'أرض', .1, .2, .03));
    store.save('w', const SpaceObject('b', 'star', 'شمس', .8, .7, .05));
    store.save(
      'other',
      const SpaceObject('hidden', 'star', 'آخر', .5, .5, .05),
    );
    session = EditorSession(store, 'w');
  });
  tearDown(() => store.close());
  int changes() =>
      store.db.select('SELECT count(*) AS n FROM changes').first['n'] as int;

  test('100 previews change no SQL; explicit commit writes exactly once', () {
    final before = changes();
    for (var i = 0; i < 100; i++) {
      session.preview(MoveIntent('a', i / 100, .4, 0));
    }
    expect(store.objects('w').first.x, .1);
    expect(changes(), before);
    expect(session.objects.first.x, .99);
    session.commitPreview();
    expect(store.objects('w').first.x, .99);
    expect(store.objects('w').last.x, .8);
    expect(changes(), before + 1);
    session.commitPreview();
    expect(changes(), before + 1);
  });
  test(
    'cancel restores durable coordinates and selection creates no write',
    () {
      final before = changes();
      session.preview(const SelectIntent('a'));
      session.preview(const MoveIntent('a', .4, .5, 0));
      session.cancelPreview();
      expect(session.objects.first.x, .1);
      expect(session.selected, 'a');
      expect(session.hasPreview, false);
      expect(changes(), before);
    },
  );
  test('invalid direct renderer intents never modify preview or database', () {
    final before = changes();
    for (final intent in <RenderIntent>[
      const SelectIntent('hidden'),
      const MoveIntent('missing', .3, .4, 0),
      const MoveIntent('a', double.nan, .4, 0),
      const MoveIntent('a', .4, .4, 1),
      const MoveIntent('a', -1, .4, 0),
      const MoveIntent('a', .4, 2, 0),
    ]) {
      expect(() => session.preview(intent), throwsArgumentError);
    }
    expect(session.objects.first.x, .1);
    expect(changes(), before);
  });
  test('one gesture cannot silently switch pending target', () {
    session.preview(const MoveIntent('a', .4, .5, 0));
    expect(
      () => session.preview(const MoveIntent('b', .1, .2, 0)),
      throwsStateError,
    );
    expect(session.objects.last.x, .8);
  });
  test('failed transaction restores view and writes no change row', () {
    final before = changes();
    store.db.execute(
      "CREATE TRIGGER reject_move BEFORE UPDATE ON objects BEGIN SELECT RAISE(ABORT,'fixture failure'); END",
    );
    session.preview(const MoveIntent('a', .4, .5, 0));
    expect(session.commitPreview, throwsA(isA<SqliteException>()));
    expect(session.objects.first.x, .1);
    expect(session.hasPreview, false);
    expect(changes(), before);
  });
  test('concurrent geometry edit is not overwritten by stale gesture', () {
    session.preview(const MoveIntent('a', .4, .5, 0));
    store.save('w', store.objects('w').first.move(.6, .6));
    final before = changes();
    expect(session.commitPreview, throwsStateError);
    expect(session.objects.first.x, .6);
    expect(changes(), before);
  });
  test('movement preserves a concurrent non-geometric rename', () {
    session.preview(const MoveIntent('a', .4, .5, 0));
    store.save('w', const SpaceObject('a', 'planet', 'اسم جديد', .1, .2, .03));
    session.commitPreview();
    expect(session.objects.first.name, 'اسم جديد');
    expect(session.objects.first.x, .4);
  });
  test('deleted target is not silently re-created', () {
    session.preview(const MoveIntent('a', .4, .5, 0));
    store.db.execute("DELETE FROM objects WHERE id='a'");
    expect(session.commitPreview, throwsStateError);
    expect(session.objects.map((o) => o.id), ['b']);
    expect(session.selected, isNull);
  });
  test('committed renderer move survives actual disk close and reopen', () {
    final dir = Directory.systemTemp.createTempSync('forge-intent-');
    final path = '${dir.path}/fixture.sqlite';
    try {
      final disk = ForgeStore(sqlite3.open(path));
      disk.ensureWorld('w', 'اختبار');
      disk.save('w', const SpaceObject('a', 'planet', 'أرض', .1, .2, .03));
      final editor = EditorSession(disk, 'w');
      editor.preview(const MoveIntent('a', .6, .7, 0));
      editor.commitPreview();
      disk.close();
      final reopened = ForgeStore(sqlite3.open(path));
      expect(reopened.objects('w').single.x, .6);
      expect(reopened.objects('w').single.name, 'أرض');
      reopened.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
  test(
    'journal insertion failure rolls back object update and clears preview',
    () {
      final before = changes();
      store.db.execute(
        "CREATE TRIGGER reject_change BEFORE INSERT ON changes BEGIN SELECT RAISE(ABORT,'fixture journal failure'); END",
      );
      session.preview(const MoveIntent('a', .4, .5, 0));
      expect(session.commitPreview, throwsA(isA<SqliteException>()));
      expect(store.objects('w').first.x, .1);
      expect(session.objects.first.x, .1);
      expect(changes(), before);
    },
  );
  test('separate database connection edit is detected at commit', () {
    final dir = Directory.systemTemp.createTempSync('forge-conflict-');
    final path = '${dir.path}/fixture.sqlite';
    final first = ForgeStore(sqlite3.open(path));
    final second = ForgeStore(sqlite3.open(path));
    try {
      first.ensureWorld('w', 'اختبار');
      first.save('w', const SpaceObject('a', 'planet', 'أرض', .1, .2, .03));
      final editor = EditorSession(first, 'w');
      editor.preview(const MoveIntent('a', .6, .7, 0));
      second.save('w', second.objects('w').single.move(.8, .8));
      expect(editor.commitPreview, throwsStateError);
      expect(first.objects('w').single.x, .8);
      expect(editor.objects.single.x, .8);
      expect(
        first.db.select('SELECT count(*) AS n FROM changes').first['n'],
        2,
      );
    } finally {
      first.close();
      second.close();
      dir.deleteSync(recursive: true);
    }
  });
  test(
    'pending edit cannot change selected entity until explicitly cancelled',
    () {
      session.preview(const MoveIntent('a', .4, .5, 0));
      expect(() => session.preview(const SelectIntent('b')), throwsStateError);
      expect(store.objects('w').first.x, .1);
      session.cancelPreview();
      session.preview(const SelectIntent('b'));
      expect(session.selected, 'b');
    },
  );
}
