import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'forge_store.dart';
import 'motion_preview.dart';
import 'motion_lab.dart';

/// Disposable draft from an immutable copy. No database/session handle.
class OrbitDraft extends StatefulWidget {
  final List<SpaceObject> objects;
  OrbitDraft({super.key, required Iterable<SpaceObject> objects})
    : objects = List.unmodifiable(objects);
  @override
  State<OrbitDraft> createState() => _OrbitDraftState();
}

class _OrbitDraftState extends State<OrbitDraft> {
  final selected = <String>{};
  String? centerId;
  String? error;
  void preview() {
    try {
      if (centerId == null || selected.isEmpty) throw ArgumentError();
      final center = widget.objects.firstWhere((o) => o.id == centerId);
      final chosen = widget.objects
          .where((o) => selected.contains(o.id))
          .toList();
      final groups = <MotionGroup>[];
      for (final o in chosen) {
        final dx = o.x - center.x, dy = o.y - center.y;
        final radius = math.sqrt(dx * dx + dy * dy);
        if (radius <= 1e-9) throw ArgumentError();
        groups.add(
          MotionGroup(
            id: 'draft-${o.id}',
            center: MotionPoint(center.x - .5, center.y - .5),
            period: 24,
            tracks: [CircularTrack(o.id, radius, math.atan2(dy, dx))],
          ),
        );
      }
      final model = MotionPreview({
        for (final o in widget.objects) o.id: MotionPoint(o.x - .5, o.y - .5),
      }, groups);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              MotionLab(draftModel: model, draftObjects: widget.objects),
        ),
      );
    } catch (_) {
      setState(
        () => error = 'اختر أجسامًا ومركزًا مختلف الموضع. لا يمكن إنشاء مسار بنصف قطر صفر.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        key: const Key('close-orbit-draft'),
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back),
      ),
      title: const Text('تجربة مدار من أجسامك'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'مسودة مؤقتة فقط، لا يوجد زر حفظ. اختر الأجسام بنفسك. كل المسارات التوضيحية مدتها 24 ثانية في هذه التجربة فقط.',
        ),
        DropdownButtonFormField<String>(
          key: const Key('draft-center'),
          initialValue: centerId,
          decoration: const InputDecoration(
            labelText: 'اختر موضع جسم كنقطة مركز ثابتة',
          ),
          items: [
            for (final o in widget.objects)
              DropdownMenuItem(
                value: o.id,
                child: Text(
                  '${o.name} (${o.id})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) => setState(() {
            centerId = id;
            selected.remove(id);
            error = null;
          }),
        ),
        const Text(
          'المركز نقطة من موضع الجسم الأصلي، لا يتبع حركته. باقي الأجسام غير المختارة تبقى ثابتة.',
        ),
        for (final o in widget.objects)
          CheckboxListTile(
            key: Key('draft-body-${o.id}'),
            title: Text(o.name),
            subtitle: Text(o.kind),
            value: selected.contains(o.id),
            onChanged: o.id == centerId
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      selected.add(o.id);
                    } else {
                      selected.remove(o.id);
                    }
                    error = null;
                  }),
          ),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.orange)),
        FilledButton(
          key: const Key('draft-preview'),
          onPressed: centerId != null && selected.isNotEmpty ? preview : null,
          child: const Text('معاينة بدون حفظ'),
        ),
        const Text(
          'العودة للمحرر تتخلص من المسودة. هذه ليست ميزة مدارات محفوظة أو محاكاة جاذبية.',
        ),
      ],
    ),
  );
}
