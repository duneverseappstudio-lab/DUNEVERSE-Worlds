import 'dart:math' as math;

import 'forge_store.dart' show SpaceObject;
import 'motion_preview.dart';

/// Authored circular path following a chosen body's motion. No gravity.
/// Radius and phase come from the current saved layout, so edits do not snap.
class AuthoredOrbit {
  final String bodyId, centerId;
  final double seconds;
  final bool clockwise;
  const AuthoredOrbit(this.bodyId, this.centerId, this.seconds, this.clockwise);
}

MotionPreview authoredMotion(
  List<SpaceObject> objects,
  List<AuthoredOrbit> orbits,
) {
  final byId = {for (final o in objects) o.id: o};
  final groups = <MotionGroup>[];
  for (final orbit in orbits) {
    final body = byId[orbit.bodyId], center = byId[orbit.centerId];
    if (body == null ||
        center == null ||
        orbit.bodyId == orbit.centerId ||
        !orbit.seconds.isFinite ||
        orbit.seconds < 1 ||
        orbit.seconds > 3600) {
      throw ArgumentError('Invalid authored orbit');
    }
    final dx = body.x - center.x, dy = body.y - center.y;
    groups.add(
      MotionGroup(
        id: body.id,
        center: const MotionPoint(0, 0),
        centerBodyId: center.id,
        period: orbit.seconds,
        clockwise: orbit.clockwise,
        tracks: [
          CircularTrack(
            body.id,
            math.sqrt(dx * dx + dy * dy),
            math.atan2(dy, dx),
          ),
        ],
      ),
    );
  }
  return MotionPreview({
    for (final o in objects) o.id: MotionPoint(o.x - .5, o.y - .5),
  }, groups);
}
