import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/labels.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common/excel_export.dart';
import 'voucher_detail.dart';
import 'voucher_form.dart';

/// List of vouchers, optionally of one kind (e.g. expenses or advances).
class VouchersScreen extends StatefulWidget {
  const VouchersScreen({super.key, this.kinds, this.title = 'السندات'});

  final List<String>? kinds;
  final String title;

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen> {
  Period _period = Period.thisMonth();
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final single = widget.kinds?.length == 1 ? widget.kinds!.first : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          ExcelButton(
            title: widget.title,
            sheets: () async => [await ExcelExport.vouchers(kinds: widget.kinds, name: widget.title)],
          ),
        ],
      ),
      floatingActionButton: single == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => push(context, VoucherForm(kind: single)),
              icon: const Icon(Icons.add),
              label: Text(voucherKinds[single] ?? 'إضافة'),
            ),
      body: Column(
        children: [
          SearchField(onChanged: (v) => setState(() => _search = v)),
          PeriodBar(value: _period, onChanged: (p) => setState(() => _period = p)),
          Expanded(
            child: DbBuilder<List<DbRow>>(
              queryKey: (_period, _search),
              query: () => app.accounts.vouchers(
                kinds: widget.kinds,
                from: _period.from,
                to: _period.to,
                search: _search,
              ),
              builder: (context, rows) {
                if (rows.isEmpty) return const EmptyView(icon: Icons.receipt_long_outlined, text: 'مفيش سندات في الفترة دي');
                final total = rows.fold<double>(0, (a, r) => a + n(r['amount']));
                return ListView(
                  padding: const EdgeInsets.only(bottom: 90),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(
                        children: [
                          Text('${rows.length} سند', style: const TextStyle(color: AppColors.muted)),
                          const Spacer(),
                          if (single != null) Text('الإجمالي: ${egp(total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    TileGroup(children: [for (final r in rows) VoucherTile(r)]),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class VoucherTile extends StatelessWidget {
  const VoucherTile(this.r, {super.key});

  final DbRow r;

  @override
  Widget build(BuildContext context) {
    final kind = s(r['kind']);
    final isIn = kind == 'receipt' || kind == 'deposit';
    final (icon, color) = switch (kind) {
      'receipt' || 'deposit' => (Icons.south_west, AppColors.good),
      'expense' => (Icons.receipt_long_outlined, AppColors.warn),
      'transfer' => (Icons.swap_horiz, AppColors.appliances),
      'advance' => (Icons.payments_outlined, AppColors.crops),
      _ => (Icons.north_east, AppColors.bad),
    };
    final who = [
      s(r['party_name']),
      s(r['category']),
      if (kind == 'transfer') '${s(r['box_name'])} ← ${s(r['to_box_name'])}',
    ].where((x) => x.isNotEmpty).join(' • ');
    return ListTile(
      leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color, size: 20)),
      title: Text(who.isEmpty ? (voucherKinds[kind] ?? '') : who, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${voucherKinds[kind] ?? ''} ${s(r['number'])} • ${showDate(r['date'])}'),
      trailing: Text(
        egp(n(r['amount'])),
        style: TextStyle(fontWeight: FontWeight.w700, color: kind == 'transfer' ? AppColors.text : (isIn ? AppColors.good : AppColors.bad)),
      ),
      onTap: () => push(context, VoucherDetailScreen(voucherId: s(r['id']))),
    );
  }
}
