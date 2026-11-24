/// Engine-independent protocol, no database or platform imports.
class SceneNode {
  final String id;
  final String? parentId;
  final double x, y, z, radius;
  const SceneNode(this.id, this.parentId, this.x, this.y, this.z, this.radius);
}

class RenderScene {
  final List<SceneNode> nodes;
  RenderScene(Iterable<SceneNode> input) : nodes = List.unmodifiable(input) {
    final byId = <String, SceneNode>{};
    for (final n in nodes) {
      if (n.id.isEmpty || byId.containsKey(n.id)) {
        throw ArgumentError('Duplicate/empty scene ID');
      }
      if (![n.x, n.y, n.z, n.radius].every((v) => v.isFinite) ||
          n.radius <= 0) {
        throw ArgumentError('Invalid transform');
      }
      byId[n.id] = n;
    }
    for (final n in nodes) {
      final seen = <String>{n.id};
      var parent = n.parentId;
      while (parent != null) {
        if (!seen.add(parent)) throw ArgumentError('Parent cycle');
        final p = byId[parent];
        if (p == null) throw ArgumentError('Missing parent');
        parent = p.parentId;
      }
    }
  }
}

/// Implementations may emit intents, never modify persistence themselves.
abstract interface class RenderAdapter {
  Future<void> loadScene(RenderScene scene);
  Future<void> select(String? entityId);
  Future<void> setCamera(double azimuth, double elevation, double distance);
  Future<void> pause();
  Future<void> resume();
  Future<void> dispose();
}

/// Only typed, validated edits can cross from a renderer into the application.
/// Applying or persisting an intent remains the application's responsibility.
sealed class RenderIntent {
  final String entityId;
  const RenderIntent(this.entityId);
}

final class MoveIntent extends RenderIntent {
  final double x, y, z;
  const MoveIntent(super.entityId, this.x, this.y, this.z);
}

final class ResizeIntent extends RenderIntent {
  final double radius;
  const ResizeIntent(super.entityId, this.radius);
}

final class SelectIntent extends RenderIntent {
  const SelectIntent(super.entityId);
}

RenderIntent parseRenderIntent(Map<String, Object?> input, RenderScene scene) {
  final id = input['entityId'];
  if (id is! String || !scene.nodes.any((n) => n.id == id)) {
    throw ArgumentError('Unknown entity');
  }
  switch (input['type']) {
    case 'select':
      if (input.keys.toSet().difference({'type', 'entityId'}).isNotEmpty) {
        throw ArgumentError('Unexpected select fields');
      }
      return SelectIntent(id);
    case 'resize':
      if (input.keys.toSet().difference({
        'type',
        'entityId',
        'radius',
      }).isNotEmpty) {
        throw ArgumentError('Unexpected resize fields');
      }
      final radius = input['radius'];
      if (radius is! num || !radius.isFinite || radius <= 0) {
        throw ArgumentError('Invalid radius');
      }
      return ResizeIntent(id, radius.toDouble());
    case 'move':
      if (input.keys.toSet().difference({
        'type',
        'entityId',
        'x',
        'y',
        'z',
      }).isNotEmpty) {
        throw ArgumentError('Unexpected move fields');
      }
      double coordinate(String key) {
        final value = input[key];
        if (value is! num || !value.isFinite) {
          throw ArgumentError('Invalid coordinate');
        }
        return value.toDouble();
      }
      return MoveIntent(id, coordinate('x'), coordinate('y'), coordinate('z'));
    default:
      throw ArgumentError('Unknown renderer intent');
  }
}

/// Pure preview reducer. Does not persist, create entities, or infer hierarchy.
/// Coordinates stay world-space. Selection does not change the scene.
RenderScene previewRenderIntent(RenderScene scene, RenderIntent intent) {
  if (!scene.nodes.any((n) => n.id == intent.entityId)) {
    throw ArgumentError('Unknown entity');
  }
  if (intent is SelectIntent) return scene;
  if (intent is ResizeIntent) {
    if (!intent.radius.isFinite || intent.radius <= 0) {
      throw ArgumentError('Invalid radius');
    }
    return RenderScene([
      for (final node in scene.nodes)
        if (node.id == intent.entityId)
          SceneNode(
            node.id,
            node.parentId,
            node.x,
            node.y,
            node.z,
            intent.radius,
          )
        else
          node,
    ]);
  }
  final move = intent as MoveIntent;
  if (![move.x, move.y, move.z].every((v) => v.isFinite)) {
    throw ArgumentError('Invalid coordinate');
  }
  return RenderScene([
    for (final node in scene.nodes)
      if (node.id == move.entityId)
        SceneNode(node.id, node.parentId, move.x, move.y, move.z, node.radius)
      else
        node,
  ]);
}
