import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/main.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/motion_lab.dart';
import 'package:imperator_forge/orbit_draft.dart';

void main() {
  testWidgets(
    'explicit existing-body draft plays and discards without SQL writes',
    (tester) async {
      final font = FontLoader('Cairo')
        ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final store = ForgeStore(sqlite3.openInMemory());
      store.ensureWorld('technical-proof', 'test');
      for (final o in [
        const SpaceObject('s', 'star', 'مركز', .5, .5, .05),
        const SpaceObject('p', 'planet', 'كوكب', .8, .5, .03),
      ]) {
        store.save('technical-proof', o);
      }
      final before = store.db.select('SELECT * FROM objects').toString(),
          changes = store.db.select('SELECT * FROM changes').toString();
      await tester.pumpWidget(ForgeApp(store: store));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(ProofEditor));
      Navigator.push(
        ctx,
        MaterialPageRoute<void>(
          builder: (_) => OrbitDraft(objects: store.objects('technical-proof')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('draft-preview')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('draft-center')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مركز (s)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('draft-body-p')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(ForgeApp),
        matchesGoldenFile('goldens/orbit-draft-selection.png'),
      );
      await tester.tap(find.byKey(const Key('draft-preview')));
      await tester.pumpAndSettle();
      MotionLabPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('motion-lab-canvas')),
                  )
                  .painter!
              as MotionLabPainter;
      await expectLater(
        find.byType(ForgeApp),
        matchesGoldenFile('goldens/orbit-draft-preview.png'),
      );
      expect(painter().model.at(0)['p']!.x, closeTo(.3, 1e-9));
      expect(painter().objects!.last.name, 'كوكب');
      await tester.tap(find.byKey(const Key('motion-play')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(painter().model.at(painter().time)['p']!.y, greaterThan(0));
      await tester.tap(find.byKey(const Key('motion-reset')));
      await tester.pumpAndSettle();
      expect(painter().time, 0);
      await tester.tap(find.byKey(const Key('close-motion-lab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('close-orbit-draft')));
      await tester.pumpAndSettle();
      expect(store.db.select('SELECT * FROM objects').toString(), before);
      expect(store.db.select('SELECT * FROM changes').toString(), changes);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.close();
    },
  );
}
