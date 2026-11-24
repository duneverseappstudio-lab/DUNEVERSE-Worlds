import 'package:flutter_test/flutter_test.dart';
import 'package:imperator_forge/render_contract.dart';

void main() {
  late RenderScene scene;
  setUp(() {
    scene = RenderScene([
      const SceneNode('parent', null, 10, 20, 30, 2),
      const SceneNode('child', 'parent', 11, 21, 31, .5),
    ]);
  });
  test('preview move changes only target and never changes original', () {
    final next = previewRenderIntent(scene, const MoveIntent('child', 3, 4, 5));
    expect(next.nodes.last.x, 3);
    expect(next.nodes.last.y, 4);
    expect(next.nodes.last.z, 5);
    expect(next.nodes.last.radius, .5);
    expect(next.nodes.last.parentId, 'parent');
    expect(identical(next.nodes.first, scene.nodes.first), isTrue);
    expect(scene.nodes.last.x, 11);
    expect(scene.nodes.last.y, 21);
    expect(scene.nodes.last.z, 31);
  });
  test('parent move does not infer a child-local coordinate system', () {
    final next = previewRenderIntent(
      scene,
      const MoveIntent('parent', 0, 0, 0),
    );
    expect(next.nodes.last.x, 11);
    expect(next.nodes.last.parentId, 'parent');
  });
  test('selection leaves immutable scene identical', () {
    expect(
      identical(previewRenderIntent(scene, const SelectIntent('child')), scene),
      isTrue,
    );
  });
  test('direct typed invalid moves cannot bypass parser validation', () {
    for (final intent in <RenderIntent>[
      const MoveIntent('unknown', 0, 0, 0),
      const SelectIntent('unknown'),
      const MoveIntent('child', double.nan, 0, 0),
      const MoveIntent('child', 0, double.infinity, 0),
      const MoveIntent('child', 0, 0, double.negativeInfinity),
    ]) {
      expect(() => previewRenderIntent(scene, intent), throwsArgumentError);
    }
    expect(scene.nodes.last.x, 11);
  });
  test('repeated previews retain exact entity IDs with no extra entities', () {
    var next = scene;
    for (var i = 0; i < 100; i++) {
      next = previewRenderIntent(next, MoveIntent('child', i.toDouble(), 0, 0));
    }
    expect(next.nodes.length, 2);
    expect(next.nodes.map((n) => n.id), ['parent', 'child']);
    expect(next.nodes.last.x, 99);
    expect(scene.nodes.last.x, 11);
  });
}
