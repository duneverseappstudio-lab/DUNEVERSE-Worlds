import 'package:flutter_test/flutter_test.dart';
import 'package:imperator_forge/motion_preview.dart';
import 'package:imperator_forge/motion_lab.dart';

class CountingPreview extends MotionPreview {
  int pathCalls = 0;
  CountingPreview()
    : super(
        {'a': const MotionPoint(1, 0)},
        [
          MotionGroup(
            id: 'g',
            center: const MotionPoint(0, 0),
            period: 4,
            tracks: const [CircularTrack('a', 1, 0)],
          ),
        ],
      );
  @override
  List<MotionPoint> path(
    String id, {
    required double from,
    required double duration,
    int segments = 96,
  }) {
    pathCalls++;
    return super.path(id, from: from, duration: duration, segments: segments);
  }
}

void main() {
  test('path snapshot samples once and remains bounded through1000animation frames', () {
    final model = CountingPreview();
    final snapshot = MotionPathSnapshot(model);
    expect(model.pathCalls, 1);
    expect(snapshot.paths['a']!.length, 97);
    for (var i = 0; i < 1000; i++) {
      MotionLabPainter(model, i / 60, snapshot);
      model.at(i / 60);
    }
    expect(model.pathCalls, 1);
    expect(snapshot.paths.length, 1);
    expect(() => snapshot.paths.clear(), throwsUnsupportedError);
    expect(() => snapshot.paths['a']!.clear(), throwsUnsupportedError);
    expect(
      () => MotionLabPainter(CountingPreview(), 0, snapshot),
      throwsArgumentError,
    );
  });
  test('snapshot equals evaluator for moving host and is explicit about fixed window', () {
    final model = MotionPreview(
      {'s': const MotionPoint(1, 0), 'p': const MotionPoint(2, 0)},
      [
        MotionGroup(
          id: 's',
          center: const MotionPoint(0, 0),
          period: 4,
          tracks: const [CircularTrack('s', 1, 0)],
        ),
        MotionGroup(
          id: 'p',
          center: const MotionPoint(0, 0),
          centerBodyId: 's',
          period: 2,
          tracks: const [CircularTrack('p', 1, 0)],
        ),
      ],
    );
    final snapshot = MotionPathSnapshot(model, segments: 8);
    for (var i = 0; i <= 8; i++) {
      final expected = model.at(i * 2 / 8)['p']!;
      final actual = snapshot.paths['p']![i];
      expect(actual.x, expected.x);
      expect(actual.y, expected.y);
    }
  });
}
