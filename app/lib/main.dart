import 'orbit_editor.dart';

import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import 'forge_store.dart';
import 'editor_session.dart';
import 'star_detail.dart';
import 'motion_lab.dart';
import 'render_contract.dart' as render;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Paint an app-owned status before waiting on a platform plugin or storage.
  runApp(const StartupGate());
}

Future<ForgeStore> openStartupStore({
  Duration stepTimeout = const Duration(seconds: 15),
}) async {
  debugPrint('DUNEVERSE startup: support-directory');
  final root = await getApplicationSupportDirectory().timeout(stepTimeout);
  debugPrint('DUNEVERSE startup: create-directory');
  await root.create(recursive: true).timeout(stepTimeout);
  // SQLite open/schema setup is synchronous. A Dart timeout cannot interrupt it.
  debugPrint('DUNEVERSE startup: sqlite-open');
  final db = sqlite3.open('${root.path}${Platform.pathSeparator}phase0.sqlite');
  try {
    final store = ForgeStore(db);
    store.ensureWorld('technical-proof', 'اختبار المحرر');
    debugPrint('DUNEVERSE startup: editor-ready');
    return store;
  } catch (_) {
    db.close();
    rethrow;
  }
}

class StartupGate extends StatefulWidget {
  final Future<ForgeStore> Function()? initialize;
  const StartupGate({super.key, this.initialize});
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  ForgeStore? store;
  bool failed = false;
  bool busy = false;
  int attempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) start();
    });
  }

  Future<void> start() async {
    if (busy || store != null) return;
    busy = true;
    final current = ++attempt;
    setState(() => failed = false);
    try {
      final opened = await (widget.initialize ?? openStartupStore)();
      if (!mounted || current != attempt) {
        opened.db.close();
        return;
      }
      setState(() => store = opened);
    } catch (error) {
      // Avoid logging paths, database contents or exception text.
      debugPrint('DUNEVERSE startup: failed (${error.runtimeType})');
      if (mounted && current == attempt) setState(() => failed = true);
    } finally {
      if (mounted && current == attempt) busy = false;
    }
  }

  @override
  void dispose() {
    attempt++;
    store?.db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (store case final opened?) return ForgeApp(store: opened);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Cairo'),
      home: Scaffold(
        body: Center(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!failed)
                  const Icon(
                    Icons.hourglass_empty,
                    size: 32,
                    semanticLabel: 'جارٍ الفتح',
                  ),
                const SizedBox(height: 16),
                Text(
                  failed
                      ? 'تعذر فتح التخزين المحلي. حاول مرة أخرى.'
                      : 'جارٍ فتح عالمك...',
                ),
                if (failed)
                  TextButton(
                    key: const Key('startup-retry'),
                    onPressed: start,
                    child: const Text('إعادة المحاولة'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ForgeApp extends StatelessWidget {
  final ForgeStore store;
  const ForgeApp({super.key, required this.store});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      fontFamily: 'Cairo',
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff141820),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffd8b76c),
        brightness: Brightness.dark,
      ),
    ),
    home: ProofEditor(store: store),
  );
}

class ProofEditor extends StatefulWidget {
  final ForgeStore store;
  const ProofEditor({super.key, required this.store});
  @override
  State<ProofEditor> createState() => _ProofEditorState();
}

