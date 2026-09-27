import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/schema.dart';
import '../../core/sync/sync_service.dart';
import '../../core/util/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common/person_chip.dart';
import 'passwords_screen.dart';

/// Cloud icon showing the sync state; opens the account screen.
class SyncButton extends StatelessWidget {
  const SyncButton({super.key, this.light = false});

  final bool light;

  @override
  Widget build(BuildContext context) {
    final sync = app.sync;
    if (!app.isCloud || sync == null) {
      return IconButton(
        tooltip: 'بدون سيرفر',
        onPressed: () => push(context, const AccountScreen()),
        icon: Icon(Icons.cloud_off_outlined, color: light ? Colors.white70 : AppColors.muted),
      );
    }
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final (icon, color) = switch (sync.phase) {
          SyncPhase.running => (Icons.sync, light ? Colors.white : AppColors.primary),
          SyncPhase.offline => (Icons.cloud_off, AppColors.warn),
          SyncPhase.error => (Icons.sync_problem, light ? Colors.orangeAccent : AppColors.bad),
          SyncPhase.idle => sync.pending > 0
              ? (Icons.cloud_upload_outlined, AppColors.warn)
              : (Icons.cloud_done_outlined, light ? Colors.white : AppColors.good),
        };
        return IconButton(
          tooltip: 'المزامنة',
          onPressed: () => push(context, const AccountScreen()),
          icon: Badge(
            isLabelVisible: sync.pending > 0,
            label: Text('${sync.pending}'),
            child: Icon(icon, color: color),
          ),
        );
      },
    );
  }
}

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الحساب والمزامنة')),
        body: ListenableBuilder(
          listenable: app,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Box(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        LetterAvatar(app.person, radius: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(app.person.isEmpty ? '—' : app.person,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                              Text('داخل على: ${app.departmentName}', style: const TextStyle(color: AppColors.muted)),
                            ],
                          ),
                        ),
                        TextButton(onPressed: () => askPerson(context), child: const Text('تغيير الاسم')),
                      ],
                    ),
                    const Divider(height: 24),
                    InfoRow('القسم المفتوح', app.divisionName, bold: true),
                    if (app.isCloud) InfoRow('اسم المستخدم', app.prefs.get('username')),
                    if (app.db.deviceCode.isNotEmpty) InfoRow('رقم الموبايل', app.db.deviceCode),
                  ],
                ),
              ),
              if (app.isManager) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => app.switchDivision(app.isCrops ? Division.appliances : Division.crops),
                  icon: const Icon(Icons.swap_horiz),
                  label: Text('افتح ${Division.names[app.isCrops ? Division.appliances : Division.crops]}'),
                ),
              ],
              const SizedBox(height: 12),
              if (app.isCloud) _syncBox(context) else _localBox(context),
              const SizedBox(height: 12),
              _wipeBox(context),
              const SizedBox(height: 12),
              if (app.isCloud) ...[
                OutlinedButton.icon(
                  onPressed: () => push(context, const PasswordsScreen()),
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('تغيير اسم المستخدم / كلمة المرور'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.bad),
                  onPressed: () async {
                    final pending = await app.db.pendingCount();
                    if (!context.mounted) return;
                    final ok = await confirmDialog(
                      context,
                      title: 'تسجيل خروج',
                      message: pending > 0
                          ? 'في $pending تغيير لسه ما اترفعش. هيتحاول يترفع دلوقتي، ولو مفيش نت هيفضل على الموبايل لحد ما حد يدخل تاني. متأكد؟'
                          : 'متأكد إنك عايز تسجل خروج؟',
                      ok: 'خروج',
                      danger: true,
                    );
                    if (ok) await app.logout();
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('تسجيل خروج'),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _syncBox(BuildContext context) {
    final sync = app.sync;
    if (sync == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final status = switch (sync.phase) {
          SyncPhase.running => ('جاري المزامنة...', AppColors.primary),
          SyncPhase.offline => (
              'الموبايل مش قادر يوصل للسيرفر دلوقتي. كل حاجة محفوظة على الموبايل وهتترفع أول ما النت يرجع.',
              AppColors.warn
            ),
          SyncPhase.error => ('حصلت مشكلة: ${sync.error ?? ''}', AppColors.bad),
          SyncPhase.idle => sync.pending > 0
              ? ('في تغييرات لسه ما اترفعتش', AppColors.warn)
              : ('كل البيانات متزامنة', AppColors.good),
        };
        return Box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(status.$1, style: TextStyle(color: status.$2, fontWeight: FontWeight.w700, height: 1.5)),
              const SizedBox(height: 8),
              InfoRow('آخر مزامنة', sync.lastSync == null ? '—' : timeAgo(sync.lastSync!)),
              InfoRow('تغييرات مستنية الرفع', '${sync.pending}'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: sync.phase == SyncPhase.running ? null : sync.syncNow,
                icon: const Icon(Icons.sync),
                label: const Text('مزامنة الآن'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Deletes everything this phone keeps (both divisions).
  Widget _wipeBox(BuildContext context) => Box(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('مسح البيانات', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.bad)),
            const SizedBox(height: 6),
            Text(
              app.isCloud
                  ? 'بيمسح كل البيانات اللي على الموبايل ده (المعرض والتجارة)، وبعدها بينزل تاني اللي على السيرفر.'
                  : 'بيمسح كل البيانات اللي على الموبايل ده (المعرض والتجارة) وتبدأ على نضيف.',
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.bad),
              onPressed: () => _confirmWipe(context),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('مسح كل البيانات من الموبايل ده'),
            ),
          ],
        ),
      );

  Future<void> _confirmWipe(BuildContext context) async {
    final pending = app.sync?.pending ?? 0;
    final word = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('مسح كل البيانات'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'كل العملاء والفواتير والمحاصيل والفلوس والتذكرة اللي على الموبايل ده هتتمسح ومش هترجع.',
                style: TextStyle(height: 1.5),
              ),
              if (app.isCloud) ...[
                const SizedBox(height: 8),
                Text('أنت مربوط بالسيرفر، السيستم هيمسح القديم وينزل البيانات تاني من السيرفر فوراً.',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ],
              if (pending > 0) ...[
                const SizedBox(height: 8),
                Text('فيه $pending تغيير لسه ما اترفعش على السيرفر وهيضيع.',
                    style: const TextStyle(color: AppColors.bad, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 12),
              const Text('علشان تأكد اكتب كلمة: امسح'),
              const SizedBox(height: 6),
              TextField(controller: word, autofocus: true, onChanged: (_) => setD(() {})),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.bad),
              onPressed: word.text.trim() == 'امسح' ? () => Navigator.pop(c, true) : null,
              child: const Text('مسح'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await app.wipeThisPhone();
  }

  Widget _localBox(BuildContext context) => Box(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('شغال بدون سيرفر', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.warn)),
            const SizedBox(height: 6),
            const Text(
              'البيانات على الموبايل ده بس. اربطه بالسيرفر علشان تشتغلوا على كذا موبايل وتبقى البيانات في أمان.',
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: app.changeServer,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('ربط بالسيرفر'),
            ),

          ],
        ),
      );
}
