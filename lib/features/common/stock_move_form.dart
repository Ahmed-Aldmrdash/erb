import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/labels.dart';
import '../../ui/pickers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Transfer between warehouses, or a stock adjustment (shrinkage, stock
/// count, opening stock) for a crop (kg) or a product (pieces).
class StockMoveForm extends StatefulWidget {
  const StockMoveForm({super.key, required this.itemType, required this.kind, this.itemId});

  final String itemType;
  final String kind;
  final String? itemId;

  @override
  State<StockMoveForm> createState() => _StockMoveFormState();
}

class _StockMoveFormState extends State<StockMoveForm> {
  final _form = GlobalKey<FormState>();
  final _qty = TextEditingController();
  final _notes = TextEditingController();
  String _date = todayStr();
  DbRow? _item;
  DbRow? _from;
  DbRow? _to;
  bool _decrease = true;
  double _available = 0;
  bool _submitted = false;
  bool _busy = false;

  bool get isCrop => widget.itemType == 'crop';
  bool get isTransfer => widget.kind == 'transfer';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.itemId != null) {
      _item = isCrop ? await app.db.byId('crops', widget.itemId) : await app.appliances.product(widget.itemId!);
    }
    final ws = await app.crops.warehouses();
    if (ws.isNotEmpty) _from = ws.first;
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_item != null && _from != null) {
      _available = isCrop
          ? await app.crops.stockAt(s(_item!['id']), s(_from!['id']))
          : await app.appliances.stockAt(s(_item!['id']), s(_from!['id']));
    }
    if (mounted) setState(() {});
  }

  String _qtyText(double v) =>
      isCrop ? kgWithUnits(v, s(_item?['unit_name']), n(_item?['kg_per_unit'])) : '${qty(v)} ${s(_item?['unit'])}';

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!_form.currentState!.validate() || _item == null || _from == null) return;
    if (isTransfer && (_to == null || _to!['id'] == _from!['id'])) return;
    final amount = parseNum(_qty.text);
    setState(() => _busy = true);
    await app.crops.saveStockMove({
      'kind': widget.kind,
      'date': _date,
      'item_type': widget.itemType,
      'item_id': _item!['id'],
      'warehouse_id': _from!['id'],
      'to_warehouse_id': isTransfer ? _to!['id'] : null,
      'qty': isTransfer || !_decrease ? amount : -amount,
      'notes': _notes.text.trim(),
    });
    if (!mounted) return;
    toast(context, 'تم الحفظ');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final reasons = _decrease
        ? (isCrop ? ['هالك / جفاف', 'عجز في الجرد', 'تالف'] : ['تالف', 'عجز في الجرد', 'عينة / استخدام'])
        : ['رصيد أول المدة', 'زيادة في الجرد'];
    return Scaffold(
      appBar: AppBar(title: Text(stockMoveKinds[widget.kind] ?? '')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DateField(label: 'التاريخ', value: _date, onChanged: (v) => setState(() => _date = v)),
            const Gap(),
            PickField(
              label: isCrop ? 'المحصول' : 'الصنف',
              value: _item == null ? null : s(_item!['name']),
              errorText: _submitted && _item == null ? 'اختار' : null,
              onTap: () async {
                final r = await (isCrop ? pickCrop(context) : pickProduct(context));
                if (r == null) return;
                _item = r;
                await _refresh();
              },
            ),
            const Gap(),
            PickField(
              label: isTransfer ? 'من مخزن' : 'المخزن',
              value: _from == null ? null : s(_from!['name']),
              errorText: _submitted && _from == null ? 'اختار المخزن' : null,
              helper: _item != null && _from != null ? 'الموجود: ${_qtyText(_available)}' : null,
              onTap: () async {
                final r = await pickWarehouse(context);
                if (r == null) return;
                _from = r;
                await _refresh();
              },
            ),
            const Gap(),
            if (isTransfer) ...[
              PickField(
                label: 'إلى مخزن',
                value: _to == null ? null : s(_to!['name']),
                errorText: _submitted && (_to == null || _to!['id'] == _from?['id']) ? 'اختار مخزن تاني' : null,
                onTap: () async {
                  final r = await pickWarehouse(context);
                  if (r != null) setState(() => _to = r);
                },
              ),
              const Gap(),
            ] else ...[
              Choice<bool>(
                options: const {true: 'نقص (هالك / عجز)', false: 'زيادة'},
                value: _decrease,
                onChanged: (v) => setState(() => _decrease = v),
              ),
              const Gap(),
            ],
            NumField(
              controller: _qty,
              label: isCrop ? 'الكمية بالكيلو' : 'الكمية',
              suffix: isCrop ? 'كجم' : s(_item?['unit']),
              validator: positiveNumber,
              helper: isCrop && _item != null && parseNum(_qty.text) > 0 ? _qtyText(parseNum(_qty.text)) : null,
              onChanged: (_) => setState(() {}),
            ),
            const Gap(),
            TextF(controller: _notes, label: 'السبب / ملاحظات', maxLines: 2),
            if (!isTransfer) ...[
              const Gap(6),
              Wrap(
                spacing: 6,
                children: [
                  for (final r in reasons) ActionChip(label: Text(r), onPressed: () => setState(() => _notes.text = r)),
                ],
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SaveBar(onSave: _save, busy: _busy),
    );
  }
}

class StockMovesScreen extends StatelessWidget {
  const StockMovesScreen({super.key, required this.itemType});

  final String itemType;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('التحويلات والتسويات')),
        body: DbBuilder<List<DbRow>>(
          query: () => app.crops.stockMoves(itemType),
          builder: (context, rows) {
            if (rows.isEmpty) return const EmptyView(icon: Icons.swap_horiz, text: 'مفيش حركات');
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                TileGroup(children: [
                  for (final r in rows)
                    ListTile(
                      leading: Icon(
                        r['kind'] == 'transfer' ? Icons.swap_horiz : Icons.tune,
                        color: r['kind'] == 'transfer' ? AppColors.appliances : AppColors.warn,
                      ),
                      title: Text(s(r['item_name'])),
                      subtitle: Text(
                        [
                          '${stockMoveKinds[r['kind']]} ${s(r['number'])} • ${showDate(r['date'])}',
                          r['kind'] == 'transfer'
                              ? '${s(r['warehouse_name'])} ← ${s(r['to_warehouse_name'])}'
                              : s(r['warehouse_name']),
                          if (s(r['notes']).isNotEmpty) s(r['notes']),
                          if (s(r['created_by_name']).isNotEmpty) 'سجلها: ${s(r['created_by_name'])}',
                        ].join('\n'),
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        itemType == 'crop'
                            ? unitsOf(n(r['qty']), s(r['unit_name']), n(r['kg_per_unit']))
                            : qty(n(r['qty'])),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: n(r['qty']) < 0 ? AppColors.bad : AppColors.good,
                        ),
                      ),
                      onLongPress: () async {
                        final ok = await confirmDialog(context, title: 'حذف الحركة', message: 'حذف الحركة دي؟', ok: 'حذف', danger: true);
                        if (ok) await app.crops.deleteStockMove(s(r['id']));
                      },
                    ),
                ]),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('للحذف: اضغط ضغطة طويلة على الحركة.', style: TextStyle(color: AppColors.muted)),
                ),
              ],
            );
          },
        ),
      );
}
