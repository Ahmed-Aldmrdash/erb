import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/label_queue.dart';
import '../../core/util/format.dart';
import '../../ui/pickers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common/pdf_docs.dart';
import 'product_detail.dart';

/// ملصقات الأسعار: pick the products, say how many stickers each one needs,
/// and print an A4 sheet. The name, the number and the price are read when
/// the sheet is printed, so a label never shows an old price.
class LabelsScreen extends StatefulWidget {
  const LabelsScreen({super.key});

  @override
  State<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends State<LabelsScreen> {
  /// How many stickers one print job takes. A whole showroom at once is
  /// dozens of pages: it takes minutes to draw and can run the phone out of
  /// memory, so the sheet is printed in batches.
  static const maxPerPrint = 300;

  List<(DbRow, int)> _rows = const [];
  bool _wholesale = false;
  bool _loading = true;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final counts = LabelQueue.items();
    // One query for the whole list, in the order the products were queued.
    final found = await app.appliances.productsForLabels(counts.keys.toList());
    final byId = {for (final p in found) s(p['id']): p};
    final rows = <(DbRow, int)>[];
    final gone = <String>[];
    for (final e in counts.entries) {
      final p = byId[e.key];
      // A product that was deleted meanwhile just drops out of the list.
      if (p == null) {
        gone.add(e.key);
        continue;
      }
      rows.add((p, e.value));
    }
    for (final id in gone) {
      await LabelQueue.remove(id);
    }
    if (mounted) {
      setState(() {
        _rows = rows;
        _loading = false;
      });
    }
  }

  /// Everything on the shelves at once: the answer for a showroom that was
  /// already full of goods before the labels screen existed.
  Future<void> _addEverything() async {
    final counts = await app.appliances.stockCounts();
    if (!mounted) return;
    if (counts.isEmpty) {
      toast(context, 'مفيش أصناف عليها رصيد في المخزن', error: true);
      return;
    }
    final stickers = counts.values.fold<int>(0, (a, b) => a + b);
    final ok = await confirmDialog(
      context,
      title: 'ضيف كل اللي في المخزن',
      message: '${counts.length} صنف، و$stickers ملصق (ملصق لكل قطعة). '
          'الأصناف اللي في القايمة هتتظبط على نفس عدد القطع.'
          '${stickers > maxPerPrint ? '\n\nالطباعة بتطلع $maxPerPrint ملصق في المرة، فهتطبع على دفعات.' : ''}',
      ok: 'ضيفهم',
    );
    if (!ok) return;
    await LabelQueue.setAll(counts);
    await _load();
    if (mounted) toast(context, 'اتحجز $stickers ملصق لـ ${counts.length} صنف');
  }

  Future<void> _addProduct() async {
    final p = await pickProduct(context);
    if (p == null || !mounted) return;
    final stock = n(p['stock']);
    await LabelQueue.add(s(p['id']), stock >= 1 ? stock.round() : 1);
    await _load();
  }

  /// The + and − buttons: the number on the screen changes with the tap and
  /// the list is never rebuilt from the database, so it stays quick with a
  /// long queue.
  Future<void> _setCount(int index, int count) async {
    final (product, _) = _rows[index];
    final rows = [..._rows];
    if (count <= 0) {
      rows.removeAt(index);
    } else {
      rows[index] = (product, count);
    }
    setState(() => _rows = rows);
    await LabelQueue.setCount(s(product['id']), count);
  }

  Future<void> _print() async {
    if (_printing) return;
    // Products with no number of their own cannot carry a barcode.
    final missing = _rows.where((r) => s(r.$1['barcode']).isEmpty).toList();
    if (missing.isNotEmpty) {
      final ok = await confirmDialog(
        context,
        title: 'في أصناف من غير كود',
        message: '${missing.length} صنف من غير رقم. نديلهم أرقام دلوقتي؟',
        ok: 'إديهم أرقام',
      );
      if (!ok) return;
      for (final (p, _) in missing) {
        await app.appliances.saveProduct({'barcode': await app.appliances.nextProductCode()}, id: s(p['id']));
      }
      await _load();
    }
    if (!mounted || _rows.isEmpty) return;

    // One batch: the first products in the queue up to [maxPerPrint]
    // stickers, so a big queue prints over a few goes instead of dying.
    final batch = <(DbRow, int)>[];
    var taken = 0;
    for (final (p, count) in _rows) {
      if (taken >= maxPerPrint) break;
      final room = maxPerPrint - taken;
      final take = count > room ? room : count;
      batch.add((p, take));
      taken += take;
    }
    final rest = _total - taken;
    if (rest > 0) {
      final ok = await confirmDialog(
        context,
        title: 'القايمة كبيرة',
        message: 'عندك $_total ملصق. هنطبع $taken دلوقتي، والباقي ($rest) '
            'هيفضل في القايمة وتطبعه بعد كده.',
        ok: 'اطبع $taken',
      );
      if (!ok || !mounted) return;
    }

    setState(() => _printing = true);
    final wholesale = _wholesale;
    try {
      await Printing.layoutPdf(
        onLayout: (_) => PdfDocs.labels(batch, wholesale: wholesale),
        name: 'ملصقات الأسعار',
      );
    } catch (e) {
      if (mounted) toast(context, 'الطباعة مانفعتش. جرب عدد أقل من الملصقات.', error: true);
      return;
    } finally {
      if (mounted) setState(() => _printing = false);
    }
    if (!mounted) return;
    // Taking what came out of the printer off the list is what lets the next
    // press carry on from where this one stopped.
    final ok = await confirmDialog(
      context,
      title: 'اتطبعوا؟',
      message: 'نشيل الـ $taken ملصق اللي اتطبعوا من القايمة؟'
          '${rest > 0 ? '\nوتكمل الباقي ($rest) في الطبعة اللي بعدها.' : ''}',
      ok: 'شيلهم',
    );
    if (!ok) return;
    for (final (p, count) in batch) {
      final id = s(p['id']);
      final left = (LabelQueue.items()[id] ?? 0) - count;
      await LabelQueue.setCount(id, left);
    }
    await _load();
  }

