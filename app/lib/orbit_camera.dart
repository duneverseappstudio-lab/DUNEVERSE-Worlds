import 'dart:math' as math;

/// Engine-independent view state. Coordinates are renderer-space, not world data.
class CameraPoint {
  final double x, y, z;
  CameraPoint(this.x, this.y, this.z) {
    if (![x, y, z].every((v) => v.isFinite)) {
      throw ArgumentError('Finite focus required');
    }
  }
}

class OrbitCameraState {
  final CameraPoint target;
  final double yaw, pitch, distance, minDistance, maxDistance;
  OrbitCameraState({
    required this.target,
    double yaw = 0,
    double pitch = .25,
    double distance = 9,
    this.minDistance = 1.5,
    this.maxDistance = 40,
  }) : yaw = _yaw(yaw),
       pitch = _pitch(pitch),
       distance = _distance(distance, minDistance, maxDistance);

  /// Minimum eye-to-center distance fitting a sphere in both frustum axes.
  /// Caller chooses margin; no authored position/radius is changed.
  static double fitDistance({
    required double radius,
    required double aspect,
    double verticalFov = math.pi / 4,
    double margin = 1.15,
  }) {
    if (![radius, aspect, verticalFov, margin].every((v) => v.isFinite) ||
        radius <= 0 ||
        aspect <= 0 ||
        verticalFov <= 0 ||
        verticalFov >= math.pi ||
        margin < 1) {
      throw ArgumentError('Invalid viewport fit');
    }
    final horizontal = 2 * math.atan(math.tan(verticalFov / 2) * aspect);
    final result =
        radius * margin / math.sin(math.min(verticalFov, horizontal) / 2);
    if (!result.isFinite) throw ArgumentError('Viewport fit overflow');
    return result;
  }

  static double _yaw(double v) {
    if (!v.isFinite) throw ArgumentError('Finite yaw required');
    return v % (2 * math.pi);
  }

  static double _pitch(double v) {
    if (!v.isFinite) throw ArgumentError('Finite pitch required');
    return v.clamp(-math.pi / 2 + .01, math.pi / 2 - .01);
  }

  static double _distance(double v, double min, double max) {
    if (![v, min, max].every((v) => v.isFinite) || min <= 0 || max < min) {
      throw ArgumentError('Invalid distance limits');
    }
    return v.clamp(min, max);
  }

  CameraPoint get position => CameraPoint(
    target.x + distance * math.cos(pitch) * math.sin(yaw),
    target.y + distance * math.sin(pitch),
    target.z + distance * math.cos(pitch) * math.cos(yaw),
  );
  OrbitCameraState update({
    CameraPoint? target,
    double? yaw,
    double? pitch,
    double? distance,
  }) => OrbitCameraState(
    target: target ?? this.target,
    yaw: yaw ?? this.yaw,
    pitch: pitch ?? this.pitch,
    distance: distance ?? this.distance,
    minDistance: minDistance,
    maxDistance: maxDistance,
  );
}
