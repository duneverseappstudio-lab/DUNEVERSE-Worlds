import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperator_forge/motion_preview.dart';

void main() {
  test('Dart motion matches independent Python offset-rotation reference within1e-9', () {
    final cases = jsonDecode(
      File('test/fixtures/python_reference_motion.json').readAsStringSync(),
    ) as List;
    var comparisons = 0;
    for (final c in cases) {
      final initial = {
        for (final e in (c['initial'] as Map).entries)
          e.key as String: MotionPoint(
            (e.value[0] as num).toDouble(),
            (e.value[1] as num).toDouble(),
          ),
      };
      final groups = [
        for (final g in c['groups'])
          MotionGroup(
            id: g['id'],
            center: MotionPoint(
              (g['center'][0] as num).toDouble(),
              (g['center'][1] as num).toDouble(),
            ),
            centerBodyId: g['host'],
            period: (g['period'] as num).toDouble(),
            clockwise: g['clockwise'],
            tracks: [
              CircularTrack(
                g['body'],
                (g['radius'] as num).toDouble(),
                (g['phase'] as num).toDouble(),
              ),
            ],
          ),
      ];
      final p = MotionPreview(initial, groups);
      for (final frame in c['frames']) {
        final actual = p.at((frame['time'] as num).toDouble());
        for (final e in (frame['positions'] as Map).entries) {
          expect(
            actual[e.key]!.x,
            closeTo((e.value[0] as num).toDouble(), 1e-9),
          );
          expect(
            actual[e.key]!.y,
            closeTo((e.value[1] as num).toDouble(), 1e-9),
          );
          comparisons++;
        }
      }
    }
    expect(comparisons, 3360);
  });
}
