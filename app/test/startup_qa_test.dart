import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';

import 'package:imperator_forge/forge_store.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/main.dart' as app;

class StartupPaths extends PathProviderPlatform {
  final String root;
  StartupPaths(this.root);
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late Directory scratch;
  late PathProviderPlatform original;
  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dune-startup-qa-');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = StartupPaths(scratch.path);
  });
  tearDown(() {
    PathProviderPlatform.instance = original;
    scratch.deleteSync(recursive: true);
  });
  testWidgets('actual main opens fresh synthetic storage and editor', (
    t,
  ) async {
    await app.main();
    await t.pump();
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    expect(find.byType(app.ForgeApp), findsOneWidget);
    expect(find.textContaining('تعذر فتح التخزين المحلي'), findsNothing);
    final db = sqlite3.open('${scratch.path}/phase0.sqlite');
    expect(db.select('PRAGMA user_version').single.values.single, 2);
    expect(
      db.select('SELECT name FROM worlds').single['name'],
      'اختبار المحرر',
    );
    expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
    db.close();
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('actual main shows storage error for newer synthetic schema', (
    t,
  ) async {
    final db = sqlite3.open('${scratch.path}/phase0.sqlite');
    db.execute('PRAGMA user_version=99');
    db.close();
    await app.main();
    await t.pump();
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    expect(find.textContaining('تعذر فتح التخزين المحلي'), findsOneWidget);
    expect(find.byType(app.ForgeApp), findsNothing);
    expect(t.takeException(), isNull);
    final check = sqlite3.open('${scratch.path}/phase0.sqlite');
    expect(check.select('PRAGMA user_version').single.values.single, 99);
    check.close();
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'actual main handles unavailable support path without uncaught error',
    (t) async {
      final blocked = File('${scratch.path}/not-a-directory')
        ..writeAsStringSync('synthetic sentinel');
      PathProviderPlatform.instance = StartupPaths('${blocked.path}/child');
      await app.main();
      await t.pump();
      for (
        var i = 0;
        i < 50 && find.byKey(const Key('startup-retry')).evaluate().isEmpty;
        i++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(find.textContaining('تعذر فتح التخزين المحلي'), findsOneWidget);
      expect(blocked.readAsStringSync(), 'synthetic sentinel');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('loading status paints while initialization is pending', (
    t,
  ) async {
    final pending = Completer<ForgeStore>();
    await t.pumpWidget(
      RepaintBoundary(child: app.StartupGate(initialize: () => pending.future)),
    );
    await t.pumpAndSettle();
    expect(find.text('جارٍ فتح عالمك...'), findsOneWidget);
    expect(find.byKey(const Key('startup-retry')), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed initialization offers retry and reaches editor once', (
    t,
  ) async {
    var calls = 0;
    await t.pumpWidget(
      RepaintBoundary(
        child: app.StartupGate(
          initialize: () async {
            calls++;
            if (calls == 1) throw StateError('synthetic failure');
            final store = ForgeStore(sqlite3.openInMemory());
            store.ensureWorld('technical-proof', 'اختبار المحرر');
            return store;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('تعذر فتح التخزين المحلي'), findsOneWidget);
    await t.tap(find.byKey(const Key('startup-retry')));
    await t.pumpAndSettle();
    expect(find.byType(app.ForgeApp), findsOneWidget);
    expect(calls, 2);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('retry is single-flight under rapid taps', (t) async {
    final pending = Completer<ForgeStore>();
    var calls = 0;
    await t.pumpWidget(
      app.StartupGate(
        initialize: () {
          calls++;
          if (calls == 1) return Future.error(StateError('synthetic'));
          return pending.future;
        },
      ),
    );
    await t.pumpAndSettle();
    final retry = find.byKey(const Key('startup-retry'));
    await t.tap(retry);
    await t.tap(retry);
    await t.pump();
    expect(calls, 2);
    await t.pumpWidget(const SizedBox.shrink());
    pending.complete(ForgeStore(sqlite3.openInMemory()));
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('late initializer is closed after gate disposal', (t) async {
    final pending = Completer<ForgeStore>();
    await t.pumpWidget(app.StartupGate(initialize: () => pending.future));
    await t.pumpWidget(const SizedBox.shrink());
    final store = ForgeStore(sqlite3.openInMemory());
    pending.complete(store);
    await t.pump();
    expect(() => store.db.select('SELECT 1'), throwsStateError);
    expect(t.takeException(), isNull);
  });

  testWidgets('stalled path provider times out without opening a database', (
    t,
  ) async {
    PathProviderPlatform.instance = PendingStartupPaths();
    final result = app.openStartupStore(
      stepTimeout: const Duration(milliseconds: 50),
    );
    final expectation = expectLater(result, throwsA(isA<TimeoutException>()));
    await t.pump(const Duration(milliseconds: 60));
    await expectation;
    expect(scratch.listSync(), isEmpty);
  });
}

class PendingStartupPaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() => Completer<String?>().future;
}
