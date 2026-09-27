import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../cash/daily_cash_screen.dart';
import '../common/open_doc.dart';
import 'voucher_form.dart';
import 'vouchers_screen.dart';

/// Cash boxes of the business (خزنة، فودافون كاش، بنك...) with balances.
class CashBoxesScreen extends StatelessWidget {
  const CashBoxesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('الخزن'),
          actions: [
            IconButton(
              tooltip: 'خزنة جديدة',
              onPressed: () => showCashBoxForm(context),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: DbBuilder<List<DbRow>>(
          query: () => app.accounts.cashBoxes(activeOnly: false),
          builder: (context, boxes) {
            final total = boxes.fold<double>(0, (a, b) => a + n(b['balance']));
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Box(
                    color: AppColors.primarySoft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('إجمالي الفلوس في الخزن', style: TextStyle(color: AppColors.muted)),
                        Text(egp(total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
                ActionGrid(columns: 4, children: [
                  ActionTile(
                    icon: Icons.today_outlined,
                    label: 'يومية الخزنة',
                    onTap: () => push(context, const DailyCashScreen()),
                  ),
                  ActionTile(
                    icon: Icons.swap_horiz,
                    label: 'تحويل',
                    color: AppColors.appliances,
                    onTap: () => push(context, const VoucherForm(kind: 'transfer')),
                  ),
                  ActionTile(
                    icon: Icons.savings_outlined,
                    label: 'إيداع',
                    color: AppColors.good,
                    onTap: () => push(context, const VoucherForm(kind: 'deposit')),
                  ),
                  ActionTile(
                    icon: Icons.outbox_outlined,
                    label: 'مسحوبات',
                    color: AppColors.accounts,
                    onTap: () => push(context, const VoucherForm(kind: 'withdrawal')),
                  ),
                ]),
                const SectionTitle('الخزن'),
                TileGroup(children: [
                  for (final b in boxes)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primarySoft,
                        child: Icon(Icons.account_balance_wallet_outlined, color: AppColors.primary),
                      ),
                      title: Text(s(b['name'])),
                      subtitle: n(b['active']) == 1 ? null : const Text('موقوفة'),
                      trailing: Text(egp(n(b['balance'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => push(context, CashBoxDetailScreen(boxId: s(b['id']))),
                    ),
                ]),
                const SectionTitle('السندات'),
                TileGroup(children: [
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined, color: AppColors.warn),
                    title: const Text('المصروفات'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => push(context, const VouchersScreen(kinds: ['expense'], title: 'المصروفات')),
                  ),
                  ListTile(
                    leading: Icon(Icons.description_outlined, color: AppColors.primary),
                    title: const Text('كل حركات الفلوس'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => push(context, const VouchersScreen()),
                  ),
                ]),
              ],
            );
          },
        ),
      );
}

Future<void> showCashBoxForm(BuildContext context, {DbRow? box}) async {
  final name = TextEditingController(text: s(box?['name']));
  final opening = TextEditingController(text: numText(n(box?['opening_balance'])));
  var active = box == null || n(box['active']) == 1;
  final formKey = GlobalKey<FormState>();
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(box == null ? 'خزنة جديدة' : 'تعديل الخزنة'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextF(controller: name, label: 'اسم الخزنة', validator: requiredText, hint: 'مثلاً: الخزنة، فودافون كاش، البنك'),
                const Gap(),
                NumField(controller: opening, label: 'رصيد أول المدة', suffix: currency),
                if (box != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('شغالة'),
                    value: active,
                    onChanged: (v) => setState(() => active = v),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (box != null)
            TextButton(
              onPressed: () async {
                final err = await app.accounts.deleteCashBox(s(box['id']));
                if (!c.mounted) return;
                if (err != null) {
                  toast(c, err, error: true);
                } else {
                  Navigator.pop(c);
                }
              },
              child: const Text('حذف', style: TextStyle(color: AppColors.bad)),
            ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await app.accounts.saveCashBox({
                'name': name.text.trim(),
                'opening_balance': parseNum(opening.text),
                'active': active,
              }, id: box == null ? null : s(box['id']));
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
}

class CashBoxDetailScreen extends StatefulWidget {
  const CashBoxDetailScreen({super.key, required this.boxId});

  final String boxId;

  @override
  State<CashBoxDetailScreen> createState() => _CashBoxDetailScreenState();
}

class _CashBoxDetailScreenState extends State<CashBoxDetailScreen> {
  Period _period = Period.thisMonth();

  Future<({DbRow? box, double opening, List<DbRow> rows})> _load() async {
    final box = await app.accounts.cashBox(widget.boxId);
    final l = await app.accounts.cashLedger(widget.boxId, _period.from, _period.to);
    return (box: box, opening: l.opening, rows: l.rows);
  }

  @override
  Widget build(BuildContext context) => DbBuilder<({DbRow? box, double opening, List<DbRow> rows})>(
        queryKey: _period,
        query: _load,
        builder: (context, d) {
          final box = d.box;
          if (box == null) return Scaffold(appBar: AppBar(), body: const SizedBox());
          final totalIn = d.rows.fold<double>(0, (a, r) => a + n(r['amount_in']));
          final totalOut = d.rows.fold<double>(0, (a, r) => a + n(r['amount_out']));
          return Scaffold(
            appBar: AppBar(
              title: Text(s(box['name'])),
              actions: [
                IconButton(onPressed: () => showCashBoxForm(context, box: box), icon: const Icon(Icons.edit_outlined)),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Box(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('الرصيد الحالي', style: TextStyle(color: AppColors.muted)),
                        Text(egp(n(box['balance'])), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
                PeriodBar(value: _period, onChanged: (p) => setState(() => _period = p)),
                CardRow(children: [
                  StatCard(label: 'رصيد أول الفترة', value: egp(d.opening)),
                  StatCard(label: 'داخل', value: egp(totalIn), color: AppColors.good),
                  StatCard(label: 'خارج', value: egp(totalOut), color: AppColors.bad),
                ]),
                const SectionTitle('الحركات'),
                if (d.rows.isEmpty)
                  const EmptyView(icon: Icons.inbox_outlined, text: 'مفيش حركات في الفترة دي')
                else
                  TileGroup(children: [for (final r in d.rows.reversed) CashMoveTile(r, showBalance: true)]),
              ],
            ),
          );
        },
      );
}

/// One cash movement with who entered it.
class CashMoveTile extends StatelessWidget {
  const CashMoveTile(this.r, {super.key, this.showBalance = false});

  final DbRow r;
  final bool showBalance;

  @override
  Widget build(BuildContext context) {
    final title = [s(r['title']), s(r['party_name']), s(r['category']), s(r['crop_name'])].where((x) => x.isNotEmpty).join(' • ');
    final sub = [
      showDate(r['date']),
      if (s(r['box_name']).isNotEmpty && !showBalance) s(r['box_name']),
      if (s(r['notes']).isNotEmpty) s(r['notes']),
      if (s(r['handled_by']).isNotEmpty) 'استلم/سلّم: ${s(r['handled_by'])}',
      if (s(r['by_name']).isNotEmpty) 'سجلها: ${s(r['by_name'])}',
      if (showBalance) 'الرصيد ${money(n(r['balance']))}',
    ].join(' • ');
    return ListTile(
      onTap: r['doc_type'] == 'opening' ? null : () => openDoc(context, s(r['doc_type']), s(r['doc_id'])),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (n(r['amount_in']) > 0)
            Text('\u200E+${money(n(r['amount_in']))}', style: const TextStyle(color: AppColors.good, fontWeight: FontWeight.w700)),
          if (n(r['amount_out']) > 0)
            Text('\u200E-${money(n(r['amount_out']))}', style: const TextStyle(color: AppColors.bad, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
