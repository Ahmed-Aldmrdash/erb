import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/util/format.dart';
import '../features/common/pdf_docs.dart';
import 'widgets.dart';

Future<void> openWhatsApp(BuildContext context, String? phone, String message) async {
  final p = waPhone(phone);
  final text = Uri.encodeComponent(message);
  final uri = Uri.parse(p == null ? 'https://wa.me/?text=$text' : 'https://wa.me/$p?text=$text');
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) toast(context, 'تعذر فتح واتساب', error: true);
}

Future<void> callPhone(BuildContext context, String? phone) async {
  final p = normalizeDigits(phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
  if (p.isEmpty) {
    toast(context, 'مفيش رقم تليفون', error: true);
    return;
  }
  final ok = await launchUrl(Uri(scheme: 'tel', path: p));
  if (!ok && context.mounted) toast(context, 'تعذر الاتصال', error: true);
}

/// Shows the PDF on screen first (the phone's own print preview), so it can
/// be read through before it goes to a printer or to a PDF file.
Future<void> printPdf(BuildContext context, Future<Uint8List> Function() build, String name) async {
  try {
    await Printing.layoutPdf(onLayout: (_) => build(), name: name);
  } catch (e) {
    if (context.mounted) toast(context, 'تعذر فتح المعاينة: $e', error: true);
  }
}

/// Builds a PDF with a progress dialog, then opens the share sheet.
Future<void> sharePdf(BuildContext context, Future<Uint8List> Function() build, String filename) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final bytes = await build();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await PdfDocs.share(bytes, filename);
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      toast(context, 'تعذر إنشاء الملف: $e', error: true);
    }
  }
}
