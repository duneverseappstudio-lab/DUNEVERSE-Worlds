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
    store.save('w', const SpaceObject('a', 'planet', 'أرض', .2, .3, .04));
    editor = EditorSession(store, 'w');
  });
  tearDown(() => store.close());
  test('resize protocol validates exact fields and direct typed values', () {
    final scene = editor.scene;
    expect(
      parseRenderIntent({
        'type': 'resize',
        'entityId': 'a',
        'radius': .08,
      }, scene),
      isA<ResizeIntent>(),
    );
    for (final message in <Map<String, Object?>>[
      {'type': 'resize', 'entityId': 'a', 'radius': 0},
      {'type': 'resize', 'entityId': 'a', 'radius': double.infinity},
      {'type': 'resize', 'entityId': 'a', 'radius': .08, 'sql': 'bad'},
      {'type': 'resize', 'entityId': 'missing', 'radius': .08},
    ]) {
      expect(() => parseRenderIntent(message, scene), throwsArgumentError);
    }
    for (final value in [double.nan, -1.0, 0.0, double.infinity]) {
      expect(
        () => previewRenderIntent(scene, ResizeIntent('a', value)),
        throwsArgumentError,
      );
    }
  });
  test('resize preview is immutable and only changes intended radius', () {
    final scene = editor.scene;
    final next = previewRenderIntent(scene, const ResizeIntent('a', .08));
    expect(scene.nodes.single.radius, .04);
    expect(next.nodes.single.radius, .08);
    expect(next.nodes.single.x, .2);
  });
  test('resize persists transactionally and undo/redo includes size', () {
    editor.preview(const ResizeIntent('a', .08));
    expect(store.objects('w').single.radius, .04);
    editor.commitPreview();
    expect(store.objects('w').single.radius, .08);
    editor.undo();
    expect(store.objects('w').single.radius, .04);
    editor.redo();
    expect(store.objects('w').single.radius, .08);
  });
  test(
    'combined size and move share one preview transaction and history entry',
    () {
      editor.preview(const ResizeIntent('a', .08));
      editor.preview(const MoveIntent('a', .6, .7, 0));
      editor.commitPreview();
      expect(editor.objects.single.radius, .08);
      expect(editor.objects.single.x, .6);
      expect(
        store.db.select('SELECT count(*) AS n FROM changes').first['n'],
        2,
      );
      editor.undo();
      expect(editor.objects.single.radius, .04);
      expect(editor.objects.single.x, .2);
    },
  );
  test(
    'size bounds cancel and external conflict cannot lose durable state',
    () {
      for (final radius in [.009, .251]) {
        expect(
          () => editor.preview(ResizeIntent('a', radius)),
          throwsArgumentError,
        );
      }
      editor.preview(const ResizeIntent('a', .08));
      editor.cancelPreview();
      expect(editor.objects.single.radius, .04);
      editor.preview(const ResizeIntent('a', .08));
      store.save('w', const SpaceObject('a', 'planet', 'أرض', .2, .3, .06));
      expect(editor.commitPreview, throwsStateError);
      expect(editor.objects.single.radius, .06);
    },
  );
  test('failed resize journal insert rolls back geometry and history', () {
    store.db.execute(
      "CREATE TRIGGER reject_change BEFORE INSERT ON changes BEGIN SELECT RAISE(ABORT,'fixture failure'); END",
    );
    editor.preview(const ResizeIntent('a', .08));
    expect(editor.commitPreview, throwsA(isA<SqliteException>()));
    expect(editor.objects.single.radius, .04);
    expect(editor.canUndo, false);
  });
}
