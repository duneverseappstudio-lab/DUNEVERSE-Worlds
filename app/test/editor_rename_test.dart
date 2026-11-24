import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/editor_session.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/render_contract.dart';
import 'package:imperator_forge/main.dart';

void main() {
  late ForgeStore store;
  late EditorSession editor;
  setUp(() {
    store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('technical-proof', 'تجربة');
    store.save(
      'technical-proof',
      const SpaceObject('a', 'planet', 'أرض', .2, .3, .04),
    );
    editor = EditorSession(store, 'technical-proof');
  });
  tearDown(() => store.close());
  int count() =>
      store.db.select('SELECT count(*) AS n FROM changes').single['n'] as int;
  test('rename validates and trims Unicode, no-op creates no journal row', () {
    for (final bad in [
      '',
      '  ',
      'a\nb',
      'a\tb',
      'a\u2028b',
      'a\u2029b',
      String.fromCharCode(127),
      List.filled(81, 'س').join(),
    ]) {
      expect(
        () => editor.rename('a', bad, expectedName: 'أرض'),
        throwsArgumentError,
      );
    }
    expect(count(), 1);
    editor.rename('a', '  أرض  ', expectedName: 'أرض');
    expect(count(), 1);
    editor.rename('a', 'عالم 🌍', expectedName: 'أرض');
    expect(editor.objects.single.name, 'عالم 🌍');
    expect(count(), 2);
  });
  test(
    'rename preserves concurrent geometry and geometry undo preserves rename',
    () {
      editor.preview(const MoveIntent('a', .6, .7, 0));
      editor.commitPreview();
      store.save(
        'technical-proof',
        store.objects('technical-proof').single.move(.8, .9),
      );
      editor.rename('a', 'جديد', expectedName: 'أرض');
      expect(editor.objects.single.x, .8);
      expect(editor.objects.single.name, 'جديد');
      expect(editor.undo, throwsStateError);
      expect(editor.objects.single.name, 'جديد');
    },
  );
  test('successful movement undo and redo retain later name', () {
    editor.preview(const MoveIntent('a', .6, .7, 0));
    editor.commitPreview();
    editor.rename('a', 'جديد', expectedName: 'أرض');
    editor.undo();
    expect(editor.objects.single.x, .2);
    expect(editor.objects.single.name, 'جديد');
    editor.redo();
    expect(editor.objects.single.x, .6);
    expect(editor.objects.single.name, 'جديد');
  });
  test('stale name, deleted target and wrong world never overwrite', () {
    store.save(
      'technical-proof',
      const SpaceObject('a', 'planet', 'آخر', .2, .3, .04),
    );
    expect(
      () => editor.rename('a', 'محلي', expectedName: 'أرض'),
      throwsStateError,
    );
    expect(count(), 2);
    store.ensureWorld('other', 'آخر');
    expect(
      () => store.save(
        'other',
        const SpaceObject('a', 'planet', 'محلي', .2, .3, .04),
        expectedName: 'آخر',
      ),
      throwsStateError,
    );
    store.db.execute("DELETE FROM objects WHERE id='a'");
    expect(
      () => editor.rename('a', 'محلي', expectedName: 'آخر'),
      throwsStateError,
    );
    expect(editor.objects, isEmpty);
    expect(count(), 2);
  });
  test(
    'journal failure rolls back rename and pending preview rejects rename',
    () {
      editor.preview(const MoveIntent('a', .6, .7, 0));
      expect(
        () => editor.rename('a', 'جديد', expectedName: 'أرض'),
        throwsStateError,
      );
      expect(editor.hasPreview, isTrue);
      editor.cancelPreview();
      store.db.execute(
        "CREATE TRIGGER reject_change BEFORE INSERT ON changes BEGIN SELECT RAISE(ABORT,'fixture failure'); END",
      );
      expect(
        () => editor.rename('a', 'جديد', expectedName: 'أرض'),
        throwsA(isA<SqliteException>()),
      );
      expect(editor.objects.single.name, 'أرض');
      expect(count(), 1);
    },
  );
  testWidgets(
    'rename dialog validates, cancel writes nothing, save changes visible name',
    (tester) async {
      await tester.pumpWidget(ForgeApp(store: store));
      await tester.pumpAndSettle();
      final area = tester.getRect(find.byKey(const Key('workspace')));
      await tester.tapAt(
        area.topLeft + Offset(area.width * .2, area.height * .3),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('تعديل اسم العنصر'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('object-name')), '');
      await tester.tap(find.text('حفظ الاسم'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(count(), 1);
      await tester.enterText(find.byKey(const Key('object-name')), 'اسم ملغي');
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(count(), 1);
      await tester.tap(find.byTooltip('تعديل اسم العنصر'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('object-name')), 'عالم جديد');
      await tester.tap(find.text('حفظ الاسم'));
      await tester.pumpAndSettle();
      expect(store.objects('technical-proof').single.name, 'عالم جديد');
      expect(count(), 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
