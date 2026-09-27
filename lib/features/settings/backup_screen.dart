import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/util/format.dart';
import '../../data/backup.dart';
import '../../core/db/schema.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common/file_out.dart';

/// نسخة احتياطية: keeps a copy of everything this division has in one file,
/// and puts a copy back when a phone is lost or something is deleted by
/// mistake.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  Future<void> _create() async {
    await saveOrSendFile(
      context,
      title: 'نسخة احتياطية ${app.divisionName}',
      extension: 'json',
      mime: backupMime,
      icon: Icons.shield_outlined,
      color: AppColors.primary,
      details: () => 'كل بيانات ${app.divisionName} لحد النهارده',
      build: () async => utf8.encode(await Backup.create(app.db, company: app.companyName)),
    );
    if (mounted) {
      await app.prefs.set('last_backup', todayStr());
      setState(() {});
    }
  }

  Future<void> _restore() async {
    final path = await pickFileFromPhone();
    if (path == null || !mounted) return;
    setState(() => _busy = true);
    BackupInfo info;
    try {
      info = Backup.read(await File(path).readAsString());
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) {
        toast(context, e is FormatException ? e.message : 'الملف مش مقروء: $e', error: true);
      }
      return;
    }
    setState(() => _busy = false);
    if (!mounted) return;
    if (info.division != app.division) {
      final other = Division.names[info.division] ?? info.division;
      toast(context, 'النسخة دي بتاعة $other. افتح $other الأول وبعدين استرجعها.', error: true);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'استرجاع النسخة',
      message: 'النسخة اتعملت ${showDate(info.createdAt.split('T').first)} وفيها:\n'
          '${info.highlights.entries.map((e) => '• ${e.value} ${e.key}').join('\n')}\n\n'
          'اللي في النسخة هيرجع مكان اللي على الموبايل، واللي اتسجل بعدها ومش موجود فيها هيفضل زي ما هو. '
          'وكل ده هيترفع على السيرفر.',
      ok: 'استرجاع',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final rows = await Backup.restore(app.db, info);
      await app.reloadSettings();
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'رجّعنا $rows سطر من النسخة');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'تعذر الاسترجاع: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = app.prefs.get('last_backup');
    return Scaffold(
      appBar: AppBar(title: const Text('نسخة احتياطية')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Box(
            color: AppColors.primarySoft,
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: AppColors.primary, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    last.isEmpty
                        ? 'لسه ماعملتش نسخة احتياطية من الموبايل ده.'
                        : 'آخر نسخة اتعملت من الموبايل ده: ${showDate(last)}',
                    style: const TextStyle(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const Gap(16),
          const Text(
            'النسخة ملف واحد فيه كل بيانات القسم المفتوح: الأصناف والحسابات والفواتير والأقساط '
            'وحركات الفلوس والمخزن والتذكرة. احفظه على الموبايل أو ابعته لنفسك على واتساب أو درايف، '
            'وخليك عامل نسخة كل شوية.',
            style: TextStyle(color: AppColors.muted, height: 1.6),
          ),
          const Gap(16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.save_outlined),
            label: Text('اعمل نسخة من ${app.divisionName} دلوقتي'),
          ),
          const Gap(24),
          const Text('استرجاع', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const Gap(6),
          const Text(
            'لو ضاع موبايل أو اتمسح حاجة بالغلط، اختار ملف النسخة ورجّعها. اللي في النسخة بيرجع '
            'مكان اللي على الموبايل، واللي اتسجل بعد النسخة بيفضل زي ما هو.',
            style: TextStyle(color: AppColors.muted, height: 1.6),
          ),
          const Gap(12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.restore_outlined),
            label: const Text('استرجع نسخة من ملف'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
