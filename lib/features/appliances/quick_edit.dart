import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/calc.dart';
import '../../ui/pickers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'labels_screen.dart';
import 'product_form.dart';

/// Changes the prices of a product without opening the whole form.
/// Returns true when something was saved.
Future<bool> editProductPrices(BuildContext context, DbRow product) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PriceSheet(product: product),
    ) ??
    false;

class _PriceSheet extends StatefulWidget {
  const _PriceSheet({required this.product});

  final DbRow product;

  @override
  State<_PriceSheet> createState() => _PriceSheetState();
}

class _PriceSheetState extends State<_PriceSheet> {
  late final _cost = TextEditingController(text: numText(n(widget.product['cost_price'])));
  late final _retail = TextEditingController(text: numText(n(widget.product['retail_price'])));
  late final _wholesale = TextEditingController(text: numText(n(widget.product['wholesale_price'])));
  final _profit = TextEditingController();
  bool _busy = false;

  void _fromProfit(String v) {
    final pct = parseNum(v), cost = parseNum(_cost.text);
    if (pct > 0 && cost > 0) _retail.text = numText(ceilToStep(cost * (1 + pct / 100), app.priceStep));
    setState(() {});
  }

  String? _margin(TextEditingController c) {
    final cost = parseNum(_cost.text), p = parseNum(c.text);
    if (cost <= 0 || p <= 0) return null;
    return 'مكسب ${money(p - cost)} (${intf(((p - cost) / cost * 100).round())}%)';
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await app.appliances.setPrices(
      s(widget.product['id']),
      cost: parseNum(_cost.text),
      retail: parseNum(_retail.text),
      wholesale: parseNum(_wholesale.text),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('أسعار ${s(widget.product['name'])}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const Gap(12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: NumField(
                    controller: _cost,
                    label: 'سعر الشراء',
                    suffix: currency,
                    onChanged: (_) => _fromProfit(_profit.text),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NumField(
                    controller: _profit,
                    label: 'نسبة المكسب',
                    suffix: '%',
                    onChanged: _fromProfit,
                  ),
                ),
              ],
            ),
            const Gap(),
            Row(
              children: [
                Expanded(
                  child: NumField(
                    controller: _retail,
                    label: 'سعر القطاعي',
                    suffix: currency,
                    autofocus: true,
                    helper: _margin(_retail),
                    onChanged: (_) => setState(() => _profit.clear()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NumField(
                    controller: _wholesale,
                    label: 'سعر الجملة',
                    suffix: currency,
                    helper: _margin(_wholesale),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const Gap(14),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('حفظ الأسعار'),
            ),
          ],
        ),
      );
}

/// Sets how many pieces are in the warehouse right now: the difference is
/// written as a stock adjustment, so the history stays honest.
/// Returns true when the stock was changed.
Future<bool> editProductStock(BuildContext context, DbRow product) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StockSheet(product: product),
    ) ??
    false;

class _StockSheet extends StatefulWidget {
  const _StockSheet({required this.product});

  final DbRow product;

  @override
  State<_StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends State<_StockSheet> {
  late final double _now = n(widget.product['stock']);
  late final _qty = TextEditingController(text: numText(_now));
  final _notes = TextEditingController();
  DbRow? _warehouse;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadWarehouse();
  }

  Future<void> _loadWarehouse() async {
    final ws = await app.crops.warehouses();
    if (ws.isNotEmpty && mounted) setState(() => _warehouse = ws.first);
  }

  double get _diff => roundMoney(parseNum(_qty.text) - _now);

  Future<void> _save() async {
    if (_warehouse == null) {
      toast(context, 'لازم يبقى في مخزن الأول', error: true);
      return;
    }
    if (_diff.abs() < 0.0001) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _busy = true);
    await app.crops.saveStockMove({
      'kind': 'adjust',
      'date': todayStr(),
      'item_type': 'product',
      'item_id': s(widget.product['id']),
      'warehouse_id': _warehouse!['id'],
      'qty': _diff,
      'notes': _notes.text.trim().isEmpty ? 'تعديل الكمية من شاشة الصنف' : _notes.text.trim(),
    });
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final diff = _diff;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('كمية ${s(widget.product['name'])}',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text('الموجود دلوقتي ${qty(_now)} ${s(widget.product['unit'])}',
              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          const Gap(12),
          Row(
            children: [
              IconButton.outlined(
                onPressed: () => setState(() => _qty.text = numText(parseNum(_qty.text) - 1)),
                icon: const Icon(Icons.remove),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NumField(
                  controller: _qty,
                  label: 'الكمية الصح في المخزن',
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: () => setState(() => _qty.text = numText(parseNum(_qty.text) + 1)),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          if (diff.abs() > 0.0001) ...[
            const Gap(8),
            InfoRow(
              diff > 0 ? 'هيتزود' : 'هينقص',
              '${qty(diff.abs())} ${s(widget.product['unit'])}',
              bold: true,
              color: diff > 0 ? AppColors.good : AppColors.bad,
            ),
          ],
          const Gap(),
          TextF(controller: _notes, label: 'السبب (اختياري)', hint: 'جرد، هالك، مرتجع...'),
          const Gap(),
          PickField(
            label: 'المخزن',
            value: _warehouse == null ? null : s(_warehouse!['name']),
            icon: Icons.warehouse_outlined,
            onTap: () async {
              final w = await pickWarehouse(context);
              if (w != null) setState(() => _warehouse = w);
            },
          ),
          const Gap(14),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('حفظ الكمية'),
          ),
        ],
      ),
    );
  }
}

/// Long press on a product anywhere: the things the showroom needs in a
/// hurry — the price, how many pieces are left, a label, or the full form.
Future<void> showProductActions(BuildContext context, DbRow product) async {
  final id = s(product['id']);
  await showModalBottomSheet<void>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              s(product['name']),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            [
              if (s(product['barcode']).isNotEmpty) 'كود ${s(product['barcode'])}',
              'المتاح ${qty(n(product['stock']))}',
              egp(n(product['retail_price'])),
            ].join(' • '),
            style: const TextStyle(color: AppColors.muted),
          ),
          const Gap(8),
          ListTile(
            leading: const Icon(Icons.price_change_outlined),
            title: const Text('تعديل السعر'),
            onTap: () async {
              Navigator.pop(c);
              await editProductPrices(context, product);
            },
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('تعديل الكمية في المخزن'),
            onTap: () async {
              Navigator.pop(c);
              await editProductStock(context, product);
            },
          ),
          ListTile(
            leading: const Icon(Icons.local_offer_outlined),
            title: const Text('ملصق سعر وباركود'),
            onTap: () async {
              Navigator.pop(c);
              await addToLabels(context, product);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('تعديل كل بيانات الصنف'),
            onTap: () {
              Navigator.pop(c);
              push(context, ProductFormScreen(id: id));
            },
          ),
        ],
      ),
    ),
  );
}
