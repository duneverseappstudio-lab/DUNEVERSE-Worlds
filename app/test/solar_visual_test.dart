import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/main.dart';

Future<ByteData> render(List<SpaceObject> objects) async {
  final recorder = ui.PictureRecorder();
  ScenePainter(
    objects,
    null,
    false,
  ).paint(ui.Canvas(recorder), const ui.Size(400, 300));
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 300);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int light(ByteData b, int x, int y) {
  final i = (y * 400 + x) * 4;
  return b.getUint8(i) + b.getUint8(i + 1) + b.getUint8(i + 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const planet = SpaceObject('p', 'planet', '', .5, .5, .2);
  test(
    'procedural surface and sky render deterministically without mutation',
    () async {
      final objects = [planet, const SpaceObject('s', 'star', '', .1, .5, .05)];
      final first = await render(objects), second = await render(objects);
      expect(first.buffer.asUint8List(), second.buffer.asUint8List());
      expect(objects.first.x, .5);
      expect(objects.first.radius, .2);
    },
  );
  test(
    'planet light side follows nearest star when light crosses it',
    () async {
      final left = await render([
        planet,
        const SpaceObject('s', 'star', '', .1, .5, .03),
      ]);
      final right = await render([
        planet,
        const SpaceObject('s', 'star', '', .9, .5, .03),
      ]);
      // Same fixed surface pixel,only lighting input changes.
      expect(light(left, 158, 150), greaterThan(light(right, 158, 150) + 30));
      expect(light(right, 242, 150), greaterThan(light(left, 242, 150) + 30));
    },
  );
  test(
    'coincident star and no-star fallback remain finite and drawable',
    () async {
      expect((await render([planet])).lengthInBytes, 400 * 300 * 4);
      expect(
        (await render([
          planet,
          const SpaceObject('s', 'star', '', .5, .5, .03),
        ])).lengthInBytes,
        400 * 300 * 4,
      );
    },
  );
}