class _ProofEditorState extends State<ProofEditor> with WidgetsBindingObserver {
  String world = 'technical-proof';
  late EditorSession session;
  List<SpaceObject> get objects => session.objects;
  String? get selected => session.selected;
  set selected(String? value) => session.selected = value;
  String status = 'محفوظ محليًا';
  bool globe = false;
  int serial = 0;
  bool ignoreCurrentDrag = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session = EditorSession(widget.store, world);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && session.hasPreview) {
      setState(() {
        session.cancelPreview();
        ignoreCurrentDrag = true;
        status = 'أُلغيت الحركة، المحفوظ لم يتغير';
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> chooseWorld() async {
    final next = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('عوالمك المحلية'),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final w in widget.store.worlds())
                    ListTile(
                      title: Text(w.name),
                      selected: w.id == world,
                      trailing: w.id == world ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.pop(sheet, w.id),
                    ),
                ],
              ),
            ),
            TextButton.icon(
              key: const Key('create-world'),
              icon: const Icon(Icons.add),
              label: const Text('عالم جديد فارغ'),
              onPressed: () => Navigator.pop(sheet, ''),
            ),
          ],
        ),
      ),
    );
    if (!mounted || next == null) return;
    if (next.isEmpty) {
      await createWorld();
      return;
    }
    if (next == world) return;
    setState(() {
      session.cancelPreview();
      world = next;
      session = EditorSession(widget.store, world);
      globe = false;
      ignoreCurrentDrag = true;
      status = 'فُتح العالم، الحركات غير المؤكدة أُلغيت';
    });
  }

  Future<void> createWorld() async {
    final controller = TextEditingController();
    String? error;
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setDialogState) => AlertDialog(
          title: const Text('إنشاء عالم محلي'),
          content: TextField(
            key: const Key('world-name'),
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'اسم العالم',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('إلغاء'),
            ),
            TextButton(
              key: const Key('confirm-create-world'),
              onPressed: () {
                try {
                  validateObjectName(controller.text);
                  Navigator.pop(dialog, controller.text.trim());
                } catch (_) {
                  setDialogState(
                    () => error = 'اكتب اسمًا من حرف إلى 80 حرفًا',
                  );
                }
              },
              child: const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
    // Dispose after the dialog's closing transition has detached its text field.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (!mounted || name == null) return;
    try {
      final id = 'world-${DateTime.now().microsecondsSinceEpoch}-${serial++}';
      widget.store.createWorld(id, name);
      setState(() {
        session.cancelPreview();
        world = id;
        session = EditorSession(widget.store, world);
        globe = false;
        ignoreCurrentDrag = true;
        status = 'عالم جديد فارغ، محفوظ محليًا';
      });
    } catch (_) {
      setState(() => status = 'تعذر إنشاء العالم، لم يتغير العالم المفتوح');
    }
  }

  void historyMove(bool redo) {
    try {
      if (redo) {
        session.redo();
      } else {
        session.undo();
      }
      setState(() => status = 'محفوظ محليًا');
    } catch (_) {
      setState(() => status = 'تعذر تغيير الحركة، المحفوظ لم يتغير');
    }
  }

  void resizeSelected(double factor) {
    if (selected == null || globe || session.hasPreview) return;
    final object = objects.firstWhere((o) => o.id == selected);
    try {
      session.preview(
        render.ResizeIntent(
          object.id,
          (object.radius * factor).clamp(.01, .25),
        ),
      );
      session.commitPreview();
      setState(() => status = 'محفوظ محليًا');
    } catch (_) {
      setState(() => status = 'فشل تغيير الحجم، المحفوظ لم يتغير');
    }
  }

  void nudgeSelected(Offset delta) {
    if (selected == null || globe || session.hasPreview) return;
    final object = objects.firstWhere((o) => o.id == selected);
    try {
      session.preview(
        render.MoveIntent(
          object.id,
          (object.x + delta.dx).clamp(0, 1),
          (object.y + delta.dy).clamp(0, 1),
          0,
        ),
      );
      session.commitPreview();
      setState(() => status = 'محفوظ محليًا');
    } catch (_) {
      setState(() => status = 'فشل التحريك، المحفوظ لم يتغير');
    }
  }

  Future<void> renameSelected() async {
    if (selected == null || globe || session.hasPreview) return;
    final object = objects.firstWhere((o) => o.id == selected);
    var draftName = object.name;
    final form = GlobalKey<FormState>();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اسم العنصر'),
        content: Form(
          key: form,
          child: TextFormField(
            key: const Key('object-name'),
            initialValue: object.name,
            onChanged: (value) => draftName = value,
            autofocus: true,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              helperText: 'حتى 80 حرفًا، الحفظ بعد التأكيد',
            ),
            validator: (value) {
              try {
                validateObjectName(value ?? '');
                return null;
              } catch (_) {
                return 'اكتب اسمًا من 1 إلى 80 حرفًا دون أسطر جديدة';
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, draftName);
              }
            },
            child: const Text('حفظ الاسم'),
          ),
        ],
      ),
    );
    if (!mounted || value == null) return;
    try {
      session.rename(object.id, value, expectedName: object.name);
      setState(() => status = 'حُفظ الاسم محليًا، التراجع للحركة والحجم فقط');
    } catch (_) {
      setState(() => status = 'تعذر حفظ الاسم، أعد فتحه للمراجعة');
    }
  }

  void add(String kind, Offset pos) {
    if (globe) return;
    final id = '${DateTime.now().microsecondsSinceEpoch}-${serial++}';
    final saved = commit(
      SpaceObject(
        id,
        kind,
        bodyName(kind),
        pos.dx.clamp(0, 1),
        pos.dy.clamp(0, 1),
        kind == 'star'
            ? 0.055
            : kind == 'planet'
            ? 0.035
            : 0.02,
      ),
    );
    if (saved) setState(() => selected = id);
  }

  bool commit(SpaceObject o) {
    try {
      widget.store.save(world, o);
      setState(() {
        session.reload();
        status = 'محفوظ محليًا';
      });
      return true;
    } catch (_) {
      setState(() {
        status = 'فشل الحفظ، لم يُعتمد التغيير';
        session.reload();
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextButton.icon(
        key: const Key('choose-world'),
        onPressed: chooseWorld,
        icon: const Icon(Icons.public),
        label: Text(
          widget.store.worlds().firstWhere((w) => w.id == world).name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              key: const Key('open-orbit-draft'),
              tooltip: 'مدارات العالم المحفوظة',
              onPressed: session.hasPreview || globe || objects.length < 2
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            OrbitEditor(store: widget.store, worldId: world),
                      ),
                    ),
              icon: const Icon(Icons.track_changes),
            ),

            IconButton(
              key: const Key('open-motion-lab'),
              tooltip: 'مختبر حركة مؤقت، لا يغير العالم',
              onPressed: session.hasPreview
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MotionLab(),
                      ),
                    ),
              icon: const Icon(Icons.science_outlined),
            ),

            IconButton(
              tooltip: 'تراجع عن التحريك أو الحجم، للجلسة الحالية',
              onPressed: session.canUndo ? () => historyMove(false) : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'إعادة التحريك أو الحجم، للجلسة الحالية',
              onPressed: session.canRedo ? () => historyMove(true) : null,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              tooltip: globe ? 'عرض 2D' : 'اختبار إسقاط الكرة',
              onPressed: () => setState(() {
                session.cancelPreview();
                status = 'محفوظ محليًا';
                globe = !globe;
              }),
              icon: Icon(globe ? Icons.grid_on : Icons.public),
            ),
          ],
        ),
      ),
    ),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(10),
          child: Text('معاينة مظللة 2D، ليست محاكاة فلكية أو محرك 3D'),
        ),
        Wrap(
          spacing: 12,
          children: [
            for (final kind in ['star', 'planet', 'moon', 'rock'])
              Draggable<String>(
                dragAnchorStrategy: pointerDragAnchorStrategy,
                maxSimultaneousDrags: globe ? 0 : 1,
                data: kind,
                feedback: Material(
                  color: Colors.transparent,
                  child: Icon(bodyIcon(kind), size: 44, color: Colors.amber),
                ),
                child: OutlinedButton.icon(
                  onPressed: globe
                      ? null
                      : () => add(kind, const Offset(.5, .5)),
                  icon: Icon(bodyIcon(kind)),
                  label: Text('إضافة ${bodyName(kind)}'),
                ),
              ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) => DragTarget<String>(
              onWillAcceptWithDetails: (_) => !globe,
              onAcceptWithDetails: (d) {
                final box = context.findRenderObject()! as RenderBox;
                final p = box.globalToLocal(d.offset);
                add(
                  d.data,
                  Offset(p.dx / bounds.maxWidth, p.dy / bounds.maxHeight),
                );
              },
              builder: (context, candidates, rejected) => Listener(
                onPointerCancel: (_) => setState(() {
                  session.cancelPreview();
                  status = 'أُلغيت الحركة، المحفوظ لم يتغير';
                }),
                child: GestureDetector(
                  key: const Key('workspace'),
                  onTapDown: (d) {
                    if (session.hasPreview) session.cancelPreview();
                    SpaceObject? hit;
                    for (final o in objects.reversed) {
                      if ((Offset(
                                    o.x * bounds.maxWidth,
                                    o.y * bounds.maxHeight,
                                  ) -
                                  d.localPosition)
                              .distance <
                          o.radius *
                                  math.min(bounds.maxWidth, bounds.maxHeight) +
                              16) {
                        hit = o;
                        break;
                      }
                    }
                    setState(() {
                      if (hit == null) {
                        selected = null;
                      } else {
                        session.preview(render.SelectIntent(hit.id));
                      }
                    });
                  },
                  onPanStart: (_) => ignoreCurrentDrag = false,
                  onPanUpdate: (d) {
                    if (selected == null || globe || ignoreCurrentDrag) return;
                    final i = objects.indexWhere((o) => o.id == selected);
                    if (i < 0) return;
                    setState(() {
                      session.preview(
                        render.MoveIntent(
                          selected!,
                          (objects[i].x + d.delta.dx / bounds.maxWidth).clamp(
                            0,
                            1,
                          ),
                          (objects[i].y + d.delta.dy / bounds.maxHeight).clamp(
                            0,
                            1,
                          ),
                          0,
                        ),
                      );
                      status = 'معاينة الحركة، لم تُحفظ بعد';
                    });
                  },
                  onPanCancel: () => setState(() {
                    session.cancelPreview();
                    status = 'أُلغيت الحركة، المحفوظ لم يتغير';
                  }),
                  onPanEnd: (_) {
                    if (globe) return;
                    try {
                      session.commitPreview();
                      setState(() => status = 'محفوظ محليًا');
                    } catch (_) {
                      setState(() => status = 'فشل الحفظ، لم يُعتمد التغيير');
                    }
                  },
                  child: CustomPaint(
                    painter: ScenePainter(objects, selected, globe),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'تصغير العنصر المحدد',
              onPressed: selected == null || globe || session.hasPreview
                  ? null
                  : () => resizeSelected(1 / 1.2),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            IconButton(
              tooltip: 'تعديل اسم العنصر',
              onPressed: selected == null || globe || session.hasPreview
                  ? null
                  : renameSelected,
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<Offset>(
              tooltip: 'تحريك العنصر دون سحب',
              enabled: selected != null && !globe && !session.hasPreview,
              onSelected: nudgeSelected,
              icon: const Icon(Icons.open_with),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: Offset(0, -.02),
                  child: Text('تحريك لأعلى'),
                ),
                PopupMenuItem(
                  value: Offset(0, .02),
                  child: Text('تحريك لأسفل'),
                ),
                PopupMenuItem(
                  value: Offset(-.02, 0),
                  child: Text('تحريك لليسار'),
                ),
                PopupMenuItem(
                  value: Offset(.02, 0),
                  child: Text('تحريك لليمين'),
                ),
              ],
            ),
            IconButton(
              key: const Key('star-closeup'),
              tooltip: 'تقريب عرض النجم دون تغيير حجمه',
              onPressed:
                  globe ||
                      session.hasPreview ||
                      !objects.any((o) => o.id == selected && o.kind == 'star')
                  ? null
                  : () {
                      final star = objects.firstWhere((o) => o.id == selected);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StarCloseup(name: star.name),
                        ),
                      );
                    },
              icon: const Icon(Icons.zoom_in),
            ),
            const Text('حجم العنصر'),
            IconButton(
              tooltip: 'تكبير العنصر المحدد',
              onPressed: selected == null || globe || session.hasPreview
                  ? null
                  : () => resizeSelected(1.2),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '$status • ${objects.length} أجرام\nاسحب من الأدوات للإضافة، ثم اضغط جرمًا واسحبه لتحريكه',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}

class ScenePainter extends CustomPainter {
  final List<SpaceObject> objects;
  final String? selected;
  final bool globe;
  final bool drawBackground, showLabels;
  ScenePainter(
    this.objects,
    this.selected,
    this.globe, {
    this.drawBackground = true,
    this.showLabels = true,
  });
  @override
  void paint(Canvas canvas, Size s) {
    if (drawBackground) {
      canvas.drawRect(
        Offset.zero & s,
        Paint()..color = const Color(0xff050812),
      );
      // Deterministic decorative background, not selectable astronomical objects.
      final sky = math.Random(1701);
      for (var i = 0; i < 160; i++) {
        final point = Offset(
          sky.nextDouble() * s.width,
          sky.nextDouble() * s.height,
        );
        final alpha = .15 + sky.nextDouble() * .55;
        canvas.drawCircle(
          point,
          .35 + sky.nextDouble() * .65,
          Paint()..color = const Color(0xffdce7ff).withValues(alpha: alpha),
        );
      }
    }
    final p = Paint()..strokeWidth = 1;
    if (globe) {
      final center = Offset(s.width / 2, s.height / 2),
          r = math.min(s.width, s.height) * .32;
      final rect = Rect.fromCircle(center: center, radius: r);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xff649ca0), Color(0xff152c47)],
            center: Alignment(-.5, -.5),
          ).createShader(rect),
      );
      canvas.save();
      canvas.clipPath(Path()..addOval(rect));
      p
        ..color = Colors.white24
        ..style = PaintingStyle.stroke;
      for (int i = -2; i <= 2; i++) {
        canvas.drawOval(
          Rect.fromCenter(
            center: center + Offset(0, i * r * .3),
            width: 2 * math.sqrt(r * r - i * i * r * r * .09),
            height: r * .22,
          ),
          p,
        );
      }
      for (int i = 1; i <= 3; i++) {
        canvas.drawOval(
          Rect.fromCenter(center: center, width: r * i * .5, height: r * 2),
          p,
        );
      }
      canvas.restore();
      return;
    }
    for (final o in objects) {
      final c = Offset(o.x * s.width, o.y * s.height),
          r = o.radius * math.min(s.width, s.height);
      if (o.kind == 'star') {
        _paintStar(canvas, c, r);
      } else if (o.kind == 'moon' || o.kind == 'rock') {
        _paintRock(canvas, c, r, o.id, o.kind == 'moon');
      } else {
        SpaceObject? light;
        var nearest = double.infinity;
        for (final candidate in objects) {
          if (candidate.kind != 'star') continue;
          final distance =
              (Offset(candidate.x * s.width, candidate.y * s.height) - c)
                  .distanceSquared;
          if (distance < nearest) {
            nearest = distance;
            light = candidate;
          }
        }
        final direction = light == null
            ? const Offset(-.7, -.5)
            : Offset(light.x * s.width, light.y * s.height) - c;
        _paintPlanet(canvas, c, r, direction, o.id);
      }
      if (o.id == selected) {
        canvas.drawRect(
          Rect.fromCircle(center: c, radius: r + 5),
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke,
        );
      }
    }
    if (!showLabels) return;
    final bodyRects = [
      for (final o in objects)
        Rect.fromCircle(
          center: Offset(o.x * s.width, o.y * s.height),
          radius: o.radius * math.min(s.width, s.height) + 3,
        ),
    ];
    final occupied = <Rect>[];
    for (var i = 0; i < objects.length; i++) {
      final o = objects[i];
      final t = TextPainter(
        text: TextSpan(
          text: o.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontFamily: 'Cairo',
          ),
        ),
        textDirection: TextDirection.rtl,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.min(160, math.max(1, s.width - 12)));
      final c = Offset(o.x * s.width, o.y * s.height);
      final rect = placeSceneLabel(
        c,
        bodyRects[i],
        Size(t.width + 8, t.height + 2),
        s,
        [...bodyRects, ...occupied],
      );
      if (rect == null) {
        continue; // Dense scenes prefer no label to unreadable overlap.
      }
      occupied.add(rect.inflate(3));
      if (!bodyRects[i].inflate(14).overlaps(rect)) {
        canvas.drawLine(
          c,
          rect.center,
          Paint()
            ..color = Colors.white38
            ..strokeWidth = 1,
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = const Color(0xcc050812),
      );
      t.paint(canvas, rect.topLeft + const Offset(4, 1));
    }
  }

  void _paintRock(Canvas canvas, Offset c, double r, String id, bool moon) {
    final rng = math.Random(
      id.runes.fold<int>(17, (a, b) => (a * 31 + b) & 0x7fffffff),
    );
    final path = Path();
    for (var i = 0; i <= 16; i++) {
      final angle = i / 16 * math.pi * 2;
      final radius = moon ? r : r * (.72 + rng.nextDouble() * .28);
      final p = c + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.5, -.5),
          radius: 1.2,
          colors: moon
              ? const [Color(0xffd2d0c8), Color(0xff4b4b51)]
              : const [Color(0xffa38f7a), Color(0xff393532)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    for (var i = 0; i < 9; i++) {
      final p =
          c +
          Offset(rng.nextDouble() * 1.6 - .8, rng.nextDouble() * 1.6 - .8) * r;
      canvas.drawCircle(
        p,
        r * (.08 + rng.nextDouble() * .12),
        Paint()..color = const Color(0x60403b38),
      );
    }
    canvas.restore();
  }

  void _paintStar(Canvas canvas, Offset c, double r) {
    paintSolarStar(canvas, c, r);
  }

  void _paintPlanet(
    Canvas canvas,
    Offset c,
    double r,
    Offset light,
    String id,
  ) {
    if (r <= 0) return;
    final rect = Rect.fromCircle(center: c, radius: r);
    final length = light.distance;
    final direction = length < .001 ? const Offset(-.7, -.5) : light / length;
    canvas.drawCircle(
      c,
      r * 1.09,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Color(0x006ab7f4),
            Color(0x006ab7f4),
            Color(0x786ab7f4),
            Color(0x006ab7f4),
          ],
          stops: [0, .82, .93, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r * 1.09)),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    canvas.drawCircle(c, r, Paint()..color = const Color(0xff286b95));
    // Seeded procedural surface: illustrative land/clouds, no external assets.
    final seed = id.runes.fold<int>(19, (v, n) => (v * 31 + n) & 0x7fffffff);
    final random = math.Random(seed);
    for (var i = 0; i < 7; i++) {
      final center =
          c +
          Offset(
            (random.nextDouble() * 1.8 - .9) * r,
            (random.nextDouble() * 1.8 - .9) * r,
          );
      final size = r * (.16 + random.nextDouble() * .32);
      final land = Path();
      for (var k = 0; k <= 18; k++) {
        final angle = k / 18 * math.pi * 2;
        final radius = size * (.55 + random.nextDouble() * .45);
        final point =
            center +
            Offset(math.cos(angle) * radius, math.sin(angle) * radius * .7);
        if (k == 0) {
          land.moveTo(point.dx, point.dy);
        } else {
          land.lineTo(point.dx, point.dy);
        }
      }
      land.close();
      canvas.drawPath(
        land,
        Paint()
          ..color = i.isEven
              ? const Color(0xff618561)
              : const Color(0xff968963),
      );
    }
    for (var i = 0; i < 5; i++) {
      final cloud = Path();
      final y = c.dy + (random.nextDouble() * 1.6 - .8) * r;
      cloud.moveTo(c.dx - r, y);
      cloud.cubicTo(
        c.dx - r * .3,
        y - r * .25,
        c.dx + r * .3,
        y + r * .3,
        c.dx + r,
        y - r * .05,
      );
      canvas.drawPath(
        cloud,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * .06
          ..color = const Color(0x99e5eff2),
      );
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(direction.dx * .65, direction.dy * .65),
          radius: 1.05,
          colors: const [
            Color(0x20fff2bd),
            Color(0x20000819),
            Color(0xea00030b),
          ],
          stops: const [0, .45, 1],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ScenePainter old) => true;
}

