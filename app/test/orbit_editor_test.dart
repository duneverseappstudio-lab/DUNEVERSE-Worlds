import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/main.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/motion_lab.dart';
import 'package:imperator_forge/orbit_editor.dart';
import 'package:imperator_forge/authored_orbit.dart';

void main() {
  testWidgets(
    'saved orbit UI persists reopens edits independent speeds and plays beyond24seconds without resetting',
    (t) async {
      final font = FontLoader('Cairo')
        ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = ForgeStore(sqlite3.openInMemory());
      s.ensureWorld('technical-proof', 'World');
      for (final o in [
        const SpaceObject('s', 'star', 'Sun', .4, .5, .05),
        const SpaceObject('p', 'planet', 'Planet', .6, .5, .025),
        const SpaceObject('m', 'moon', 'Moon', .67, .5, .015),
      ]) {
        s.save('technical-proof', o);
      }
      await t.pumpWidget(ForgeApp(store: s));
      await t.pumpAndSettle();
      Future<void> choose(String key, String text) async {
        await t.tap(find.byKey(Key(key)));
        await t.pumpAndSettle();
        await t.tap(find.text(text).last);
        await t.pumpAndSettle();
      }

      await t.tap(find.byKey(const Key('open-orbit-draft')));
      await t.pumpAndSettle();
      await choose('orbit-body', 'Planet');
      await choose('orbit-center-p-null', 'Sun');
      await t.tap(find.text('60 ث'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('save-orbit')));
      await t.tap(find.byKey(const Key('save-orbit')));
      await t.pumpAndSettle();
      expect(s.orbits('technical-proof').single.seconds, 60);
      await t.ensureVisible(find.byKey(const Key('orbit-body')));
      await choose('orbit-body', 'Moon');
      await choose('orbit-center-m-null', 'Planet');
      await t.tap(find.text('12 ث'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('save-orbit')));
      await t.tap(find.byKey(const Key('save-orbit')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('close-saved-orbits')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('open-orbit-draft')));
      await t.pumpAndSettle();
      await choose('orbit-body', 'Planet');
      expect(find.textContaining('مدة الدورة: 60'), findsOneWidget);
      await expectLater(
        find.byType(ForgeApp),
        matchesGoldenFile('goldens/2-1-saved-orbits-390.png'),
      );
      for (final size in [const Size(320, 700), const Size(844, 390)]) {
        t.view.physicalSize = size;
        await t.pumpAndSettle();
        await expectLater(
          find.byType(ForgeApp),
          matchesGoldenFile(size.width == 320 ? 'goldens/1-saved-orbits-320.png' : 'goldens/3-1-saved-orbits-844.png'),
        );
      }
      t.view.physicalSize = const Size(390, 844);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('play-saved-orbits')));
      await t.tap(find.byKey(const Key('play-saved-orbits')));
      await t.pumpAndSettle();
      MotionLabPainter painter() =>
          t
                  .widget<CustomPaint>(
                    find.byKey(const Key('motion-lab-canvas')),
                  )
                  .painter!
              as MotionLabPainter;
      await expectLater(
        find.byType(ForgeApp),
        matchesGoldenFile('goldens/saved-orbits-preview-390.png'),
      );
      final before = s
          .objects('technical-proof')
          .map((o) => o.toJson())
          .toString();
      await t.tap(find.byKey(const Key('motion-play')));
      await t.pump();
      await t.pump(const Duration(seconds: 25));
      expect(painter().time, greaterThanOrEqualTo(25));
      final at25 = painter().model.at(painter().time)['p']!;
      expect(at25.x, lessThan(-.2));
      await t.tap(find.byKey(const Key('motion-play')));
      await t.pumpAndSettle();
      final paused = painter().time;
      await t.pump(const Duration(seconds: 5));
      expect(painter().time, paused);
      await t.tap(find.byKey(const Key('motion-play')));
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      expect(painter().time, closeTo(paused + 2, .01));
      await t.tap(find.byKey(const Key('motion-reset')));
      await t.pumpAndSettle();
      expect(painter().time, 0);
      expect(
        s.objects('technical-proof').map((o) => o.toJson()).toString(),
        before,
      );
      expect(s.orbits('technical-proof').map((o) => o.seconds), [60, 12]);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      s.close();
    },
  );
  testWidgets(
    'orbit toolbar reverses edit and removal and disables on reopen',
    (t) async {
      final s = ForgeStore(sqlite3.openInMemory());
      s.ensureWorld('w', 'W');
      s.save('w', const SpaceObject('s', 'star', 'Sun', .2, .3, .04));
      s.save('w', const SpaceObject('p', 'planet', 'Planet', .5, .4, .03));
      s.saveOrbit('w', const AuthoredOrbit('p', 's', 24, false));
      await t.pumpWidget(
        MaterialApp(
          home: OrbitEditor(store: s, worldId: 'w'),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t.widget<IconButton>(find.byKey(const Key('orbit-undo'))).onPressed,
        isNull,
      );
      await t.tap(find.byKey(const Key('orbit-body')));
      await t.pumpAndSettle();
      await t.tap(find.text('Planet').last);
      await t.pumpAndSettle();
      await t.tap(find.text('60 ث'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('save-orbit')));
      await t.tap(find.byKey(const Key('save-orbit')));
      await t.pumpAndSettle();
      expect(s.orbits('w').single.seconds, 60);
      await t.tap(find.byKey(const Key('orbit-undo')));
      await t.pumpAndSettle();
      expect(s.orbits('w').single.seconds, 24);
      await t.tap(find.byKey(const Key('orbit-redo')));
      await t.pumpAndSettle();
      expect(s.orbits('w').single.seconds, 60);
      await t.ensureVisible(find.byKey(const Key('remove-orbit-p')));
      await t.tap(find.byKey(const Key('remove-orbit-p')));
      await t.pumpAndSettle();
      expect(s.orbits('w'), isEmpty);
      await t.tap(find.byKey(const Key('orbit-undo')));
      await t.pumpAndSettle();
      expect(s.orbits('w').single.seconds, 60);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(
        MaterialApp(
          home: OrbitEditor(store: s, worldId: 'w'),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t.widget<IconButton>(find.byKey(const Key('orbit-undo'))).onPressed,
        isNull,
      );
      expect(s.orbits('w').single.seconds, 60);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      s.close();
    },
  );
}
