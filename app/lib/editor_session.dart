import 'forge_store.dart';
import 'render_contract.dart';

/// Application-owned bridge for the current 2D schema. No renderer writes SQL.
/// Preview is transient. Only explicit commit records one transactional change.
class EditorSession {
  final ForgeStore store;
  final String worldId;
  late List<SpaceObject> _objects;
  String? selected;
  RenderIntent? _pending;
  SpaceObject? _base;
  static const historyLimit = 100;
  final List<_GeometryCommand> _undo = [];
  final List<_GeometryCommand> _redo = [];
  bool get canUndo => !hasPreview && _undo.isNotEmpty;
  bool get canRedo => !hasPreview && _redo.isNotEmpty;

  EditorSession(this.store, this.worldId) {
    reload();
  }
  List<SpaceObject> get objects => List.unmodifiable(_objects);
  bool get hasPreview => _pending != null;
  RenderScene get scene => RenderScene([
    for (final o in _objects) SceneNode(o.id, null, o.x, o.y, 0, o.radius),
  ]);

  void reload() {
    _objects = store.objects(worldId);
    _pending = null;
    _base = null;
    if (!_objects.any((o) => o.id == selected)) selected = null;
  }

  void preview(RenderIntent intent) {
    // Validate direct typed intents as strictly as decoded messages.
    final next = previewRenderIntent(scene, intent);
    if (intent is SelectIntent) {
      if (_pending != null && _pending!.entityId != intent.entityId) {
        throw StateError('Cancel active preview before changing selection');
      }
      selected = intent.entityId;
      return;
    }
    if (intent is MoveIntent &&
        (intent.z != 0 ||
            intent.x < 0 ||
            intent.x > 1 ||
            intent.y < 0 ||
            intent.y > 1)) {
      throw ArgumentError('Current 2D schema requires normalized x/y and z=0');
    }
    if (intent is ResizeIntent &&
        (intent.radius < .01 || intent.radius > .25)) {
      throw ArgumentError('Current 2D radius must be between .01 and .25');
    }
    if (_pending != null && _pending!.entityId != intent.entityId) {
      throw StateError(
        'Commit or cancel the active move before editing another entity',
      );
    }
    _base ??= _objects.firstWhere((o) => o.id == intent.entityId);
    _objects = [
      for (var i = 0; i < _objects.length; i++)
        SpaceObject(
          _objects[i].id,
          _objects[i].kind,
          _objects[i].name,
          next.nodes[i].x,
          next.nodes[i].y,
          next.nodes[i].radius,
        ),
    ];
    _pending = intent;
  }

  void cancelPreview() => reload();

  void commitPreview() {
    final pending = _pending;
    if (pending == null) return;
    try {
      // Store compares geometry inside BEGIN IMMEDIATE before updating.
      final base = _base!;
      final next = _objects.firstWhere((o) => o.id == pending.entityId);
      if (base.x == next.x && base.y == next.y && base.radius == next.radius) {
        return;
      }
      store.save(worldId, next, expectedGeometry: base);
      _undo.add(_GeometryCommand(base, next));
      if (_undo.length > historyLimit) _undo.removeAt(0);
      _redo.clear();
    } finally {
      // Failed commits restore durable state rather than displaying false save.
      reload();
    }
  }

  /// Metadata edits preserve durable geometry and do not enter geometry history.
  void rename(String id, String value, {required String expectedName}) {
    if (hasPreview) {
      throw StateError('Finish or cancel the active preview first');
    }
    validateObjectName(value);
    try {
      final object = _objects.firstWhere((o) => o.id == id);
      store.save(
        worldId,
        SpaceObject(
          object.id,
          object.kind,
          value.trim(),
          object.x,
          object.y,
          object.radius,
        ),
        expectedName: expectedName,
      );
    } finally {
      reload();
    }
  }

  /// Undo history belongs to this editing session; inverse writes are durable.
  void undo() => _replay(_undo, _redo, backwards: true);
  void redo() => _replay(_redo, _undo, backwards: false);

  void _replay(
    List<_GeometryCommand> source,
    List<_GeometryCommand> destination, {
    required bool backwards,
  }) {
    if (hasPreview) {
      throw StateError('Finish or cancel the active preview first');
    }
    if (source.isEmpty) return;
    final command = source.last;
    final expected = backwards ? command.after : command.before;
    final target = backwards ? command.before : command.after;
    try {
      store.save(worldId, target, expectedGeometry: expected);
      source.removeLast();
      destination.add(command);
    } finally {
      reload();
    }
  }
}

class _GeometryCommand {
  final SpaceObject before, after;
  const _GeometryCommand(this.before, this.after);
}
