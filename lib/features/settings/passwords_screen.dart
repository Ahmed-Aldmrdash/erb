import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/util/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Change the username / password of the signed-in department. The manager
/// account can reset any department without its old password.
class PasswordsScreen extends StatelessWidget {
  const PasswordsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الحسابات وكلمات المرور')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: app.server!.departments(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const EmptyView(icon: Icons.wifi_off, text: 'محتاج إنترنت علشان تغير كلمات المرور');
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final deps = snap.data!;
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'لما كلمة المرور تتغير، كل الموبايلات التانية الداخلة على نفس القسم هتطلب تسجيل دخول تاني.',
                    style: TextStyle(color: AppColors.muted, height: 1.6),
                  ),
                ),
                TileGroup(children: [
                  for (final d in deps)
                    ListTile(
                      leading: const Icon(Icons.key_outlined),
                      title: Text(s(d['display_name'])),
                      subtitle: Text('اسم المستخدم: ${s(d['username'])}', textDirection: TextDirection.rtl),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _change(context, d),
                    ),
                ]),
              ],
            );
          },
        ),
      );

  Future<void> _change(BuildContext context, Map<String, dynamic> d) async {
    final user = TextEditingController(text: s(d['username']));
    final oldPass = TextEditingController();
    final newPass = TextEditingController();
    final newPass2 = TextEditingController();
    final form = GlobalKey<FormState>();
    final needsOld = !app.isManager;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text('حساب ${s(d['display_name'])}'),
          content: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextF(controller: user, label: 'اسم المستخدم', validator: requiredText, textDirection: TextDirection.ltr),
                  const Gap(),
                  if (needsOld) ...[
                    TextF(controller: oldPass, label: 'كلمة المرور الحالية', obscure: true, validator: requiredText, textDirection: TextDirection.ltr),
                    const Gap(),
                  ],
                  TextF(
                    controller: newPass,
                    label: 'كلمة المرور الجديدة',
                    obscure: true,
                    textDirection: TextDirection.ltr,
                    validator: (v) => (v == null || v.length < 6) ? '6 حروف أو أرقام على الأقل' : null,
                  ),
                  const Gap(),
                  TextF(
                    controller: newPass2,
                    label: 'تأكيد كلمة المرور',
                    obscure: true,
                    textDirection: TextDirection.ltr,
                    validator: (v) => v != newPass.text ? 'مش زي كلمة المرور' : null,
                  ),
                  if (error != null) ...[
                    const Gap(),
                    Text(error!, style: const TextStyle(color: AppColors.bad)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                final err = await app.changePassword(
                  department: s(d['id']),
                  oldPassword: needsOld ? oldPass.text : null,
                  newPassword: newPass.text,
                  newUsername: user.text.trim() == s(d['username']) ? null : user.text.trim(),
                );
                if (err != null) {
                  setState(() => error = err);
                  return;
                }
                if (c.mounted) Navigator.pop(c);
                if (context.mounted) {
                  toast(context, 'تم تغيير بيانات الدخول');
                  Navigator.pop(context);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
