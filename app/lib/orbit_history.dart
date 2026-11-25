import 'authored_orbit.dart';
import 'forge_store.dart';

/// Local history for one orbit-editor visit. Durable values are compared in SQL
/// transactions; a conflicting path is never silently overwritten by replay.
class OrbitHistory {
  final ForgeStore store;
  final String worldId;
  static const limit = 100;
  final List<_OrbitCommand> _undo = [], _redo = [];
  OrbitHistory(this.store, this.worldId);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  AuthoredOrbit? current(String bodyId) {
    final rows = store.orbits(worldId).where((o) => o.bodyId == bodyId);
    return rows.isEmpty ? null : rows.single;
  }

  void change(
    String bodyId,
    AuthoredOrbit? next, {
    required AuthoredOrbit? expected,
  }) {
    // Check even no-ops: a stale form must not falsely report a successful save.
    store.changeOrbit(worldId, bodyId, next, compare: true, expected: expected);
    if (sameOrbit(expected, next)) return;
    _undo.add(_OrbitCommand(bodyId, expected, next));
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  void undo() => _replay(_undo, _redo, true);
  void redo() => _replay(_redo, _undo, false);
  void _replay(
    List<_OrbitCommand> source,
    List<_OrbitCommand> destination,
    bool back,
  ) {
    if (source.isEmpty) return;
    final command = source.last;
    store.changeOrbit(
      worldId,
      command.bodyId,
      back ? command.before : command.after,
      compare: true,
      expected: back ? command.after : command.before,
    );
    source.removeLast();
    destination.add(command);
  }
}

class _OrbitCommand {
  final String bodyId;
  final AuthoredOrbit? before, after;
  const _OrbitCommand(this.bodyId, this.before, this.after);
}
