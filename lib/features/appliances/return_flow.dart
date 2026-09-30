import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/appliances_repo.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'invoice_form.dart';

/// المرتجعات، خطوة خطوة: اختار الفاتورة اللي البضاعة راجعة منها، بعدين حدد
/// اللي رجع منها بالظبط.
///
/// Everything else follows from the return invoice that comes out of it: the
/// pieces go back on the shelf, the money comes off what the customer owes,
/// and the sale figures are netted down — nothing has to be fixed by hand.
Future<void> startReturn(BuildContext context, {String kind = 'sale_return'}) async {
  final picked = await push<(DbRow, List<InvoiceLineDraft>)>(
    context,
    _PickInvoiceScreen(kind: kind),
  );
  if (picked == null || !context.mounted) return;
  await push(
    context,
    InvoiceForm(kind: kind, returnOfId: s(picked.$1['id']), initialLines: picked.$2),
  );
}

/// Straight to the pieces of one invoice, for the return started from the
/// invoice itself.
Future<void> returnFromInvoice(BuildContext context, DbRow invoice) async {
  final kind = s(invoice['kind']) == 'sale' ? 'sale_return' : 'purchase_return';
  final lines = await push<List<InvoiceLineDraft>>(
    context,
    ReturnLinesScreen(invoice: invoice, kind: kind),
  );
  if (lines == null || lines.isEmpty || !context.mounted) return;
  await push(
    context,
    InvoiceForm(kind: kind, returnOfId: s(invoice['id']), initialLines: lines),
  );
}

/// Step one: which invoice did the goods go out on.
class _PickInvoiceScreen extends StatefulWidget {
  const _PickInvoiceScreen({required this.kind});

  final String kind;

  @override
  State<_PickInvoiceScreen> createState() => _PickInvoiceScreenState();
}

class _PickInvoiceScreenState extends State<_PickInvoiceScreen> {
  String _search = '';
  Period _period = Period.all();

  bool get _isSale => widget.kind == 'sale_return';

