import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imperator_forge/forge_store.dart';
import 'package:imperator_forge/main.dart';

void main() {
  test('2D scene raster export yields a decodable offline PNG', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
    await loader.load();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xff141820), ui.BlendMode.src);
    ScenePainter(
      [
        const SpaceObject('s', 'star', 'شمس', .3, .4, .055),
        const SpaceObject('p', 'planet', 'كوكب الرمال', .7, .6, .035),
      ],
      null,
      false,
    ).paint(canvas, const ui.Size(800, 600));
    final picture = recorder.endRecording();
    final image = await picture.toImage(800, 600);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final decoded = await codec.getNextFrame();
    expect(decoded.image.width, 800);
    expect(decoded.image.height, 600);
    await File(
      Platform.environment['IWF_EXPORT_TEST_PNG'] ??
          '${Directory.systemTemp.path}/imperator-canvas-export.png',
    ).writeAsBytes(bytes.buffer.asUint8List());
    decoded.image.dispose();
    codec.dispose();
    image.dispose();
    picture.dispose();
  });
  test('2D diagnostic draws 1000 labeled objects, not a device benchmark', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final objects = List.generate(
      1000,
      (i) => SpaceObject(
        'p$i',
        'planet',
        '$i',
        (i % 40 + .5) / 40,
        (i ~/ 40 + .5) / 25,
        .004,
      ),
    );
    final times = <int>[];
    for (var i = 0; i < 5; i++) {
      final timer = Stopwatch()..start();
      final recorder = ui.PictureRecorder();
      ScenePainter(
        objects,
        null,
        false,
      ).paint(ui.Canvas(recorder), const ui.Size(1200, 800));
      final picture = recorder.endRecording();
      final image = await picture.toImage(1200, 800);
      timer.stop();
      times.add(timer.elapsedMicroseconds);
      image.dispose();
      picture.dispose();
    }
    times.sort();
    // Captures paint plus software test rasterization, not app frame pacing.
    // ignore: avoid_print
    print(
      '1000 labeled bodies paint+raster microseconds: $times; median=${times[2]}',
    );
    expect(times.length, 5);
  });
}
