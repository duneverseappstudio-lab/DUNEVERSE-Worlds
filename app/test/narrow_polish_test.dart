import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/main.dart';

void main() {
  test('label placement avoids bodies and previous labels', () {
    const viewport = Size(320, 500), center = Offset(160, 250);
    final body = Rect.fromCircle(center: center, radius: 30);
    final first = placeSceneLabel(center, body, const Size(70, 22), viewport, [
      body,
    ])!;
    final second = placeSceneLabel(center, body, const Size(70, 22), viewport, [
      body,
      first.inflate(3),
    ])!;
    expect(first.overlaps(body), false);
    expect(second.overlaps(body), false);
    expect(first.overlaps(second), false);
    expect(
      placeSceneLabel(center, body, const Size(400, 22), viewport, [body]),
      null,
    );
  });
  testWidgets('narrow phone full title actions and dense labels', (
    tester,
  ) async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    final store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('technical-proof', 'Proof');
    for (final o in [
      const SpaceObject('a', 'star', 'نجم أ', .39, .42, .055),
      const SpaceObject('b', 'star', 'نجم ب', .58, .38, .045),
      const SpaceObject('c', 'star', 'نجم ج', .50, .53, .095),
      const SpaceObject('d', 'star', 'نجم د', .58, .63, .03),
      const SpaceObject('p', 'planet', 'كوكب', .21, .69, .16),
      const SpaceObject('m', 'moon', 'قمر', .72, .73, .04),
      const SpaceObject('r', 'rock', 'صخرة', .82, .58, .025),
    ]) {
      store.save('technical-proof', o);
    }
    for (final width in [320.0, 390.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(ForgeApp(store: store));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('choose-world')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(ForgeApp),
        matchesGoldenFile('goldens/narrow-polish-${width.toInt()}.png'),
      );
    }
    await tester.tap(find.byKey(const Key('open-motion-lab')));
    await tester.pumpAndSettle();
    expect(find.text('مختبر حركة مؤقت'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.close();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
