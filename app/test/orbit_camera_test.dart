import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:imperator_forge/orbit_camera.dart';

void main() {
  test(
    'full turn visits front side back and returns to original around focus',
    () {
      final s = OrbitCameraState(
        target: CameraPoint(3, 2, -4),
        pitch: 0,
        distance: 5,
      );
      final expected = [
        [3, 2, 1],
        [8, 2, -4],
        [3, 2, -9],
        [-2, 2, -4],
        [3, 2, 1],
      ];
      for (var i = 0; i < 5; i++) {
        final p = s.update(yaw: i * math.pi / 2).position;
        for (final pair in [
          [p.x, expected[i][0]],
          [p.y, expected[i][1]],
          [p.z, expected[i][2]],
        ]) {
          expect(pair[0], closeTo(pair[1], 1e-9));
        }
      }
    },
  );
  test('pitch avoids pole flip, zoom clamps and focus switch preserves view offset', () {
    final s = OrbitCameraState(
      target: CameraPoint(0, 0, 0),
      pitch: 100,
      distance: -5,
    );
    expect(s.distance, 1.5);
    expect(s.pitch, lessThan(math.pi / 2));
    final p = s.position, q = s.update(target: CameraPoint(3, 4, 5)).position;
    expect(q.x - p.x, closeTo(3, 1e-9));
    expect(q.y - p.y, closeTo(4, 1e-9));
    expect(q.z - p.z, closeTo(5, 1e-9));
    expect(s.update(distance: 999).distance, 40);
    expect(s.update(yaw: -math.pi).yaw, closeTo(math.pi, 1e-9));
  });
  test('nonfinite state and invalid clipping limits rejected', () {
    expect(() => CameraPoint(double.nan, 0, 0), throwsArgumentError);
    for (final value in [double.nan, double.infinity]) {
      expect(
        () => OrbitCameraState(target: CameraPoint(0, 0, 0), yaw: value),
        throwsArgumentError,
      );
      expect(
        () => OrbitCameraState(target: CameraPoint(0, 0, 0), pitch: value),
        throwsArgumentError,
      );
      expect(
        () => OrbitCameraState(target: CameraPoint(0, 0, 0), distance: value),
        throwsArgumentError,
      );
    }
    expect(
      () => OrbitCameraState(target: CameraPoint(0, 0, 0), minDistance: 0),
      throwsArgumentError,
    );
  });
  test('sphere fit respects both frustum axes including portrait viewport', () {
    for (final aspect in [.25, .5, 1.0, 2.0, 4.0]) {
      final d = OrbitCameraState.fitDistance(radius: 2, aspect: aspect);
      final angularRadius = math.asin(2 / d);
      final horizontalHalf = math.atan(math.tan(math.pi / 8) * aspect);
      expect(angularRadius, lessThan(math.pi / 8));
      expect(angularRadius, lessThan(horizontalHalf));
    }
    expect(
      OrbitCameraState.fitDistance(radius: 2, aspect: 1),
      closeTo(2 * OrbitCameraState.fitDistance(radius: 1, aspect: 1), 1e-9),
    );
  });
  test('invalid viewport fitting cannot silently create NaN camera', () {
    for (final aspect in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => OrbitCameraState.fitDistance(radius: 1, aspect: aspect),
        throwsArgumentError,
      );
    }
    expect(
      () => OrbitCameraState.fitDistance(radius: 0, aspect: 1),
      throwsArgumentError,
    );
    expect(
      () => OrbitCameraState.fitDistance(
        radius: 1,
        aspect: 1,
        verticalFov: math.pi,
      ),
      throwsArgumentError,
    );
    expect(
      () => OrbitCameraState.fitDistance(radius: 1, aspect: 1, margin: .5),
      throwsArgumentError,
    );
  });
}
