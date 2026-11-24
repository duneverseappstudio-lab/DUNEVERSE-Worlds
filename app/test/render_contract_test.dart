import 'package:flutter_test/flutter_test.dart';
import 'package:imperator_forge/render_contract.dart';

void main() {
  test('renderer intent boundary accepts only typed scene-local edits', () {
    final scene = RenderScene([const SceneNode('p', null, 0, 0, 0, 1)]);
    final move = parseRenderIntent({
      'type': 'move',
      'entityId': 'p',
      'x': 1,
      'y': 2.5,
      'z': 0,
    }, scene) as MoveIntent;
    expect(move.x, 1);
    expect(move.y, 2.5);
    expect(
      parseRenderIntent({'type': 'select', 'entityId': 'p'}, scene),
      isA<SelectIntent>(),
    );
    expect(scene.nodes.single.x, 0);
    for (final invalid in <Map<String, Object?>>[
      {'type': 'sql', 'entityId': 'p'},
      {'type': 'move', 'entityId': 'foreign', 'x': 1, 'y': 2, 'z': 3},
      {'type': 'move', 'entityId': 'p', 'x': double.nan, 'y': 2, 'z': 3},
      {'type': 'move', 'entityId': 'p', 'x': '1', 'y': 2, 'z': 3},
      {'type': 'move', 'entityId': 'p', 'x': 1, 'y': 2},
      {'type': 'select', 'entityId': 'p', 'command': 'unsupported'},
    ]) {
      expect(() => parseRenderIntent(invalid, scene), throwsArgumentError);
    }
  });
  test('scene preserves stable IDs and parent-independent transforms', () {
    final scene = RenderScene([
      const SceneNode('star', null, 0, 0, 0, 1),
      const SceneNode('planet', 'star', 3, 0, 1, .3),
    ]);
    expect(scene.nodes.last.id, 'planet');
    expect(scene.nodes.last.parentId, 'star');
    expect(() => scene.nodes.clear(), throwsUnsupportedError);
  });
  test(
    'renderer contract rejects dangling parent cycles and invalid coordinates',
    () {
      expect(
        () => RenderScene([const SceneNode('p', 'missing', 0, 0, 0, 1)]),
        throwsArgumentError,
      );
      expect(
        () => RenderScene([
          const SceneNode('a', 'b', 0, 0, 0, 1),
          const SceneNode('b', 'a', 0, 0, 0, 1),
        ]),
        throwsArgumentError,
      );
      expect(
        () => RenderScene([SceneNode('a', null, double.infinity, 0, 0, 1)]),
        throwsArgumentError,
      );
      expect(
        () => RenderScene([
          const SceneNode('a', null, 0, 0, 0, 1),
          const SceneNode('a', null, 1, 0, 0, 1),
        ]),
        throwsArgumentError,
      );
    },
  );
}
