import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/main.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/star_detail.dart';

Future<List<int>> pixels(double phase) async {
  final recorder = ui.PictureRecorder();
  StarDetailPainter(
    phase: phase,
    zoom: 1.5,
  ).paint(ui.Canvas(recorder), const ui.Size(400, 400));
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 400);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List()
        .toList();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('prominence phase changes bounded pixels deterministically', () async {
    final a = await pixels(0), b = await pixels(.37), c = await pixels(0);
    expect(a, c);
    expect(a, isNot(b));
  });
  testWidgets(
    'closeup zoom and animation never change durable radius or journal',
    (tester) async {
      final store = ForgeStore(sqlite3.openInMemory());
      store.ensureWorld('technical-proof', 'test');
      store.save(
        'technical-proof',
        const SpaceObject('s', 'star', 'نجم', .5, .5, .055),
      );
      final before = store.db.select('SELECT * FROM objects').toString();
      final changes = store.db.select('SELECT * FROM changes').toString();
      await tester.pumpWidget(ForgeApp(store: store));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byKey(const Key('workspace'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('star-closeup')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StarCloseup), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('view-zoom')),
        const Offset(100, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('star-pause')));
      await tester.pumpAndSettle();
      final p =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('star-detail-canvas')),
                  )
                  .painter!
              as StarDetailPainter;
      await tester.pump(const Duration(seconds: 1));
      final q =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('star-detail-canvas')),
                  )
                  .painter!
              as StarDetailPainter;
      expect(q.phase, p.phase);
      expect(p.zoom, greaterThan(1));
      expect(store.db.select('SELECT * FROM objects').toString(), before);
      expect(store.db.select('SELECT * FROM changes').toString(), changes);
      await tester.tap(find.byKey(const Key('close-star-detail')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.close();
    },
  );
  testWidgets(
    'reduced motion freezes rendering and lifecycle resume respects it',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: StarCloseup(name: 'test'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final p =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('star-detail-canvas')),
                  )
                  .painter!
              as StarDetailPainter;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      final q =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('star-detail-canvas')),
                  )
                  .painter!
              as StarDetailPainter;
      expect(q.phase, p.phase);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
