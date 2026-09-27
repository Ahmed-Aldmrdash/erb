import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/labels.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common/excel_export.dart';
import '../settings/sync_screen.dart';
import 'party_detail.dart';
import 'party_form.dart';

/// Accounts of the open business (customers & suppliers, or farmers &
/// traders) with what they owe, like a debt book.
class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key, this.balanceFilter = 0, this.kind = '', this.asTab = false});

  /// 1: only those who owe us, -1: only those we owe.
  final int balanceFilter;
  final String kind;
  final bool asTab;

  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  String _search = '';
  late String _filter = widget.balanceFilter > 0 ? '+' : (widget.balanceFilter < 0 ? '-' : widget.kind);
  String _sort = 'recent';

  Map<String, String> get _filters => {
        '': 'الكل',
        '+': 'لينا عندهم',
        '-': 'علينا ليهم',
        ...partyKindsFor(app.division),
      };

  Future<({List<DbRow> rows, double receivable, double payable})> _load() async {
    final rp = await app.reports.receivablesPayables();
    final rows = await app.accounts.parties(
      search: _search,
      kinds: _filter.isEmpty || _filter == '+' || _filter == '-' ? null : [_filter],
      balanceFilter: _filter == '+' ? 1 : (_filter == '-' ? -1 : 0),
      sort: _sort,
    );
    return (rows: rows, receivable: rp.receivable, payable: rp.payable);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.asTab ? 'الحسابات' : 'العملاء والموردين'),
          actions: [
            ExcelButton(title: 'حسابات ${app.divisionName}', sheets: () async => [await ExcelExport.parties()]),
            PopupMenuButton<String>(
              tooltip: 'الترتيب',
              icon: const Icon(Icons.sort),
              initialValue: _sort,
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'recent', child: Text('آخر حركة')),
                PopupMenuItem(value: 'balance', child: Text('الأكبر رصيداً')),
                PopupMenuItem(value: 'name', child: Text('بالاسم')),
              ],
            ),
            if (widget.asTab) const SyncButton(),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'party-add',
          onPressed: () => push(context, PartyFormScreen(defaultKind: partyKindsFor(app.division).keys.first)),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('اسم جديد'),
        ),
        body: DbBuilder(
          queryKey: (_search, _filter, _sort),
          query: _load,
          builder: (context, d) => CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SummaryBox(
                          label: 'لينا عند الناس',
                          value: d.receivable,
                          color: AppColors.good,
                          selected: _filter == '+',
                          onTap: () => setState(() => _filter = _filter == '+' ? '' : '+'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SummaryBox(
                          label: 'علينا للناس',
                          value: d.payable,
                          color: AppColors.bad,
                          selected: _filter == '-',
                          onTap: () => setState(() => _filter = _filter == '-' ? '' : '-'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: SearchField(onChanged: (v) => setState(() => _search = v), hint: 'بحث بالاسم أو التليفون')),
              SliverToBoxAdapter(child: ChipsBar<String>(options: _filters, value: _filter, onChanged: (v) => setState(() => _filter = v))),
              if (d.rows.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyView(icon: Icons.groups_outlined, text: 'مفيش أسماء هنا'),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  sliver: SliverList.separated(
                    itemCount: d.rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => PartyTile(d.rows[i]),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({required this.label, required this.value, required this.color, required this.selected, required this.onTap});

  final String label;
  final double value;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? color.withValues(alpha: 0.12) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? color : AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(egp(value), style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
      );
}

class PartyTile extends StatelessWidget {
  const PartyTile(this.r, {super.key});

  final DbRow r;

  @override
  Widget build(BuildContext context) {
    final balance = n(r['balance']);
    final b = balanceInfo(balance);
    final collect = s(r['collect_on']);
    final due = collect.isNotEmpty && balance > 0.009 && collect.compareTo(todayStr()) <= 0;
    final last = s(r['last_date']);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: due ? AppColors.bad.withValues(alpha: 0.5) : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => push(context, PartyDetailScreen(partyId: s(r['id']))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              LetterAvatar(s(r['name'])),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s(r['name']), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                    Text(
                      [
                        partyKinds[r['kind']] ?? '',
                        if (last.isNotEmpty) 'آخر حركة ${showDate(last)}',
                      ].where((x) => x.isNotEmpty).join(' • '),
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                    if (collect.isNotEmpty && balance > 0.009)
                      Text(
                        due ? 'ميعاد التحصيل جه: ${showDate(collect)}' : 'يحصّل ${showDate(collect)}',
                        style: TextStyle(color: due ? AppColors.bad : AppColors.warn, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(balance.abs() < 0.01 ? 'خالص' : money(balance.abs()),
                      style: TextStyle(color: b.color, fontWeight: FontWeight.w800, fontSize: 15)),
                  if (balance.abs() >= 0.01)
                    Text(b.word, style: TextStyle(color: b.color, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
