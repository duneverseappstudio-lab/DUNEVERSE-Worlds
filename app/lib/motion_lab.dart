import 'dart:math' as math;

import 'package:flutter/scheduler.dart';

import 'package:material_ui/material_ui.dart';

import 'motion_preview.dart';
import 'forge_store.dart';
import 'main.dart' show ScenePainter;

// Explicit disposable example. No store/session passed in or imported.
MotionPreview exampleMotion() => MotionPreview(
  {
    'star-a': const MotionPoint(-.12, 0),
    'star-b': const MotionPoint(.18, 0),
    'planet': const MotionPoint(.36, 0),
  },
  [
    MotionGroup(
      id: 'example-binary',
      center: const MotionPoint(0, 0),
      period: 12,
      tracks: const [
        CircularTrack('star-a', .12, math.pi),
        CircularTrack('star-b', .18, 0),
      ],
    ),
    MotionGroup(
      id: 'example-planet',
      center: const MotionPoint(0, 0),
      period: 24,
      tracks: const [CircularTrack('planet', .36, 0)],
    ),
  ],
);

class MotionLab extends StatefulWidget {
  final bool saved;
  final MotionPreview? draftModel;
  final List<SpaceObject>? draftObjects;
  const MotionLab({
    super.key,
    this.draftModel,
    this.draftObjects,
    this.saved = false,
  });
  @override
  State<MotionLab> createState() => _MotionLabState();
}

class _MotionLabState extends State<MotionLab>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker ticker;
  final clock = ValueNotifier<double>(0);
  double accumulated = 0;
  late final MotionPreview model;
  late final MotionPathSnapshot pathSnapshot;
  bool playing = false, active = true, reduced = false;
  void sync() {
    if (playing && active && !reduced) {
      if (!ticker.isActive) {
        accumulated = clock.value;
        ticker.start();
      }
    } else {
      ticker.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    model = widget.draftModel ?? exampleMotion();
    pathSnapshot = MotionPathSnapshot(model);
    ticker = createTicker((elapsed) {
      clock.value = accumulated + elapsed.inMicroseconds / 1000000;
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = MediaQuery.disableAnimationsOf(context);
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker.dispose();
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.draftModel == null
            ? 'مختبر حركة مؤقت'
            : widget.saved
            ? 'تشغيل المدارات المحفوظة'
            : 'معاينة مسودة، بدون حفظ',
      ),
      leading: IconButton(
        key: const Key('close-motion-lab'),
        tooltip: 'العودة للمحرر',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            widget.draftModel == null
                ? 'مثال منفصل بنجمين وكوكب، لا يغيّر عالمك.\nمسارات دائرية توضيحية 2D، ليست محاكاة جاذبية أو مدارات محفوظة.'
                : widget.saved
                ? 'مدارات دائرية محفوظة بسرعات مستقلة، بدون جاذبية.\nالتشغيل لا يغير مواضع البداية.'
                : 'نسخة مؤقتة من أجسامك، لا حفظ ولا تغيير للمواضع الأصلية.\nحركة دائرية توضيحية حول مركز ثابت، ليست جاذبية.',
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: clock,
              builder: (_, _) => CustomPaint(
                key: const Key('motion-lab-canvas'),
                painter: MotionLabPainter(
                  model,
                  clock.value,
                  pathSnapshot,
                  objects: widget.draftObjects,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton.icon(
              key: const Key('motion-play'),
              onPressed: reduced
                  ? null
                  : () => setState(() {
                      playing = !playing;
                      sync();
                    }),
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              label: Text(
                playing
                    ? 'إيقاف'
                    : widget.saved
                    ? 'تشغيل'
                    : 'تشغيل المثال',
              ),
            ),
            TextButton.icon(
              key: const Key('motion-reset'),
              onPressed: () {
                setState(() {
                  playing = false;
                  ticker.stop();
                  clock.value = 0;
                });
              },
              icon: const Icon(Icons.replay),
              label: const Text('إعادة البداية'),
            ),
          ],
        ),
        if (reduced) const Text('الحركة متوقفة حسب إعداد تقليل الحركة'),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            widget.draftModel == null
                ? 'مساران متقابلان للنجمين حول مركز مشترك، ومدار للكوكب حول نفس المركز.'
                : widget.saved
                ? 'المركز يتبع حركة الجسم المختار. العودة توقف العرض ولا تلغي المدارات المحفوظة.'
                : 'كل جسم مختار يبدأ من موضعه الأصلي. التقابل بين النجوم غير مفروض. الخروج يلغي المسودة.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}

class MotionLabPainter extends CustomPainter {
  final MotionPreview model;
  final double time;
  final MotionPathSnapshot pathSnapshot;
  final List<SpaceObject>? objects;
  MotionLabPainter(this.model, this.time, this.pathSnapshot, {this.objects}) {
    if (!identical(model, pathSnapshot.model)) {
      throw ArgumentError('Path model mismatch');
    }
  }
  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height);
    Offset screen(MotionPoint p) =>
        Offset(size.width / 2 + p.x * scale, size.height / 2 + p.y * scale);
    // Paint background+objects first;thin orbit lines remain legible underneath
    // through a separate background pass andthen object pass.
    ScenePainter(const [], null, false).paint(canvas, size);
    for (final points in pathSnapshot.paths.values) {
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final p = screen(points[i]);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x7774a9bc),
      );
    }
    final positions = model.at(time);
    // The editor painter would repaint the background,so isolate object painting
    // via a transparent layer option,not by erasing the orbit paths.
    final templates = {
      for (final o in this.objects ?? <SpaceObject>[]) o.id: o,
    };
    final objects = [
      for (final id in positions.keys)
        SpaceObject(
          id,
          templates[id]?.kind ?? (id == 'planet' ? 'planet' : 'star'),
          templates[id]?.name ??
              (id == 'planet'
                  ? 'كوكب تجريبي'
                  : id == 'star-a'
                  ? 'نجم أ'
                  : 'نجم ب'),
          screen(positions[id]!).dx / size.width,
          screen(positions[id]!).dy / size.height,
          templates[id]?.radius ??
              (id == 'planet'
                  ? .025
                  : id == 'star-a'
                  ? .04
                  : .05),
        ),
    ];
    ScenePainter(
      objects,
      null,
      false,
      drawBackground: false,
      showLabels: size.height >= 260,
    ).paint(canvas, size);
    final center = screen(model.groups.first.center);
    canvas.drawLine(
      center + const Offset(-5, 0),
      center + const Offset(5, 0),
      Paint()..color = Colors.white54,
    );
    canvas.drawLine(
      center + const Offset(0, -5),
      center + const Offset(0, 5),
      Paint()..color = Colors.white54,
    );
  }

  @override
  bool shouldRepaint(covariant MotionLabPainter old) =>
      time != old.time || model != old.model;
}
