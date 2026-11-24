import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/main.dart';

void main() {
  testWidgets('technical editor renders portrait and landscape', (
    tester,
  ) async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final loader = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
    await loader.load();
    final store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('technical-proof', 'Proof');
    store.save(
      'technical-proof',
      const SpaceObject('s', 'star', 'نجم', .3, .4, .055),
    );
    store.save(
      'technical-proof',
      const SpaceObject('p', 'planet', 'كوكب', .65, .55, .035),
    );
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(ForgeApp(store: store));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ForgeApp),
      matchesGoldenFile('goldens/portrait.png'),
    );
    tester.view.physicalSize = const Size(960, 540);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ForgeApp),
      matchesGoldenFile('goldens/landscape.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    store.close();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
