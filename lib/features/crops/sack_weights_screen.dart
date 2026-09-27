import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/util/format.dart';
import '../../data/calc.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Reads the numbers written on a notebook page photo (on the phone, no
/// internet needed). Clear, Western digits read best; the photo stays on
/// screen so the rest can be typed while looking at it.
Future<({String path, List<double> weights})?> readWeightsPhoto(ImageSource source) async {
  final file = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 2400);
  if (file == null) return null;
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(file.path));
    // A sack weighs a few kilos to a few hundred; years and page numbers go.
    final weights = parseWeights(result.text).where((w) => w >= 1 && w < 1000).toList();
    return (path: file.path, weights: weights);
  } catch (_) {
    return (path: file.path, weights: const <double>[]);
  } finally {
    await recognizer.close();
  }
}

/// وزن كل شكارة: typed one by one ("50", "49.5", or "10×50" for ten sacks of
/// 50), or read from a photo of the paper notebook.
class SackWeightsScreen extends StatefulWidget {
  const SackWeightsScreen({super.key, required this.initial, this.startWithPhoto = false});

  final List<double> initial;

  /// Open the camera right away.
  final bool startWithPhoto;

  @override
  State<SackWeightsScreen> createState() => _SackWeightsScreenState();
}

class _SackWeightsScreenState extends State<SackWeightsScreen> {
  late final List<double> _weights = [...widget.initial];
  final _input = TextEditingController();
  final _focus = FocusNode();
  String? _photo;
  bool _reading = false;

  double get _total => round3(_weights.fold<double>(0, (a, w) => a + w));

  @override
  void initState() {
    super.initState();
    if (widget.startWithPhoto) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fromPhoto(ImageSource.camera));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add() {
    final text = normalizeDigits(_input.text.trim()).replaceAll('*', '×').replaceAll('x', '×').replaceAll('X', '×');
    // "10×50": ten sacks of 50 kg.
    final times = RegExp(r'^(\d+)\s*×\s*(\d+(?:\.\d+)?)$').firstMatch(text);
    final List<double> add;
    if (times != null) {
      final count = int.parse(times.group(1)!);
      final w = double.parse(times.group(2)!);
      add = count > 0 && count <= 1000 && w > 0 ? List.filled(count, w) : const [];
    } else {
      add = parseWeights(_input.text);
    }
    if (add.isEmpty) return;
    setState(() => _weights.addAll(add));
    _input.clear();
    _focus.requestFocus();
  }