// Screen-only label layout. Never changes body coordinates or saved data.
Rect? placeSceneLabel(
  Offset center,
  Rect body,
  Size label,
  Size viewport,
  List<Rect> occupied,
) {
  if (label.width > viewport.width - 4 || label.height > viewport.height - 4) {
    return null;
  }
  final candidates = <Offset>[
    Offset(center.dx - label.width / 2, body.bottom + 6),
    Offset(center.dx - label.width / 2, body.top - label.height - 6),
    Offset(body.right + 6, center.dy - label.height / 2),
    Offset(body.left - label.width - 6, center.dy - label.height / 2),
    for (var ring = 1; ring <= 6; ring++)
      for (final side in [-1.0, 1.0])
        Offset(
          center.dx - label.width / 2,
          center.dy +
              side * (body.height / 2 + ring * (label.height + 6)) -
              (side < 0 ? label.height : 0),
        ),
  ];
  for (final p in candidates) {
    final r = Rect.fromLTWH(
      p.dx.clamp(2, viewport.width - label.width - 2),
      p.dy.clamp(2, viewport.height - label.height - 2),
      label.width,
      label.height,
    );
    if (occupied.every((other) => !r.overlaps(other))) return r;
  }
  return null;
}

String bodyName(String kind) => switch (kind) {
  'star' => 'نجم',
  'planet' => 'كوكب',
  'moon' => 'قمر',
  'rock' => 'صخرة فضائية',
  _ => 'جرم',
};
IconData bodyIcon(String kind) => switch (kind) {
  'star' => Icons.star,
  'planet' => Icons.public,
  'moon' => Icons.nightlight_round,
  _ => Icons.hexagon_outlined,
};
