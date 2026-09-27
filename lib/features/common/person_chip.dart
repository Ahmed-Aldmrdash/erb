import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../ui/widgets.dart';

/// "مين معايا؟": the name written on everything this phone records. Several
/// people can share one phone, so switching is one tap away.
class PersonChip extends StatelessWidget {
  const PersonChip({super.key, this.light = false});

  final bool light;

  @override
  Widget build(BuildContext context) {
    final name = app.person.isEmpty ? 'مين معايا؟' : app.person;
    if (!light) {
      return ActionChip(
        avatar: const Icon(Icons.person, size: 18),
        label: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => askPerson(context),
      );
    }
    // On the colored dashboard header.
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => askPerson(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Icon(Icons.swap_horiz, size: 16, color: Colors.white.withValues(alpha: 0.75)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> askPerson(BuildContext context) async {
  final ctrl = TextEditingController(text: app.person);
  final name = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('مين بيستخدم الموبايل دلوقتي؟'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('أي حاجة هتتسجل هتتكتب باسمه.', style: TextStyle(height: 1.5)),
          const SizedBox(height: 12),
          TextF(controller: ctrl, label: 'الاسم', icon: Icons.person_outline, autofocus: true),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in app.recentPersons) ActionChip(label: Text(r), onPressed: () => Navigator.pop(c, r)),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('تمام')),
      ],
    ),
  );
  if (name != null && name.trim().isNotEmpty) await app.setPerson(name);
}
