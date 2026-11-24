import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:imperator_forge/motion_preview.dart';

MotionPreview binary() => MotionPreview(
  {
    'a': const MotionPoint(-1, 0),
    'b': const MotionPoint(2, 0),
    'planet': const MotionPoint(4, 0),
  },
  [
    MotionGroup(
      id: 'binary',
      center: const MotionPoint(0, 0),
      period: 8,
      tracks: const [CircularTrack('a', 1, math.pi), CircularTrack('b', 2, 0)],
    ),
    MotionGroup(
      id: 'planet-orbit',
      center: const MotionPoint(0, 0),
      period: 16,
      tracks: const [CircularTrack('planet', 4, 0)],
    ),
  ],
);
void main() {
  test('binary explicit shared center keeps relative separation,period anddeterminism', () {
    final p = binary();
    for (final t in [0.0, 2.0, 4.0, 8.0, 1000.0]) {
      final a = p.at(t)['a']!, b = p.at(t)['b']!;
      expect(
        math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)),
        closeTo(3, 1e-9),
      );
      expect(a.x * 2 + b.x, closeTo(0, 1e-9));
      expect(a.y * 2 + b.y, closeTo(0, 1e-9));
    }
    expect(p.at(8)['a']!.x, closeTo(-1, 1e-9));
    expect(p.at(2)['b']!.y, closeTo(2, 1e-9));
    expect(p.initial['a']!.x, -1);
  });
  test(
    'path samples identical evaluator positions andcannot mutate inputs',
    () {
      final p = binary(),
          path = binary().path('planet', from: 0, duration: 16, segments: 8);
      expect(path[2].x, closeTo(p.at(4)['planet']!.x, 1e-9));
      expect(path[2].y, closeTo(p.at(4)['planet']!.y, 1e-9));
      expect(() => path.clear(), throwsUnsupportedError);
      expect(() => p.at(0).clear(), throwsUnsupportedError);
    },
  );
  test(
    'missing bodies,duplicate ownership,cycles andinitial snap rejected',
    () {
      final initial = {
        'a': const MotionPoint(1, 0),
        'b': const MotionPoint(2, 0),
      };
      MotionGroup group(String id, String body, {String? center}) =>
          MotionGroup(
            id: id,
            center: const MotionPoint(0, 0),
            centerBodyId: center,
            period: 2,
            tracks: [CircularTrack(body, 1, 0)],
          );
      expect(
        () => MotionPreview(initial, [group('x', 'missing')]),
        throwsArgumentError,
      );
      expect(
        () => MotionPreview(initial, [group('x', 'a'), group('y', 'a')]),
        throwsArgumentError,
      );
      expect(
        () => MotionPreview(initial, [
          group('x', 'a', center: 'b'),
          group('y', 'b', center: 'a'),
        ]),
        throwsArgumentError,
      );
      expect(
        () => MotionPreview(initial, [group('x', 'b')]),
        throwsArgumentError,
      );
    },
  );
  test('moving host andchild trajectory use same evaluated time', () {
    final p = MotionPreview(
      {'s': const MotionPoint(1, 0), 'p': const MotionPoint(1.5, 0)},
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
          tracks: const [CircularTrack('p', .5, 0)],
        ),
      ],
    );
    expect(p.at(1)['p']!.x, closeTo(-.5, 1e-9));
    expect(p.at(1)['p']!.y, closeTo(1, 1e-9));
  });
  test('nonfinite input,time andunbounded path requests rejected', () {
    final p = binary();
    expect(() => p.at(double.nan), throwsArgumentError);
    expect(
      () => p.path('a', from: 0, duration: 8, segments: 513),
      throwsArgumentError,
    );
    expect(
      () => MotionPreview(
        {'a': const MotionPoint(1, 0)},
        [
          MotionGroup(
            id: 'g',
            center: const MotionPoint(0, 0),
            period: 0,
            tracks: const [CircularTrack('a', 1, 0)],
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
  test('extreme finite time reduces before angle multiplication and negative time reverses', () {
    final p = MotionPreview(
      {'a': const MotionPoint(1, 0)},
      [
        MotionGroup(
          id: 'g',
          center: const MotionPoint(0, 0),
          period: 1e-300,
          tracks: const [CircularTrack('a', 1, 0)],
        ),
      ],
    );
    final point = p.at(1e300)['a']!;
    expect(point.x.isFinite && point.y.isFinite, true);
    final ordinary = binary();
    final forward = ordinary.at(1)['a']!, back = ordinary.at(-1)['a']!;
    expect(back.x, closeTo(forward.x, 1e-9));
    expect(back.y, closeTo(-forward.y, 1e-9));
  });
  test(
    '10000-body moving-host chain evaluates iteratively without stack overflow',
    () {
      final initial = <String, MotionPoint>{'root': const MotionPoint(0, 0)};
      final groups = <MotionGroup>[];
      for (var i = 0; i < 10000; i++) {
        final id = 'b$i';
        initial[id] = MotionPoint((i + 1).toDouble(), 0);
        groups.add(
          MotionGroup(
            id: 'g$i',
            center: const MotionPoint(0, 0),
            centerBodyId: i == 0 ? 'root' : 'b${i - 1}',
            period: 4,
            tracks: [CircularTrack(id, 1, 0)],
          ),
        );
      }
      final preview = MotionPreview(initial, groups);
      final frame = preview.at(1);
      expect(frame['b9999']!.x, closeTo(0, 1e-8));
      expect(frame['b9999']!.y, closeTo(10000, 1e-8));
      expect(initial['b9999']!.x, 10000);
    },
  );
  test('10000members sharing one group keep initial order and evaluate without per-body track search', () {
    final ids = List.generate(10000, (i) => 'body$i');
    final initial = {
      for (var i = 0; i < ids.length; i++)
        ids[i]: MotionPoint((i + 1).toDouble(), 0),
    };
    final preview = MotionPreview(initial, [
      MotionGroup(
        id: 'shared',
        center: const MotionPoint(0, 0),
        period: 4,
        tracks: [
          for (var i = 0; i < ids.length; i++)
            CircularTrack(ids[i], (i + 1).toDouble(), 0),
        ],
      ),
    ]);
    final result = preview.at(1);
    expect(result.keys.toList(), ids);
    expect(result[ids.last]!.y, closeTo(10000, 1e-8));
    expect(() => result.clear(), throwsUnsupportedError);
  });
}