  Future<void> _open(DbRow invoice) async {
    final lines = await push<List<InvoiceLineDraft>>(
      context,
      ReturnLinesScreen(invoice: invoice, kind: widget.kind),
    );
    if (lines == null || lines.isEmpty || !mounted) return;
    Navigator.pop(context, (invoice, lines));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_isSale ? 'مرتجع: اختار الفاتورة' : 'مرتجع للمورد: اختار الفاتورة')),
        body: Column(
          children: [
            SearchField(
              onChanged: (v) => setState(() => _search = v),
              hint: _isSale ? 'اسم العميل أو رقم الفاتورة' : 'اسم المورد أو رقم الفاتورة',
            ),
            PeriodBar(value: _period, onChanged: (p) => setState(() => _period = p)),
            Expanded(
              child: DbBuilder<List<DbRow>>(
                queryKey: (_search, _period, widget.kind),
                query: () => app.appliances.invoices(
                  kinds: [_isSale ? 'sale' : 'purchase'],
                  from: _period.from,
                  to: _period.to,
                  search: _search,
                  limit: 300,
                ),
                builder: (context, rows) {
                  if (rows.isEmpty) {
                    return const EmptyView(
                      icon: Icons.receipt_long_outlined,
                      text: 'مفيش فواتير في الفترة دي. جرب "الكل" فوق.',
                    );
                  }
                  return ListView(
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                        child: Text(
                          'دوس على الفاتورة اللي البضاعة راجعة منها.',
                          style: TextStyle(color: AppColors.muted, fontSize: 13),
                        ),
                      ),
                      TileGroup(children: [
                        for (final r in rows)
                          ListTile(
                            onTap: () => _open(r),
                            title: Text(
                              s(r['party_name']).isNotEmpty
                                  ? s(r['party_name'])
                                  : (s(r['customer_name']).isNotEmpty ? s(r['customer_name']) : 'بدون اسم'),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              ['فاتورة ${s(r['number'])}', showDate(s(r['date'])), '${ni(r['line_count'])} صنف'].join(' • '),
                            ),
                            trailing: Text(egp(n(r['grand_total'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                      ]),
                      const Gap(80),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
}

/// Step two: how many pieces of each product came back.
class ReturnLinesScreen extends StatefulWidget {
  const ReturnLinesScreen({super.key, required this.invoice, required this.kind});

  final DbRow invoice;
  final String kind;

  @override
  State<ReturnLinesScreen> createState() => _ReturnLinesScreenState();
}

class _ReturnLinesScreenState extends State<ReturnLinesScreen> {
  List<DbRow> _rows = const [];
  final _take = <String, double>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await app.appliances.returnableLines(s(widget.invoice['id']));
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  double _left(DbRow r) => n(r['qty']) - n(r['returned_qty']);

  double _taken(DbRow r) => _take[s(r['product_id'])] ?? 0;

  void _set(DbRow r, double v) {
    final left = _left(r);
    final capped = v < 0 ? 0.0 : (v > left ? left : v);
    setState(() {
      if (capped <= 0) {
        _take.remove(s(r['product_id']));
      } else {
        _take[s(r['product_id'])] = capped;
      }
    });
  }

  double get _total => _rows.fold(0, (a, r) => a + _taken(r) * n(r['price']));

  int get _count => _take.length;

  void _done() {
    final lines = [
      for (final r in _rows)
        if (_taken(r) > 0)
          InvoiceLineDraft(
            productId: s(r['product_id']),
            name: s(r['product_name']),
            unit: s(r['unit']),
            qty: _taken(r),
            price: n(r['price']),
          ),
    ];
    Navigator.pop(context, lines);
  }

  @override
  Widget build(BuildContext context) {
    final anythingLeft = _rows.any((r) => _left(r) > 0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('اللي رجع من الفاتورة'),
        actions: [
          if (anythingLeft)
            TextButton(
              onPressed: () => setState(() {
                for (final r in _rows) {
                  final left = _left(r);
                  if (left > 0) _take[s(r['product_id'])] = left;
                }
              }),
              child: const Text('رجّع الكل'),
            ),
        ],
      ),
      bottomNavigationBar: _count == 0
          ? null
          : SaveBar(
              label: 'كمل ($_count صنف بـ ${money(_total)})',
              icon: Icons.arrow_back,
              onSave: _done,
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s(widget.invoice['party_name']).isNotEmpty
                                ? s(widget.invoice['party_name'])
                                : (s(widget.invoice['customer_name']).isNotEmpty
                                    ? s(widget.invoice['customer_name'])
                                    : 'بدون اسم'),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'فاتورة ${s(widget.invoice['number'])} • ${showDate(s(widget.invoice['date']))}'
                            ' • ${egp(n(widget.invoice['grand_total']))}',
                            style: const TextStyle(color: AppColors.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Gap(),
                if (!anythingLeft)
                  const EmptyView(
                    icon: Icons.assignment_turned_in_outlined,
                    text: 'الفاتورة دي رجع منها كل حاجة خلاص.',
                  )
                else
                  TileGroup(children: [
                    for (final r in _rows) _lineTile(r),
                  ]),
                const Gap(),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'اللي هتحدده هيرجع للمخزن، وحسابه هيتشال من على العميل، والمبيعات هتتحسب من غيره.',
                    style: TextStyle(color: AppColors.muted, height: 1.5, fontSize: 13),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _lineTile(DbRow r) {
    final left = _left(r);
    final taken = _taken(r);
    final done = left <= 0;
    return ListTile(
      onTap: done ? null : () => _set(r, taken > 0 ? 0 : 1),
      title: Text(
        s(r['product_name']),
        style: TextStyle(fontWeight: FontWeight.w700, color: done ? AppColors.muted : null),
      ),
      subtitle: Text(
        done
            ? 'رجع كله قبل كده'
            : [
                'اتباع ${qty(n(r['qty']))} ${s(r['unit'])}',
                if (n(r['returned_qty']) > 0) 'رجع منها ${qty(n(r['returned_qty']))}',
                '${money(n(r['price']))} للقطعة',
              ].join(' • '),
        style: TextStyle(color: done ? AppColors.muted : null, fontSize: 12.5),
      ),
      trailing: done
          ? const Icon(Icons.check_circle_outline, color: AppColors.muted)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.outlined(
                  visualDensity: VisualDensity.compact,
                  onPressed: taken <= 0 ? null : () => _set(r, taken - 1),
                  icon: const Icon(Icons.remove, size: 18),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    qty(taken),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: taken > 0 ? AppColors.appliances : AppColors.muted,
                    ),
                  ),
                ),
                IconButton.outlined(
                  visualDensity: VisualDensity.compact,
                  onPressed: taken >= left ? null : () => _set(r, taken + 1),
                  icon: const Icon(Icons.add, size: 18),
                ),
              ],
            ),
    );
  }
}
