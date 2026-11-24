import 'dart:io';

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
    await t.runAsync(() => app.main());
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
    await t.runAsync(() => app.main());
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
      await t.runAsync(() => app.main());
      await t.pumpAndSettle();
      expect(find.textContaining('تعذر فتح التخزين المحلي'), findsOneWidget);
      expect(blocked.readAsStringSync(), 'synthetic sentinel');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
