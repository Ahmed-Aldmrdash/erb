import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/appliances_repo.dart';
import '../../data/labels.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common/excel_export.dart';
import 'invoice_detail.dart';
import 'invoice_form.dart';
import 'return_flow.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key, this.kind = 'sale', this.mineOnly = false});

  final String kind;

  /// The sales this person wrote himself, and nothing else: what a cashier
  /// opens to find a receipt for a customer who came back.
  final bool mineOnly;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  late String _kind = widget.kind;
  String _payment = '';
  Period _period = Period.thisMonth();
  String _search = '';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.mineOnly
              ? 'فواتيري'
              : (_kind.endsWith('_return') ? 'المرتجعات' : 'الفواتير')),
          actions: [
            if (!widget.mineOnly)
              ExcelButton(
                title: 'فواتير المعرض',
                sheets: () async => [await ExcelExport.invoices(), await ExcelExport.invoiceLines()],
              ),
          ],
        ),
        floatingActionButton: widget.mineOnly
            ? null
            : FloatingActionButton.extended(
                // A return always starts from the invoice the goods went out
                // on, so the pieces, the prices and the customer come with it.
                onPressed: () => _kind.endsWith('_return')
                    ? startReturn(context, kind: _kind)
                    : push(context, InvoiceForm(kind: _kind)),
                icon: const Icon(Icons.add),
                label: Text(invoiceKinds[_kind] ?? 'فاتورة'),
              ),
        body: Column(
          children: [
            SearchField(onChanged: (v) => setState(() => _search = v), hint: 'بحث بالاسم أو رقم الفاتورة'),
            if (!widget.mineOnly)
              ChipsBar<String>(
                options: const {'sale': 'البيع', 'purchase': 'الشراء', 'sale_return': 'مرتجع بيع', 'purchase_return': 'مرتجع شراء'},
                value: _kind,
                onChanged: (v) => setState(() => _kind = v),
              ),
            if (_kind == 'sale' && !widget.mineOnly)
              ChipsBar<String>(
                options: const {'': 'كل طرق الدفع', 'cash': 'كاش', 'credit': 'آجل', 'installment': 'تقسيط'},
                value: _payment,
                onChanged: (v) => setState(() => _payment = v),
              ),
            PeriodBar(value: _period, onChanged: (p) => setState(() => _period = p)),
            Expanded(
              child: DbBuilder<List<DbRow>>(
                queryKey: (_kind, _payment, _period, _search, widget.mineOnly),
                query: () => app.appliances.invoices(
                  kinds: [widget.mineOnly ? 'sale' : _kind],
                  paymentType: _kind == 'sale' && _payment.isNotEmpty ? _payment : null,
                  from: _period.from,
                  to: _period.to,
                  search: _search,
                  byPerson: widget.mineOnly ? app.person : null,
                ),
                builder: (context, rows) {
                  if (rows.isEmpty) {
                    return EmptyView(
                      icon: Icons.receipt_long_outlined,
                      text: widget.mineOnly
                          ? 'مفيش فواتير كتبتها في الفترة دي'
                          : 'مفيش فواتير في الفترة دي',
                    );
                  }
                  final total = rows.fold<double>(0, (a, r) => a + n(r['grand_total']));
                  return TileListView(
                    itemCount: rows.length,
                    itemBuilder: (context, i) => InvoiceTile(rows[i]),
                    header: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Row(
                          children: [
                            Text('${rows.length} فاتورة', style: const TextStyle(color: AppColors.muted)),
                            const Spacer(),
                            Text('الإجمالي: ${egp(total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  );
                },
              ),
            ),
          ],
        ),
      );
}

class InvoiceTile extends StatelessWidget {
  const InvoiceTile(this.r, {super.key});

  final DbRow r;

  @override
  Widget build(BuildContext context) {
    final remaining = AppliancesRepo.remainingOf(r);
    final name = s(r['party_name']).isNotEmpty ? s(r['party_name']) : (s(r['customer_name']).isNotEmpty ? s(r['customer_name']) : 'عميل نقدي');
    final pt = s(r['payment_type']);
    final color = switch (pt) {
      'installment' => AppColors.accounts,
      'credit' => AppColors.warn,
      _ => AppColors.good,
    };
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.appliancesSoft,
        child: Icon(
          r['kind'] == 'sale' ? Icons.point_of_sale_outlined : (s(r['kind']).endsWith('return') ? Icons.assignment_return_outlined : Icons.shopping_cart_outlined),
          color: AppColors.appliances,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          Pill(paymentTypes[pt] ?? '', color: color),
        ],
      ),
      subtitle: Text('${s(r['number'])} • ${showDate(r['date'])} • ${ni(r['line_count'])} صنف'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(egp(n(r['grand_total'])), style: const TextStyle(fontWeight: FontWeight.w700)),
          if (remaining > 0.009) Text('باقي ${money(remaining)}', style: const TextStyle(color: AppColors.bad, fontSize: 12)),
        ],
      ),
      onTap: () => push(context, InvoiceDetailScreen(invoiceId: s(r['id']))),
    );
  }
}
