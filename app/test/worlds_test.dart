import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/main.dart';

void main() {
  test('worlds stay isolated and survive fresh database reopen', () {
    final d = Directory.systemTemp.createTempSync('forge-worlds-');
    final path = '${d.path}/test.sqlite';
    var s = ForgeStore(sqlite3.open(path));
    s.ensureWorld('technical-proof', 'Original');
    s.save('technical-proof', const SpaceObject('a', 'star', 'A', .3, .4, .05));
    s.createWorld('two', 'Second');
    s.save('two', const SpaceObject('b', 'planet', 'B', .6, .5, .1));
    expect(
      () => s.save('two', const SpaceObject('a', 'star', 'hijack', .1, .1, .1)),
      throwsStateError,
    );
    expect(() => s.createWorld('bad', ' '), throwsArgumentError);
    s.close();
    s = ForgeStore(sqlite3.open(path));
    expect(s.worlds().map((w) => w.id), ['technical-proof', 'two']);
    expect(s.objects('technical-proof').single.name, 'A');
    expect(s.objects('two').single.name, 'B');
    expect(s.db.select('PRAGMA integrity_check').first.values.first, 'ok');
    s.close();
    d.deleteSync(recursive: true);
  });
  testWidgets('create switch and return preserves original bodies', (t) async {
    final s = ForgeStore(sqlite3.openInMemory());
    s.ensureWorld('technical-proof', 'Original');
    s.save('technical-proof', const SpaceObject('a', 'star', 'A', .3, .4, .05));
    await t.pumpWidget(ForgeApp(store: s));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('choose-world')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('create-world')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('world-name')), 'Second');
    await t.tap(find.byKey(const Key('confirm-create-world')));
    await t.pumpAndSettle();
    expect(s.worlds(), hasLength(2));
    expect(find.textContaining('0 أجرام'), findsOneWidget);
    await t.tap(find.text('إضافة كوكب'));
    await t.pumpAndSettle();
    expect(s.objects(s.worlds().last.id), hasLength(1));
    expect(s.objects('technical-proof'), hasLength(1));
    await t.tap(find.byKey(const Key('choose-world')));
    await t.pumpAndSettle();
    await t.tap(find.text('Original').last);
    await t.pumpAndSettle();
    expect(find.textContaining('1 أجرام'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.text('إضافة قمر'));
    await t.pumpAndSettle();
    await t.tap(find.text('إضافة صخرة فضائية'));
    await t.pumpAndSettle();
    expect(s.objects('technical-proof').map((o) => o.kind), [
      'star',
      'moon',
      'rock',
    ]);
    await t.pumpWidget(const SizedBox.shrink());
    s.close();
  });
}
