import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

// Illustrative2Dsolar art. View-only,no persistence/session access.
void paintSolarStar(
  Canvas canvas,
  Offset c,
  double r, {
  double phase = 0,
  bool detail = false,
}) {
  if (r <= 0) return;
  if (!detail) {
    final halo = Rect.fromCircle(center: c, radius: r * 3.5);
    canvas.drawCircle(
      c,
      r * 3.5,
      Paint()
        ..shader = RadialGradient(
          colors: const [
            Color(0x99ffda72),
            Color(0x45ff982e),
            Color(0x00ff701f),
          ],
          stops: const [0, .35, 1],
        ).createShader(halo),
    );
  }
  final rect = Rect.fromCircle(center: c, radius: r);
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(-.2, -.2),
        colors: [Color(0xfffff8cd), Color(0xffffdc69), Color(0xffef8528)],
        stops: [0, .65, 1],
      ).createShader(rect),
  );
  canvas.save();
  canvas.clipPath(Path()..addOval(rect));
  final noise = math.Random(91);
  for (var i = 0; i < 110; i++) {
    final point =
        c +
        Offset(
          (noise.nextDouble() * 2 - 1) * r,
          (noise.nextDouble() * 2 - 1) * r,
        );
    canvas.drawCircle(
      point,
      r * (.01 + noise.nextDouble() * .035),
      Paint()..color = Color(i.isEven ? 0x32fffce6 : 0x25b84b0c),
    );
  }
  canvas.restore();
  if (!detail) return;
  // Bounded, filled tapering ribbons. Illustrative art, not plasma physics.
  // Every frame is a pure function of phase: no particle accumulation.
  for (var i = 0; i < 17; i++) {
    final angle = i * math.pi * 2 / 17 + .13 + math.sin(i * 4.7) * .10;
    final pulse = .5 + .5 * math.sin(phase * math.pi * 2 + i * 1.71);
    final direction = Offset(math.cos(angle), math.sin(angle));
    final tangent = Offset(-direction.dy, direction.dx);
    final height =
        r * (.07 + .22 * pulse) * (.65 + .35 * math.sin(i * 2.1).abs());
    final curl = r * (.035 + .09 * math.sin(phase * math.pi * 2 + i));
    final width = r * (.023 + .018 * math.sin(i * 3.7).abs());
    final base = c + direction * (r * .97);
    final tip = c + direction * (r + height) + tangent * curl;
    for (var layer = 0; layer < 3; layer++) {
      final w = width * (1 - layer * .27);
      final peak = tip - direction * (height * layer * .13);
      final start = base - tangent * w;
      final end = base + tangent * w;
      final shoulder = base + direction * height * .48 - tangent * w * .5;
      final back = base + direction * height * .32 + tangent * w * .7;
      final flame = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          shoulder.dx,
          shoulder.dy,
          (peak - tangent * w * .7).dx,
          (peak - tangent * w * .7).dy,
          peak.dx,
          peak.dy,
        )
        ..cubicTo(
          (peak - direction * height * .38).dx,
          (peak - direction * height * .38).dy,
          back.dx,
          back.dy,
          end.dx,
          end.dy,
        )
        ..close();
      canvas.drawPath(
        flame,
        Paint()
          ..color = const [
            Color(0x79f34c12),
            Color(0xbaff922a),
            Color(0xdfffd56b),
          ][layer],
      );
    }
  }
}

class StarCloseup extends StatefulWidget {
  final String name;
  const StarCloseup({super.key, required this.name});
  @override
  State<StarCloseup> createState() => _StarCloseupState();
}

class _StarCloseupState extends State<StarCloseup>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController motion;
  bool paused = false, reduced = false, active = true;
  double zoom = 1;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    motion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
  }

  void syncMotion() {
    if (!paused && !reduced && active) {
      motion.repeat();
    } else {
      motion.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = MediaQuery.disableAnimationsOf(context);
    syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    syncMotion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        key: const Key('close-star-detail'),
        tooltip: 'العودة للمحرر',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text('تقريب النجم: ${widget.name}'),
    ),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'تقريب بصري فقط، لا يغيّر نصف القطر المحفوظ.\nألسنة توهج توضيحية 2D، ليست محاكاة فيزيائية.',
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: motion,
              builder: (context, _) => CustomPaint(
                key: const Key('star-detail-canvas'),
                painter: StarDetailPainter(phase: motion.value, zoom: zoom),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        Row(
          children: [
            const SizedBox(width: 12),
            const Text('تقريب العرض'),
            Expanded(
              child: Slider(
                key: const Key('view-zoom'),
                value: zoom,
                min: 1,
                max: 1.6,
                onChanged: (value) => setState(() => zoom = value),
              ),
            ),
            Text('${zoom.toStringAsFixed(1)}×'),
            const SizedBox(width: 12),
          ],
        ),
        TextButton.icon(
          key: const Key('star-pause'),
          onPressed: reduced
              ? null
              : () => setState(() {
                  paused = !paused;
                  syncMotion();
                }),
          icon: Icon(paused || reduced ? Icons.play_arrow : Icons.pause),
          label: Text(
            reduced
                ? 'الحركة متوقفة حسب إعداد تقليل الحركة'
                : paused
                ? 'تشغيل التوهج'
                : 'إيقاف التوهج',
          ),
        ),
      ],
    ),
  );
}

class StarDetailPainter extends CustomPainter {
  final double phase, zoom;
  StarDetailPainter({required this.phase, required this.zoom});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff050812),
    );
    paintSolarStar(
      canvas,
      Offset(size.width / 2, size.height / 2),
      math.min(size.width, size.height) * .21 * zoom,
      phase: phase,
      detail: true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StarDetailPainter old) =>
      phase != old.phase || zoom != old.zoom;
}
