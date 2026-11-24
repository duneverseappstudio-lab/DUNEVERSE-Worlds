// Explicit kinematic2Dtrajectory prototype,not a gravity solver.
// No database/editor imports. Units and relationships come from the caller.
import 'dart:math' as math;

import 'dependency_order.dart';

class MotionPoint {
  final double x, y;
  const MotionPoint(this.x, this.y);
  MotionPoint operator +(MotionPoint other) =>
      MotionPoint(x + other.x, y + other.y);
}

class CircularTrack {
  final String bodyId;
  final double radius, phase;
  const CircularTrack(this.bodyId, this.radius, this.phase);
}

class MotionGroup {
  final String id;
  final MotionPoint center;
  final String? centerBodyId;
  final double period;
  final bool clockwise;
  final List<CircularTrack> tracks;

  /// Tracks explicitly share a center andperiod. A binary fixture uses opposite
  /// phases;radius ratio is caller-supplied,not inferred from nonexistent mass.
  MotionGroup({
    required this.id,
    required this.center,
    required this.period,
    required Iterable<CircularTrack> tracks,
    this.centerBodyId,
    this.clockwise = false,
  }) : tracks = List.unmodifiable(tracks);
}

class MotionPreview {
  final Map<String, MotionPoint> initial;
  final List<MotionGroup> groups;
  late final List<String> evaluationOrder;
  late final Map<String, MotionGroup> _groupByBody;
  late final Map<String, CircularTrack> _trackByBody;
  MotionPreview(Map<String, MotionPoint> initial, Iterable<MotionGroup> groups)
    : initial = Map.unmodifiable(initial),
      groups = List.unmodifiable(groups) {
    if (initial.keys.any((id) => id.isEmpty) ||
        initial.values.any((p) => !p.x.isFinite || !p.y.isFinite)) {
      throw ArgumentError('Invalid authored positions');
    }
    final groupIds = <String>{}, owners = <String, String>{};
    for (final g in this.groups) {
      if (g.id.isEmpty ||
          !groupIds.add(g.id) ||
          !g.period.isFinite ||
          g.period <= 0 ||
          !g.center.x.isFinite ||
          !g.center.y.isFinite ||
          g.tracks.isEmpty ||
          (g.centerBodyId != null && !initial.containsKey(g.centerBodyId))) {
        throw ArgumentError('Invalid motion group');
      }
      for (final t in g.tracks) {
        if (!initial.containsKey(t.bodyId) ||
            owners.containsKey(t.bodyId) ||
            !t.radius.isFinite ||
            t.radius <= 0 ||
            !t.phase.isFinite) {
          throw ArgumentError('Invalid/duplicate track');
        }
        owners[t.bodyId] = g.id;
      }
    }
    _groupByBody = Map.unmodifiable({
      for (final g in this.groups)
        for (final t in g.tracks) t.bodyId: g,
    });
    _trackByBody = Map.unmodifiable({
      for (final g in this.groups)
        for (final t in g.tracks) t.bodyId: t,
    });
    evaluationOrder = dependencyOrder(this.initial.keys.toSet(), {
      for (final g in this.groups)
        for (final t in g.tracks) t.bodyId: g.centerBodyId,
    });
    // No silent snap from authored layout at t0. A caller must explicitly edit
    // initial placement or orbit parameters before constructing a valid preview.
    final evaluated = at(0);
    for (final id in owners.keys) {
      final a = initial[id]!, b = evaluated[id]!;
      if ((a.x - b.x).abs() > 1e-9 || (a.y - b.y).abs() > 1e-9) {
        throw ArgumentError('Trajectory does not match authored initial state');
      }
    }
  }
  Map<String, MotionPoint> at(double time) {
    if (!time.isFinite) throw ArgumentError('Invalid time');
    final output = <String, MotionPoint>{};
    void position(String id) {
      final g = _groupByBody[id];
      if (g == null) {
        output[id] = initial[id]!;
        return;
      }
      final center = g.centerBodyId == null
          ? g.center
          : output[g.centerBodyId!]! + g.center;
      final track = _trackByBody[id]!;
      final angle =
          track.phase.remainder(math.pi * 2) +
          (time.remainder(g.period) / g.period) *
              math.pi *
              2 *
              (g.clockwise ? -1 : 1);
      final p =
          center +
          MotionPoint(
            math.cos(angle) * track.radius,
            math.sin(angle) * track.radius,
          );
      if (!p.x.isFinite || !p.y.isFinite) {
        throw StateError('Trajectory overflow');
      }
      output[id] = p;
    }

    for (final id in evaluationOrder) {
      position(id);
    }
    return Map.unmodifiable({for (final id in initial.keys) id: output[id]!});
  }

  /// Draw the path using the same evaluation as the animated body. For a moving
  /// center this returns the actualworld trajectory,not a misleading static ring.
  List<MotionPoint> path(
    String bodyId, {
    required double from,
    required double duration,
    int segments = 96,
  }) {
    if (!initial.containsKey(bodyId) ||
        !from.isFinite ||
        !duration.isFinite ||
        duration <= 0 ||
        segments < 8 ||
        segments > 512 ||
        (from + duration).isInfinite) {
      throw ArgumentError('Invalid path request');
    }
    return List.unmodifiable(
      List.generate(
        segments + 1,
        (i) => at(from + duration * (i / segments))[bodyId]!,
      ),
    );
  }
}

/// Finite immutable path samples for one explicit window per tracked body.
/// Not a growing memoization cache. Rebuild only for a new model/window.
class MotionPathSnapshot {
  final MotionPreview model;
  final Map<String, List<MotionPoint>> paths;
  MotionPathSnapshot(this.model, {int segments = 96})
    : paths = Map.unmodifiable({
        for (final group in model.groups)
          for (final track in group.tracks)
            track.bodyId: model.path(
              track.bodyId,
              from: 0,
              duration: group.period,
              segments: segments,
            ),
      });
}
