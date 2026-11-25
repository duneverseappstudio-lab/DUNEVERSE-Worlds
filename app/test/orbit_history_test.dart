import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imperator_forge/authored_orbit.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/orbit_history.dart';

void main() {
  late ForgeStore store;
  late OrbitHistory history;
  const path = AuthoredOrbit('p', 's', 24, false);
  setUp(() {
    store = ForgeStore(sqlite3.openInMemory());
    store.ensureWorld('w', 'World');
    store.ensureWorld('other', 'Other');
    for (final o in [
      const SpaceObject('s', 'star', 'S', .2, .3, .04),
      const SpaceObject('p', 'planet', 'P', .5, .4, .03),
      const SpaceObject('m', 'moon', 'M', .7, .6, .02),
    ]) {
      store.save('w', o);
    }
    store.save('other', const SpaceObject('x', 'star', 'X', .1, .1, .03));
    history = OrbitHistory(store, 'w');
  });
  tearDown(() => store.close());
  test('create edit remove undo redo persist in order', () {
    history.change('p', path, expected: null);
    const edited = AuthoredOrbit('p', 's', 60, true);
    history.change('p', edited, expected: path);
    history.change('p', null, expected: edited);
    expect(store.orbits('w'), isEmpty);
    history.undo();
    expect(sameOrbit(history.current('p'), edited), true);
    history.undo();
    expect(sameOrbit(history.current('p'), path), true);
    history.undo();
    expect(store.orbits('w'), isEmpty);
    expect(history.canUndo, false);
    history.redo();
    history.redo();
    history.redo();
    expect(store.orbits('w'), isEmpty);
    expect(history.canRedo, false);
  });
  test('no-op preserves redo but real new change invalidates it', () {
    history.change('p', path, expected: null);
    history.undo();
    history.change('p', null, expected: null);
    expect(history.canRedo, true);
    history.change(
      'm',
      const AuthoredOrbit('m', 's', 12, false),
      expected: null,
    );
    expect(history.canRedo, false);
  });
  test('undo rejects external path edit without consuming history', () {
    history.change('p', path, expected: null);
    const external = AuthoredOrbit('p', 's', 90, true);
    store.saveOrbit('w', external);
    expect(history.undo, throwsStateError);
    expect(sameOrbit(history.current('p'), external), true);
    expect(history.canUndo, true);
  });
  test('redo refuses external path creation', () {
    history.change('p', path, expected: null);
    history.undo();
    const external = AuthoredOrbit('p', 'm', 90, true);
    store.saveOrbit('w', external);
    expect(history.redo, throwsStateError);
    expect(sameOrbit(history.current('p'), external), true);
    expect(history.canRedo, true);
  });
  test('stale form no-op is rejected transactionally', () {
    store.saveOrbit('w', path);
    expect(() => history.change('p', null, expected: null), throwsStateError);
    expect(sameOrbit(history.current('p'), path), true);
    expect(history.canUndo, false);
  });
  test('cycle on replay rolls back and preserves history', () {
    history.change('p', path, expected: null);
    history.change('p', null, expected: path);
    store.saveOrbit('w', const AuthoredOrbit('s', 'p', 20, false));
    expect(history.undo, throwsArgumentError);
    expect(history.current('p'), isNull);
    expect(store.orbits('w').single.bodyId, 's');
    expect(history.canUndo, true);
  });
  test('cross-world and mismatched body cannot be changed', () {
    expect(() => history.change('x', null, expected: null), throwsArgumentError);
    expect(
      () => history.change(
        'p',
        const AuthoredOrbit('m', 's', 30, false),
        expected: null,
      ),
      throwsArgumentError,
    );
    expect(store.orbits('w'), isEmpty);
    expect(store.objects('other').single.id, 'x');
  });
  test('new screen visit starts empty bounded history', () {
    expect(OrbitHistory(store, 'w').canUndo, false);
    for (var i = 0; i < 105; i++) {
      history.change(
        'p',
        AuthoredOrbit('p', 's', i + 1.0, false),
        expected: history.current('p'),
      );
    }
    for (var i = 0; i < 100; i++) {
      history.undo();
    }
    expect(history.canUndo, false);
    expect(history.current('p')!.seconds, 5);
    expect(OrbitHistory(store, 'w').canRedo, false);
  });
}
