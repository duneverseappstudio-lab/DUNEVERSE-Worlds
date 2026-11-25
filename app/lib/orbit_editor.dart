import 'package:material_ui/material_ui.dart';

import 'authored_orbit.dart';
import 'forge_store.dart';
import 'motion_lab.dart';
import 'orbit_history.dart';

class OrbitEditor extends StatefulWidget {
  final ForgeStore store;
  final String worldId;
  const OrbitEditor({super.key, required this.store, required this.worldId});
  @override
  State<OrbitEditor> createState() => _OrbitEditorState();
}

class _OrbitEditorState extends State<OrbitEditor> {
  String? bodyId, centerId, error;
  double seconds = 24;
  bool clockwise = false;
  AuthoredOrbit? base;
  late final OrbitHistory history;
  @override
  void initState() {
    super.initState();
    history = OrbitHistory(widget.store, widget.worldId);
  }

  void refreshSelection() {
    base = bodyId == null ? null : history.current(bodyId!);
    centerId = base?.centerId;
    seconds = base?.seconds ?? 24;
    clockwise = base?.clockwise ?? false;
  }

  void replay(bool redo) {
    try {
      if (redo) {
        history.redo();
      } else {
        history.undo();
      }
      setState(() {
        refreshSelection();
        error = null;
      });
    } catch (_) {
      setState(() {
        refreshSelection();
        error = 'تعذر التراجع أو الإعادة. عُرضت أحدث القيم ولم تُستبدل. راجع المدار، أو أعد فتح الصفحة لبدء سجل جديد.';
      });
    }
  }

  void save() {
    try {
      history.change(
        bodyId!,
        AuthoredOrbit(bodyId!, centerId!, seconds, clockwise),
        expected: base,
      );
      setState(() {
        refreshSelection();
        error = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم حفظ المدار محليًا')));
    } catch (_) {
      setState(() {
        refreshSelection();
        error = 'تعذر الحفظ. عُرضت أحدث القيم للمراجعة. اختر مركزًا مختلفًا، بدون دورة اعتماد أو موضع مطابق.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final objects = widget.store.objects(widget.worldId),
        orbits = widget.store.orbits(widget.worldId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدارات العالم'),
        actions: [
          IconButton(
            key: const Key('orbit-undo'),
            tooltip: 'تراجع عن تعديل المدار',
            onPressed: history.canUndo ? () => replay(false) : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            key: const Key('orbit-redo'),
            tooltip: 'إعادة تعديل المدار',
            onPressed: history.canRedo ? () => replay(true) : null,
            icon: const Icon(Icons.redo),
          ),
        ],
        leading: IconButton(
          key: const Key('close-saved-orbits'),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'مسارات دائرية تختارها أنت، بدون جاذبية. كل جسم له مدة دورة واتجاه مستقلان. موضع الجسم يحدد نصف القطر ونقطة البداية. القمر يمكنه الدوران حول كوكب متحرك.',
          ),
          DropdownButtonFormField<String>(
            key: const Key('orbit-body'),
            initialValue: bodyId,
            decoration: const InputDecoration(labelText: 'الجسم المتحرك'),
            items: [
              for (final o in objects)
                DropdownMenuItem(value: o.id, child: Text(o.name)),
            ],
            onChanged: (id) {
              final found = orbits.where((o) => o.bodyId == id);
              setState(() {
                bodyId = id;
                base = found.isEmpty ? null : found.first;
                centerId = found.isEmpty ? null : found.first.centerId;
                seconds = found.isEmpty ? 24 : found.first.seconds;
                clockwise = found.isEmpty ? false : found.first.clockwise;
                error = null;
              });
            },
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('orbit-center-$bodyId-$centerId'),
            initialValue: centerId,
            decoration: const InputDecoration(
              labelText: 'مركز المدار، يتبع حركته',
            ),
            items: [
              for (final o in objects.where((o) => o.id != bodyId))
                DropdownMenuItem(value: o.id, child: Text(o.name)),
            ],
            onChanged: (id) => setState(() => centerId = id),
          ),
          const SizedBox(height: 12),
          Text(
            'مدة الدورة: ${seconds.toStringAsFixed(0)} ثانية. مدة أقل تعني سرعة أكبر.',
          ),
          Slider(
            key: const Key('orbit-seconds'),
            value: seconds,
            min: 1,
            max: 3600,
            label: '${seconds.round()} ث',
            onChanged: (v) => setState(() => seconds = v.roundToDouble()),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final n in [6, 12, 24, 60, 120])
                ActionChip(
                  label: Text('$n ث'),
                  onPressed: () => setState(() => seconds = n.toDouble()),
                ),
            ],
          ),
          SwitchListTile(
            key: const Key('orbit-direction'),
            title: const Text('عكس اتجاه الدوران'),
            value: clockwise,
            onChanged: (v) => setState(() => clockwise = v),
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.orange)),
          FilledButton(
            key: const Key('save-orbit'),
            onPressed: bodyId != null && centerId != null ? save : null,
            child: const Text('حفظ مدار هذا الجسم'),
          ),
          const SizedBox(height: 16),
          for (final orbit in orbits)
            ListTile(
              title: Text(
                '${objects.firstWhere((o) => o.id == orbit.bodyId).name} / ${objects.firstWhere((o) => o.id == orbit.centerId).name}',
              ),
              subtitle: Text('${orbit.seconds.round()} ثانية / دورة'),
              trailing: IconButton(
                key: Key('remove-orbit-${orbit.bodyId}'),
                tooltip: 'إزالة المدار فقط',
                onPressed: () {
                  try {
                    history.change(orbit.bodyId, null, expected: orbit);
                    setState(() {
                      refreshSelection();
                      error = null;
                    });
                  } catch (_) {
                    setState(() {
                      refreshSelection();
                      error = 'تعذرت إزالة المدار، أعد المحاولة بعد مراجعة التغييرات.';
                    });
                  }
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          OutlinedButton(
            key: const Key('play-saved-orbits'),
            onPressed: orbits.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => MotionLab(
                        draftModel: authoredMotion(objects, orbits),
                        draftObjects: objects,
                        saved: true,
                      ),
                    ),
                  ),
            child: const Text('تشغيل المدارات المحفوظة'),
          ),
          const Text(
            'التراجع والإعادة يشملان حفظ المدار وإزالته خلال هذه الزيارة فقط. مغادرة الصفحة تمسح سجل التراجع، ولا تمسح المدارات المحفوظة.',
          ),
          const Text(
            'تشغيل الحركة لا يغير إحداثيات البداية المحفوظة. التحريك في المحرر يغير شكل المدار عند التشغيل التالي. إزالة المدار لا تحذف الجسم.',
          ),
        ],
      ),
    );
  }
}
