import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/main.dart';

void main() {
  late ForgeStore store;
  setUp(() {
    store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('technical-proof', 'تجربة');
    store.save(
      'technical-proof',
      const SpaceObject('a', 'planet', 'أرض', .5, .5, .04),
    );
  });
  tearDown(() => store.close());
  int count() =>
      store.db.select('SELECT count(*) AS n FROM changes').single['n'] as int;
  Future<void> select(WidgetTester tester) async {
    await tester.pumpWidget(ForgeApp(store: store));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byKey(const Key('workspace'))));
    await tester.pumpAndSettle();
  }

  Future<void> nudge(WidgetTester tester, String direction) async {
    await tester.tap(find.byTooltip('تحريك العنصر دون سحب'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(direction));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'menu movement persists once and undo/redo preserve exact position',
    (tester) async {
      await select(tester);
      await nudge(tester, 'تحريك لليمين');
      expect(store.objects('technical-proof').single.x, .52);
      expect(count(), 2);
      await tester.tap(find.byIcon(Icons.undo));
      await tester.pumpAndSettle();
      expect(store.objects('technical-proof').single.x, .5);
      await tester.tap(find.byIcon(Icons.redo));
      await tester.pumpAndSettle();
      expect(store.objects('technical-proof').single.x, .52);
      await nudge(tester, 'تحريك لأعلى');
      expect(store.objects('technical-proof').single.y, .48);
      await nudge(tester, 'تحريك لليسار');
      expect(store.objects('technical-proof').single.x, .5);
      await nudge(tester, 'تحريك لأسفل');
      expect(store.objects('technical-proof').single.y, .5);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('boundary no-op writes no journal entry', (tester) async {
    store.save(
      'technical-proof',
      const SpaceObject('a', 'planet', 'أرض', 1, .5, .04),
    );
    await tester.pumpWidget(ForgeApp(store: store));
    await tester.pumpAndSettle();
    final area = tester.getRect(find.byKey(const Key('workspace')));
    await tester.tapAt(Offset(area.right - 1, area.center.dy));
    await tester.pumpAndSettle();
    final before = count();
    await nudge(tester, 'تحريك لليمين');
    expect(count(), before);
    expect(store.objects('technical-proof').single.x, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'failed nudge journal preserves durable position and disables undo',
    (tester) async {
      await select(tester);
      store.db.execute(
        "CREATE TRIGGER reject_change BEFORE INSERT ON changes BEGIN SELECT RAISE(ABORT,'fixture failure'); END",
      );
      await nudge(tester, 'تحريك لليسار');
      expect(store.objects('technical-proof').single.x, .5);
      expect(count(), 1);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('فشل التحريك'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('movement menu disabled with no selection or projection', (
    tester,
  ) async {
    await tester.pumpWidget(ForgeApp(store: store));
    await tester.pumpAndSettle();
    PopupMenuButton<Offset> menu() => tester.widget<PopupMenuButton<Offset>>(
      find.byType(PopupMenuButton<Offset>),
    );
    expect(menu().enabled, isFalse);
    await tester.tapAt(tester.getCenter(find.byKey(const Key('workspace'))));
    await tester.pumpAndSettle();
    expect(menu().enabled, isTrue);
    await tester.tap(find.byTooltip('اختبار إسقاط الكرة'));
    await tester.pumpAndSettle();
    expect(menu().enabled, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