  int get _total => _rows.fold(0, (a, r) => a + r.$2);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('ملصقات الأسعار'),
          actions: [
            IconButton(
              tooltip: 'ضيف كل اللي في المخزن',
              onPressed: _addEverything,
              icon: const Icon(Icons.playlist_add),
            ),
            if (_rows.isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  final ok = await confirmDialog(context, title: 'تفريغ القايمة', message: 'تشيل كل الأصناف؟', ok: 'تفريغ', danger: true);
                  if (!ok) return;
                  await LabelQueue.clear();
                  await _load();
                },
                icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.bad),
                label: const Text('تفريغ', style: TextStyle(color: AppColors.bad)),
              ),
          ],
        ),
        floatingActionButton: _rows.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: _addProduct,
                icon: const Icon(Icons.add),
                label: const Text('ضيف صنف'),
              ),
        bottomNavigationBar: _rows.isEmpty
            ? null
            : SaveBar(
                label: _printing ? 'بيجهّز الملصقات...' : 'اطبع ${_total > maxPerPrint ? maxPerPrint : _total} ملصق',
                icon: Icons.print_outlined,
                busy: _printing,
                onSave: _print,
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rows.isEmpty
                ? EmptyView(
                    icon: Icons.local_offer_outlined,
                    text: 'القايمة فاضية. ضيف كل اللي في المخزن مرة واحدة، أو صنف صنف.',
                    actionLabel: 'ضيف كل اللي في المخزن',
                    onAction: _addEverything,
                  )
                : TileListView(
                    itemCount: _rows.length,
                    header: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Choice<bool>(
                            options: const {false: 'سعر القطاعي', true: 'سعر الجملة'},
                            value: _wholesale,
                            onChanged: (v) => setState(() => _wholesale = v),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                          child: Row(
                            children: [
                              Text('${_rows.length} صنف', style: const TextStyle(color: AppColors.muted)),
                              const Spacer(),
                              Text('$_total ملصق', style: const TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    footer: const Padding(
                      padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Text(
                        'الملصق بيتطبع بسعر النهارده من المخزن، فلو غيّرت سعر صنف اطبعله ملصق جديد.',
                        style: TextStyle(color: AppColors.muted, height: 1.5, fontSize: 13),
                      ),
                    ),
                    itemBuilder: (context, i) {
                      final (p, count) = _rows[i];
                      final code = s(p['barcode']);
                      return ListTile(
                        onTap: () => push(context, ProductDetailScreen(productId: s(p['id']))),
                        title: Text(s(p['name']), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            code.isEmpty ? 'من غير كود' : 'كود $code',
                            egp(n(p[_wholesale ? 'wholesale_price' : 'retail_price'])),
                          ].join(' • '),
                          style: TextStyle(color: code.isEmpty ? AppColors.warn : null),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton.outlined(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _setCount(i, count - 1),
                              icon: const Icon(Icons.remove, size: 18),
                            ),
                            SizedBox(
                              width: 34,
                              child: Text('$count', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            ),
                            IconButton.outlined(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _setCount(i, count + 1),
                              icon: const Icon(Icons.add, size: 18),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      );
}

/// Sends one product to the label queue and opens the sheet.
Future<void> addToLabels(BuildContext context, DbRow product, {int? count}) async {
  final stock = n(product['stock']);
  await LabelQueue.add(s(product['id']), count ?? (stock >= 1 ? stock.round() : 1));
  if (context.mounted) await push(context, const LabelsScreen());
}