  /// Several sacks of the same weight at once.
  Future<void> _addSame() async {
    final count = TextEditingController();
    final weight = TextEditingController(text: _input.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('كذا شكارة بنفس الوزن'),
        content: Row(
          children: [
            Expanded(child: NumField(controller: count, label: 'عدد الشكاير', autofocus: true)),
            const SizedBox(width: 10),
            Expanded(child: NumField(controller: weight, label: 'وزن الواحدة', suffix: 'كجم')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ضيف')),
        ],
      ),
    );
    final n = parseNum(count.text).round(), w = parseNum(weight.text);
    if (ok != true || n <= 0 || n > 1000 || w <= 0) return;
    setState(() => _weights.addAll(List.filled(n, w)));
    _input.clear();
  }

  Future<void> _fromPhoto(ImageSource source) async {
    setState(() => _reading = true);
    final r = await readWeightsPhoto(source);
    if (!mounted) return;
    setState(() => _reading = false);
    if (r == null) return;
    setState(() => _photo = r.path);
    if (r.weights.isEmpty) {
      toast(context, 'مقدرناش نقرا أرقام واضحة من الصورة. اكتبها وانت شايف الصورة فوق.');
      return;
    }
    // Numbers far from the usual sack weight (dates, page numbers) start
    // unticked; a tap adds or removes any number.
    final sorted = [...r.weights]..sort();
    final median = sorted[sorted.length ~/ 2];
    final picked = [for (final w in r.weights) w >= median * 0.5 && w <= median * 1.5];
    final chosen = await showDialog<List<double>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          final list = [for (var i = 0; i < r.weights.length; i++) if (picked[i]) r.weights[i]];
          final total = list.fold<double>(0, (a, w) => a + w);
          return AlertDialog(
            title: Text('لقينا ${r.weights.length} رقم'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'المتعلّم عليهم ${list.length} شكارة = ${qty(total)} كجم. دوس على أي رقم علشان تشيله أو ترجّعه، وبعد ما يتضافوا راجعهم على الصورة.',
                    style: const TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < r.weights.length; i++)
                        FilterChip(
                          label: Text(qty(r.weights[i])),
                          selected: picked[i],
                          visualDensity: VisualDensity.compact,
                          onSelected: (v) => setD(() => picked[i] = v),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('هكتبهم بنفسي')),
              FilledButton(
                onPressed: list.isEmpty ? null : () => Navigator.pop(c, list),
                child: Text('ضيف ${list.length}'),
              ),
            ],
          );
        },
      ),
    );
    if (chosen != null) setState(() => _weights.addAll(chosen));
  }

  Future<void> _edit(int i) async {
    final ctrl = TextEditingController(text: numText(_weights[i]));
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('الشكارة رقم ${i + 1}'),
        content: NumField(controller: ctrl, label: 'الوزن', suffix: 'كجم', autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'delete'),
            child: const Text('حذف', style: TextStyle(color: AppColors.bad)),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('تمام')),
        ],
      ),
    );
    if (r == 'delete') setState(() => _weights.removeAt(i));
    if (r == 'save' && parseNum(ctrl.text) > 0) setState(() => _weights[i] = parseNum(ctrl.text));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('وزن الشكاير'),
          actions: [
            IconButton(
              tooltip: 'صوّر صفحة الدفتر',
              onPressed: _reading ? null : () => _fromPhoto(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
            ),
            IconButton(
              tooltip: 'صورة من المعرض',
              onPressed: _reading ? null : () => _fromPhoto(ImageSource.gallery),
              icon: const Icon(Icons.image_outlined),
            ),
            if (_weights.isNotEmpty)
              IconButton(
                tooltip: 'مسح الكل',
                onPressed: () async {
                  final ok = await confirmDialog(context, title: 'مسح الأوزان', message: 'تمسح كل الأوزان اللي اتكتبت؟', ok: 'مسح', danger: true);
                  if (ok) setState(() => _weights.clear());
                },
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
          ],
        ),
        body: Column(
          children: [
            if (_reading) const LinearProgressIndicator(),
            if (_photo != null)
              Stack(
                children: [
                  Container(
                    height: MediaQuery.sizeOf(context).height * 0.3,
                    color: Colors.black,
                    child: InteractiveViewer(
                      maxScale: 6,
                      child: Center(child: Image.file(File(_photo!))),
                    ),
                  ),
                  PositionedDirectional(
                    top: 6,
                    end: 6,
                    child: IconButton.filledTonal(
                      tooltip: 'إخفاء الصورة',
                      onPressed: () => setState(() => _photo = null),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            Container(
              color: AppColors.primarySoft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(child: _stat('عدد الشكاير', intf(_weights.length))),
                  Expanded(child: _stat('الإجمالي', '${qty(_total)} كجم')),
                  Expanded(child: _stat('المتوسط', _weights.isEmpty ? '-' : '${qty(_total / _weights.length)} كجم')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      autofocus: !widget.startWithPhoto,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _add(),
                      onEditingComplete: () {},
                      decoration: const InputDecoration(
                        labelText: 'وزن الشكارة',
                        hintText: 'مثلاً 50 أو 49.5',
                        suffixText: 'كجم',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _add, child: const Text('ضيف')),
                  IconButton(
                    tooltip: 'كذا شكارة بنفس الوزن',
                    onPressed: _addSame,
                    icon: const Icon(Icons.library_add_outlined),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                'اكتب الوزن ودوس ↵ وكمّل على اللي بعده. ممكن كذا وزن ورا بعض بمسافة. دوس على أي شكارة علشان تعدّلها أو تمسحها.',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            ),
            Expanded(
              child: _weights.isEmpty
                  ? const EmptyView(icon: Icons.scale_outlined, text: 'لسه مفيش أوزان')
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 92,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.35,
                      ),
                      itemCount: _weights.length,
                      itemBuilder: (context, i) => Material(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _edit(i),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${i + 1}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                              Text(qty(_weights[i]), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
        bottomNavigationBar: SaveBar(
          label: _weights.isEmpty ? 'رجوع' : 'تمام: ${intf(_weights.length)} شكارة = ${qty(_total)} كجم',
          onSave: () => Navigator.pop(context, _weights),
        ),
      );

  Widget _stat(String label, String value) => Column(
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        ],
      );
}
