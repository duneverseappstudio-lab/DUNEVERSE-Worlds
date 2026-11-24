import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/main.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/motion_lab.dart';

void main() {
  testWidgets(
    'explicit motion example plays pauses resets exits without store writes',
    (tester) async {
      final store = ForgeStore(sqlite3.openInMemory());
      store.ensureWorld('technical-proof', 'test');
      store.save(
        'technical-proof',
        const SpaceObject('a', 'planet', 'unchanged', .2, .3, .04),
      );
      final before = store.db.select('SELECT * FROM objects').toString();
      final journal = store.db.select('SELECT * FROM changes').toString();
      await tester.pumpWidget(ForgeApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-motion-lab')));
      await tester.pumpAndSettle();
      MotionLabPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('motion-lab-canvas')),
                  )
                  .painter!
              as MotionLabPainter;
      expect(painter().time, 0);
      await tester.tap(find.byKey(const Key('motion-play')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(painter().time, greaterThan(0));
      await tester.tap(find.byKey(const Key('motion-play')));
      await tester.pumpAndSettle();
      final paused = painter().time;
      await tester.pump(const Duration(seconds: 2));
      expect(painter().time, paused);
      await tester.tap(find.byKey(const Key('motion-reset')));
      await tester.pumpAndSettle();
      expect(painter().time, 0);
      await tester.tap(find.byKey(const Key('close-motion-lab')));
      await tester.pumpAndSettle();
      expect(store.db.select('SELECT * FROM objects').toString(), before);
      expect(store.db.select('SELECT * FROM changes').toString(), journal);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.close();
    },
  );
  testWidgets('motion example obeys reduced-motion and lifecycle', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MotionLab(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<TextButton>(
      find.byKey(const Key('motion-play')),
    );
    expect(button.onPressed, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    expect(
      (tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('motion-lab-canvas')),
                  )
                  .painter!
              as MotionLabPainter)
          .time,
      0,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
