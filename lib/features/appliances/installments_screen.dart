import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/util/format.dart';
import '../../data/appliances_repo.dart';
import '../../data/calc.dart';
import '../../ui/share.dart';
import '../../ui/theme.dart';
import '../../ui/wa_text.dart';
import '../../ui/widgets.dart';
import '../accounts/voucher_form.dart';
import '../common/excel_export.dart';
import 'invoice_detail.dart';

/// Installments to collect: overdue, due soon, or all open ones.
class InstallmentsScreen extends StatefulWidget {
  const InstallmentsScreen({super.key, this.partyId});

  final String? partyId;

  @override
  State<InstallmentsScreen> createState() => _InstallmentsScreenState();
}

class _InstallmentsScreenState extends State<InstallmentsScreen> {
  String _filter = 'overdue';
  String _search = '';

  String? get _until => switch (_filter) {
        'overdue' => dateStr(DateTime.now().subtract(const Duration(days: 1))),
        'week' => dateStr(DateTime.now().add(const Duration(days: 7))),
        'month' => lastOfMonth(),
        _ => null,
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('الأقساط'),
          actions: [ExcelButton(title: 'الأقساط', sheets: () async => [await ExcelExport.installments()])],
        ),
        body: Column(
          children: [
            SearchField(onChanged: (v) => setState(() => _search = v), hint: 'بحث باسم العميل'),
            ChipsBar<String>(
              options: const {'overdue': 'المتأخرة', 'week': 'لحد أسبوع قدام', 'month': 'الشهر ده', 'all': 'كل الباقي'},
              value: _filter,
              onChanged: (v) => setState(() => _filter = v),
            ),
            Expanded(
              child: DbBuilder<List<InstallmentRow>>(
                queryKey: (_filter, _search),
                query: () async {
                  final rows = await app.appliances.openInstallments(until: _until, partyId: widget.partyId);
                  if (_search.trim().isEmpty) return rows;
                  final q = arFold(_search);
                  return rows.where((r) => arFold(s(r.invoice['party_name'])).contains(q)).toList();
                },
                builder: (context, rows) {
                  if (rows.isEmpty) {
                    return EmptyView(
                      icon: Icons.event_available_outlined,
                      text: _filter == 'overdue' ? 'مفيش أقساط متأخرة' : 'مفيش أقساط',
                    );
                  }
                  final total = rows.fold<double>(0, (a, r) => a + r.status.remaining);
                  final today = todayStr();
                  return TileListView(
                    bottomPadding: 24,
                    itemCount: rows.length,
                    itemBuilder: (context, i) => _Tile(r: rows[i], today: today),
                    header: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Row(
                          children: [
                            Text('${rows.length} قسط', style: const TextStyle(color: AppColors.muted)),
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

class _Tile extends StatelessWidget {
  const _Tile({required this.r, required this.today});

  final InstallmentRow r;
  final String today;

  @override
  Widget build(BuildContext context) {
    final st = r.status;
    final overdue = st.stateOn(today) == InstallmentState.overdue;
    final days = overdue ? DateTime.now().difference(parseDate(st.dueDate)!).inDays : 0;
    final inv = r.invoice;
    return ListTile(
      onTap: () => push(context, InvoiceDetailScreen(invoiceId: s(inv['id']))),
      leading: CircleAvatar(
        backgroundColor: (overdue ? AppColors.bad : AppColors.appliances).withValues(alpha: 0.12),
        child: Text('${st.seq}', style: TextStyle(color: overdue ? AppColors.bad : AppColors.appliances, fontWeight: FontWeight.w700)),
      ),
      title: Text(s(inv['party_name'])),
      subtitle: Text(
        'فاتورة ${s(inv['number'])} • ${showDate(st.dueDate)}${overdue ? ' • متأخر $days يوم' : ''}',
        style: TextStyle(color: overdue ? AppColors.bad : null),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(egp(st.remaining), style: const TextStyle(fontWeight: FontWeight.w700)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'collect') {
                push(
                  context,
                  VoucherForm(
                    kind: 'receipt',
                    partyId: inv['party_id'] as String?,
                    invoiceId: s(inv['id']),
                    amount: st.remaining,
                    notes: 'قسط ${st.seq} - فاتورة ${s(inv['number'])}',
                  ),
                );
              } else if (v == 'whatsapp') {
                openWhatsApp(context, s(inv['party_phone']), WaText.installment(inv, st, roundMoney(n(inv['grand_total']) - n(inv['paid_amount']) - n(inv['collected']))));
              } else if (v == 'call') {
                callPhone(context, s(inv['party_phone']));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'collect', child: Text('تحصيل')),
              PopupMenuItem(value: 'whatsapp', child: Text('تذكير واتساب')),
              PopupMenuItem(value: 'call', child: Text('اتصال')),
            ],
          ),
        ],
      ),
    );
  }
}
