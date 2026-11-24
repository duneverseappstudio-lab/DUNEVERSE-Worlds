import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/main.dart';

void main() {
  testWidgets('projection preview never creates hidden objects', (
    tester,
  ) async {
    final store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('technical-proof', 'Proof');
    await tester.pumpWidget(ForgeApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('اختبار إسقاط الكرة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة كوكب'));
    await tester.pumpAndSettle();
    expect(store.objects('technical-proof'), isEmpty);
    await tester.tap(find.byIcon(Icons.grid_on));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة كوكب'));
    await tester.pumpAndSettle();
    expect(store.objects('technical-proof'), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    store.close();
  });
  testWidgets('drag palette creates at drop and move persists', (tester) async {
    final store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('technical-proof', 'Proof');
    await tester.pumpWidget(ForgeApp(store: store));
    await tester.pumpAndSettle();
    final workspace = find.byKey(const Key('workspace'));
    final area = tester.getRect(workspace);
    final drop = area.topLeft + Offset(area.width * .7, area.height * .4);
    await tester.dragFrom(
      tester.getCenter(find.text('إضافة كوكب')),
      drop - tester.getCenter(find.text('إضافة كوكب')),
    );
    await tester.pumpAndSettle();
    expect(store.objects('technical-proof'), hasLength(1));
    var o = store.objects('technical-proof').single;
    expect(o.x, closeTo(.7, .08));
    expect(o.y, closeTo(.4, .08));
    final center = area.topLeft + Offset(o.x * area.width, o.y * area.height);
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    await tester.dragFrom(center, const Offset(-80, 40));
    await tester.pumpAndSettle();
    final moved = store.objects('technical-proof').single;
    expect(moved.x, lessThan(o.x));
    expect(moved.y, greaterThan(o.y));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.close();
  });
  testWidgets('add button creates and persists arbitrary second body', (
    tester,
  ) async {
    final store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('technical-proof', 'Proof');
    await tester.pumpWidget(ForgeApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة كوكب'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة كوكب'));
    await tester.pumpAndSettle();
    expect(store.objects('technical-proof'), hasLength(2));
    expect(
      store.objects('technical-proof').map((x) => x.id).toSet(),
      hasLength(2),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.close();
  });
  testWidgets('cancelled editor drag never commits preview coordinates', (
    tester,
  ) async {
    final store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('technical-proof', 'Proof');
    store.save(
      'technical-proof',
      const SpaceObject('p', 'planet', 'كوكب', .5, .5, .035),
    );
    await tester.pumpWidget(ForgeApp(store: store));
    await tester.pumpAndSettle();
    final area = tester.getRect(find.byKey(const Key('workspace')));
    await tester.tapAt(area.center);
    final gesture = await tester.startGesture(area.center);
    await gesture.moveBy(const Offset(30, 10));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 30));
    await tester.pump();
    expect(store.objects('technical-proof').single.x, .5);
    expect(find.textContaining('معاينة الحركة، لم تُحفظ بعد'), findsOneWidget);
    await gesture.cancel();
    await tester.pumpAndSettle();
    final painter = tester
        .widget<CustomPaint>(
          find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is ScenePainter,
          ),
        )
        .painter;
    expect(painter, isA<ScenePainter>());
    expect((painter as ScenePainter).objects.single.x, .5);
    expect(store.objects('technical-proof').single.x, .5);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.close();
  });
  testWidgets('failed editor move visibly returns to saved coordinates', (
    tester,
  ) async {
    final store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('technical-proof', 'Proof');
    store.save(
      'technical-proof',
      const SpaceObject('p', 'planet', 'كوكب', .5, .5, .035),
    );
    store.db.execute(
      "CREATE TRIGGER reject_move BEFORE UPDATE ON objects BEGIN SELECT RAISE(ABORT,'fixture failure'); END",
    );
    await tester.pumpWidget(ForgeApp(store: store));
    await tester.pumpAndSettle();
    final area = tester.getRect(find.byKey(const Key('workspace')));
    await tester.tapAt(area.center);
    await tester.dragFrom(area.center, const Offset(90, 40));
    await tester.pumpAndSettle();
    expect(find.textContaining('فشل الحفظ، لم يُعتمد التغيير'), findsOneWidget);
    expect(store.objects('technical-proof').single.x, .5);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.close();
  });
  testWidgets('backgrounding cancels unsaved drag without a database write', (
    tester,
  ) async {
    final store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('technical-proof', 'Proof');
    store.save(
      'technical-proof',
      const SpaceObject('p', 'planet', 'كوكب', .5, .5, .035),
    );
    await tester.pumpWidget(ForgeApp(store: store));
    await tester.pumpAndSettle();
    final area = tester.getRect(find.byKey(const Key('workspace')));
    await tester.tapAt(area.center);
    final gesture = await tester.startGesture(area.center);
    await gesture.moveBy(const Offset(30, 10));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 30));
    await tester.pump();
    expect(find.textContaining('معاينة الحركة، لم تُحفظ بعد'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(
      find.textContaining('أُلغيت الحركة، المحفوظ لم يتغير'),
      findsOneWidget,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await gesture.moveBy(const Offset(50, 20));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.objects('technical-proof').single.x, .5);
    expect(store.db.select('SELECT count(*) AS n FROM changes').first['n'], 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.close();
  });
  testWidgets('editor undo and redo buttons durably reverse completed move', (
    tester,
  ) async {
    final store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('technical-proof', 'Proof');
    store.save(
      'technical-proof',
      const SpaceObject('p', 'planet', 'كوكب', .5, .5, .035),
    );
    await tester.pumpWidget(ForgeApp(store: store));
    await tester.pumpAndSettle();
    final area = tester.getRect(find.byKey(const Key('workspace')));
    await tester.tapAt(area.center);
    await tester.dragFrom(area.center, const Offset(90, 40));
    await tester.pumpAndSettle();
    final moved = store.objects('technical-proof').single.x;
    expect(moved, greaterThan(.5));
    await tester.tap(
      find.byTooltip('تراجع عن التحريك أو الحجم، للجلسة الحالية'),
    );
    await tester.pumpAndSettle();
    expect(store.objects('technical-proof').single.x, .5);
    await tester.tap(find.byTooltip('إعادة التحريك أو الحجم، للجلسة الحالية'));
    await tester.pumpAndSettle();
    expect(store.objects('technical-proof').single.x, moved);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.close();
  });
  testWidgets('size controls persist selected geometry and undo it', (
    tester,
  ) async {
    final store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('technical-proof', 'Proof');
    store.save(
      'technical-proof',
      const SpaceObject('p', 'planet', 'كوكب', .5, .5, .035),
    );
    await tester.pumpWidget(ForgeApp(store: store));
    await tester.pumpAndSettle();
    final area = tester.getRect(find.byKey(const Key('workspace')));
    await tester.tapAt(area.center);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('تكبير العنصر المحدد'));
    await tester.pumpAndSettle();
    expect(
      store.objects('technical-proof').single.radius,
      closeTo(.042, .00001),
    );
    await tester.tap(
      find.byTooltip('تراجع عن التحريك أو الحجم، للجلسة الحالية'),
    );
    await tester.pumpAndSettle();
    expect(store.objects('technical-proof').single.radius, .035);
    await tester.tap(find.byTooltip('تصغير العنصر المحدد'));
    await tester.pumpAndSettle();
    expect(store.objects('technical-proof').single.radius, lessThan(.035));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.close();
  });
  testWidgets('failed creation never leaves a selected missing object', (
    tester,
  ) async {
    final store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('technical-proof', 'Proof');
    store.db.execute(
      "CREATE TRIGGER reject_create BEFORE INSERT ON objects BEGIN SELECT RAISE(ABORT,'fixture failure'); END",
    );
    await tester.pumpWidget(ForgeApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة كوكب'));
    await tester.pumpAndSettle();
    expect(store.objects('technical-proof'), isEmpty);
    final sizeButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.add_circle_outline),
    );
    expect(sizeButton.onPressed, isNull);
    expect(find.textContaining('فشل الحفظ، لم يُعتمد التغيير'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.close();
  });
}
