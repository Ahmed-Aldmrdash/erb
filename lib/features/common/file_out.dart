import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_state.dart';
import '../../core/platform.dart';
import '../../core/util/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

const excelMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const backupMime = 'application/json';
const excelGreen = Color(0xFF1D6F42);

const _files = MethodChannel('damardash/files');

/// Where a file Claude writes for the user lives until it is saved or sent.
/// Not the cache: a phone short of space empties it, even while the "save as"
/// screen is open.
Future<Directory> _outDir(String name) async {
  final dir = Directory(p.join((await getApplicationSupportDirectory()).path, name));
  if (dir.existsSync()) {
    for (final old in dir.listSync().whereType<File>()) {
      if (DateTime.now().difference(old.lastModifiedSync()).inMinutes > 30) old.deleteSync();
    }
  } else {
    dir.createSync(recursive: true);
  }
  return dir;
}

/// Builds a file (with a waiting circle), then lets the user keep it in the
/// phone's Downloads or send it out (WhatsApp, e-mail, Drive...).
Future<void> saveOrSendFile(
  BuildContext context, {
  required String title,
  required String extension,
  required String mime,
  required Future<List<int>> Function() build,

  /// Read after [build], e.g. "عدد الصفحات: 11 • عدد السطور: 81".
  String Function()? details,
  IconData icon = Icons.description_outlined,
  Color color = excelGreen,
  String saveLabel = 'احفظه في التنزيلات على الموبايل',
  String sendLabel = 'ابعته (واتساب، إيميل، درايف...)',
}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  final File file;
  try {
    final bytes = await build();
    final dir = await _outDir('out');
    final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
    file = File(p.join(dir.path, '$safe ${todayStr()}.$extension'));
    await file.writeAsBytes(bytes, flush: true);
  } catch (e) {
    nav.pop();
    debugPrint('file out: $e');
    if (context.mounted) toast(context, 'تعذر تجهيز الملف: $e', error: true);
    return;
  }
  nav.pop();
  if (!context.mounted) return;

  final name = p.basename(file.path);
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Not the file name: Arabic, a date and ".xlsx" come
                      // out scrambled right to left.
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      if (details != null) Text(details(), style: const TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(52)),
              onPressed: () => Navigator.pop(c, 'save'),
              icon: const Icon(Icons.download_rounded),
              label: Text(isMobile ? saveLabel : 'احفظه في فولدر التنزيلات'),
            ),
            const SizedBox(height: 10),
            if (isMobile)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => Navigator.pop(c, 'share'),
                icon: const Icon(Icons.share_outlined),
                label: Text(sendLabel),
              ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  try {
    if (choice == 'save') {
      final saved = isMobile
          ? await _files.invokeMapMethod<String, Object?>(
              'saveToDownloads',
              {'path': file.path, 'name': name, 'mime': mime},
            )
          : await _saveOnComputer(file, name);
      if (saved == null || !context.mounted) return;
      final m = ScaffoldMessenger.of(context);
      m.hideCurrentSnackBar();
      m.showSnackBar(SnackBar(
        content: Text(saved['downloads'] == true ? 'اتحفظ "$title" في فولدر التنزيلات (Download)' : 'اتحفظ "$title"'),
        duration: const Duration(seconds: 8),
        // With an action it would otherwise stay until swiped away.
        persist: false,
        action: SnackBarAction(label: 'افتحه', onPressed: () => openSavedFile(context, s(saved['uri']), mime)),
      ));
    } else if (choice == 'share') {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: mime)],
        title: title,
        subject: '$title - ${app.companyName}',
      ));
    }
  } catch (e) {
    debugPrint('file out: $e');
    if (context.mounted) {
      toast(
        context,
        choice == 'save' ? 'تعذر حفظ الملف. جرّب تاني، أو اختار "ابعته" بدل الحفظ.' : 'تعذر إرسال الملف. جرّب تاني.',
        error: true,
      );
    }
  }
}

/// Puts the file in the Downloads folder of the laptop and hands back the
/// same answer the phone gives, so the screen above does not care which one
/// it is talking to.
Future<Map<String, Object?>?> _saveOnComputer(File file, String name) async {
  final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  var out = File(p.join(dir.path, name));
  // Never write over a file that is already there.
  if (out.existsSync()) {
    final base = p.basenameWithoutExtension(name), ext = p.extension(name);
    for (var i = 2; out.existsSync() && i < 100; i++) {
      out = File(p.join(dir.path, '$base ($i)$ext'));
    }
  }
  await file.copy(out.path);
  return {'downloads': true, 'uri': out.path};
}

Future<void> openSavedFile(BuildContext context, String uri, String mime) async {
  if (!isMobile) {
    final ok = await launchUrl(Uri.file(uri));
    if (!ok && context.mounted) toast(context, 'مش عارف يفتح الملف. هتلاقيه في فولدر التنزيلات.', error: true);
    return;
  }
  final ok = await _files.invokeMethod<bool>('open', {'uri': uri, 'mime': mime}) ?? false;
  if (!ok && context.mounted) {
    toast(
      context,
      mime == excelMime
          ? 'مفيش برنامج على الموبايل بيفتح ملفات Excel. نزّل Microsoft Excel أو Google Sheets.'
          : 'مفيش برنامج على الموبايل بيفتح الملف ده.',
      error: true,
    );
  }
}

/// Lets the user pick a file from the phone. Returns a copy of it inside the
/// app, or null when nothing was picked.
Future<String?> pickFileFromPhone({String mime = '*/*'}) async {
  final dir = await _outDir('in');
  if (isMobile) {
    return _files.invokeMethod<String>('pickFile', {'mime': mime, 'dir': dir.path});
  }
  // On the laptop the usual "open file" window.
  final picked = await fs.openFile(
    acceptedTypeGroups: [
      if (mime == backupMime) const fs.XTypeGroup(label: 'نسخة احتياطية', extensions: ['json']),
    ],
  );
  if (picked == null) return null;
  final copy = File(p.join(dir.path, p.basename(picked.path)));
  await copy.writeAsBytes(await picked.readAsBytes(), flush: true);
  return copy.path;
}
