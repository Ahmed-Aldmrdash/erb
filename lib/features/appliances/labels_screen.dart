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
  List<(DbRow, int)> _rows = const [];
  bool _wholesale = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final counts = LabelQueue.items();
    final rows = <(DbRow, int)>[];
    for (final e in counts.entries) {
      final p = await app.appliances.product(e.key);
      // A product that was deleted meanwhile just drops out of the list.
      if (p == null || n(p['deleted']) == 1) {
        await LabelQueue.remove(e.key);
        continue;
      }
      rows.add((p, e.value));
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
    final products = await app.appliances.products();
    final withStock = {
      for (final p in products)
        if (n(p['stock']) >= 1) s(p['id']): n(p['stock']).round(),
    };
    if (!mounted) return;
    if (withStock.isEmpty) {
      toast(context, 'مفيش أصناف عليها رصيد في المخزن', error: true);
      return;
    }
    final empty = products.length - withStock.length;
    final stickers = withStock.values.fold<int>(0, (a, b) => a + b);
    final ok = await confirmDialog(
      context,
      title: 'ضيف كل اللي في المخزن',
      message: '${withStock.length} صنف، و$stickers ملصق (ملصق لكل قطعة). '
          'الأصناف اللي في القايمة هتتظبط على نفس عدد القطع.'
          '${empty > 0 ? '\n\n($empty صنف خلصان مش هيتحطوا، اطبعلهم ملصق أول ما يجوا.)' : ''}',
      ok: 'ضيفهم',
    );
    if (!ok) return;
    await LabelQueue.setAll(withStock);
    await _load();
    if (mounted) toast(context, 'اتحجز $stickers ملصق لـ ${withStock.length} صنف');
  }

  Future<void> _addProduct() async {
    final p = await pickProduct(context);
    if (p == null || !mounted) return;
    final stock = n(p['stock']);
    await LabelQueue.add(s(p['id']), stock >= 1 ? stock.round() : 1);
    await _load();
  }

  Future<void> _setCount(DbRow p, int count) async {
    await LabelQueue.setCount(s(p['id']), count);
    await _load();
  }

  Future<void> _print() async {
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
    final rows = _rows;
    final wholesale = _wholesale;
    await Printing.layoutPdf(
      onLayout: (_) => PdfDocs.labels(rows, wholesale: wholesale),
      name: 'ملصقات الأسعار',
    );
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
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addProduct,
          icon: const Icon(Icons.add),
          label: const Text('ضيف صنف'),
        ),
        bottomNavigationBar: _rows.isEmpty
            ? null
            : SaveBar(
                label: 'اطبع $_total ملصق',
                icon: Icons.print_outlined,
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
                : ListView(
                    padding: const EdgeInsets.only(bottom: 90),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Choice<bool>(
                          options: const {false: 'سعر القطاعي', true: 'سعر الجملة'},
                          value: _wholesale,
                          onChanged: (v) => setState(() => _wholesale = v),
                        ),
                      ),
                      const Gap(),
                      TileGroup(children: [
                        for (final (p, count) in _rows)
                          ListTile(
                            onTap: () => push(context, ProductDetailScreen(productId: s(p['id']))),
                            title: Text(s(p['name'])),
                            subtitle: Text(
                              [
                                s(p['barcode']).isEmpty ? 'من غير كود' : 'كود ${s(p['barcode'])}',
                                egp(n(p[_wholesale ? 'wholesale_price' : 'retail_price'])),
                              ].join(' • '),
                              style: TextStyle(color: s(p['barcode']).isEmpty ? AppColors.warn : null),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton.outlined(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _setCount(p, count - 1),
                                  icon: const Icon(Icons.remove, size: 18),
                                ),
                                SizedBox(
                                  width: 34,
                                  child: Text('$count', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                ),
                                IconButton.outlined(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _setCount(p, count + 1),
                                  icon: const Icon(Icons.add, size: 18),
                                ),
                              ],
                            ),
                          ),
                      ]),
                      const Gap(),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'الملصق بيتطبع بسعر النهارده من المخزن، فلو غيّرت سعر صنف اطبعله ملصق جديد.',
                          style: TextStyle(color: AppColors.muted, height: 1.5, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
      );
}

/// Sends one product to the label queue and opens the sheet.
Future<void> addToLabels(BuildContext context, DbRow product, {int? count}) async {
  final stock = n(product['stock']);
  await LabelQueue.add(s(product['id']), count ?? (stock >= 1 ? stock.round() : 1));
  if (context.mounted) await push(context, const LabelsScreen());
}
