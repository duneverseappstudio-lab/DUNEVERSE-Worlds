import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/editor_session.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/render_contract.dart';

void main() {
  late ForgeStore store;
  late EditorSession editor;
  setUp(() {
    store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('w', 'تجربة');
    store.save('w', const SpaceObject('a', 'planet', 'أرض', .1, .2, .03));
    editor = EditorSession(store, 'w');
  });
  tearDown(() => store.close());
  void move(double x) {
    editor.preview(MoveIntent('a', x, .2, 0));
    editor.commitPreview();
  }

  test('undo and redo persist inverse moves in order', () {
    move(.3);
    move(.6);
    expect(editor.canUndo, true);
    editor.undo();
    expect(store.objects('w').single.x, .3);
    editor.undo();
    expect(store.objects('w').single.x, .1);
    expect(editor.canUndo, false);
    editor.redo();
    expect(store.objects('w').single.x, .3);
    editor.redo();
    expect(store.objects('w').single.x, .6);
    expect(editor.canRedo, false);
    expect(store.db.select('SELECT count(*) AS n FROM changes').first['n'], 7);
  });
  test('new edit after undo discards redo,preview and cancellation do not', () {
    move(.3);
    editor.undo();
    editor.preview(const MoveIntent('a', .8, .2, 0));
    editor.cancelPreview();
    expect(editor.canRedo, true);
    move(.5);
    expect(editor.canRedo, false);
    editor.undo();
    expect(editor.objects.single.x, .1);
  });
  test('no-op commit does not write or consume redo', () {
    move(.3);
    editor.undo();
    move(.1);
    expect(editor.canRedo, true);
    expect(store.db.select('SELECT count(*) AS n FROM changes').first['n'], 3);
  });
  test('active preview blocks history until cancelled', () {
    move(.3);
    editor.preview(const MoveIntent('a', .7, .2, 0));
    expect(editor.canUndo, false);
    expect(editor.undo, throwsStateError);
    editor.cancelPreview();
    editor.undo();
    expect(editor.objects.single.x, .1);
  });
  test('failed undo keeps history and durable state for safe retry', () {
    move(.3);
    store.db.execute(
      "CREATE TRIGGER reject_change BEFORE INSERT ON changes BEGIN SELECT RAISE(ABORT,'fixture failure'); END",
    );
    expect(editor.undo, throwsA(isA<SqliteException>()));
    expect(editor.objects.single.x, .3);
    expect(editor.canUndo, true);
    expect(editor.canRedo, false);
    store.db.execute('DROP TRIGGER reject_change');
    editor.undo();
    expect(editor.objects.single.x, .1);
  });
  test('external geometry conflict cannot be overwritten by undo', () {
    move(.3);
    store.save('w', store.objects('w').single.move(.8, .2));
    expect(editor.undo, throwsStateError);
    expect(editor.objects.single.x, .8);
    expect(editor.canUndo, true);
  });
  test('undo preserves external rename and fresh session has no history', () {
    move(.3);
    store.save('w', const SpaceObject('a', 'planet', 'اسم جديد', .3, .2, .03));
    editor.undo();
    expect(editor.objects.single.name, 'اسم جديد');
    expect(EditorSession(store, 'w').canRedo, false);
    expect(EditorSession(store, 'w').canUndo, false);
  });
  test('session history has a bounded100command budget', () {
    for (var i = 1; i <= 120; i++) {
      move(i / 200);
    }
    var count = 0;
    while (editor.canUndo) {
      editor.undo();
      count++;
    }
    expect(count, EditorSession.historyLimit);
    expect(editor.objects.single.x, .1);
  });
}
