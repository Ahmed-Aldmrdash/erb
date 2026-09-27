import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/reports_repo.dart';
import '../../ui/share.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'season_report_screen.dart';

class _ReportData {
  late ProfitLoss pnl;
  DbRow sales = const {};
  List<DbRow> cropRows = const [];
  List<DbRow> topProducts = const [];
  List<DbRow> expenses = const [];
  double receivable = 0;
  double payable = 0;
  double cash = 0;
  double stock = 0;
}

/// Profit & loss of the open division for a period, plus money and stock.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Period _period = Period.thisMonth();

  Future<_ReportData> _load() async {
    final d = _ReportData();
    final f = _period.from, t = _period.to;
    if (app.isCrops) {
      d.pnl = await app.reports.cropsProfit(f, t);
      d.cropRows = await app.crops.profitByCrop(f, t);
      d.stock = await app.crops.stockValue();
    } else {
      d.pnl = await app.reports.appliancesProfit(f, t);
      d.sales = await app.appliances.salesSummary(f, t);
      d.topProducts = await app.appliances.topProducts(f, t);
      d.stock = await app.appliances.stockValue();
    }
    d.expenses = await app.reports.expensesByCategory(f, t);
    final rp = await app.reports.receivablesPayables();
    d.receivable = rp.receivable;
    d.payable = rp.payable;
    d.cash = await app.reports.cashTotal();
    return d;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('تقارير ${app.divisionName}')),
        body: Column(
          children: [
            PeriodBar(value: _period, onChanged: (p) => setState(() => _period = p), includeAll: true),
            Expanded(
              child: DbBuilder<_ReportData>(
                queryKey: _period,
                query: _load,
                builder: (context, d) => ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: Text('الفترة: ${_period.rangeText}', style: const TextStyle(color: AppColors.muted)),
                    ),
                    _resultCard(d.pnl),
                    if (app.isCrops)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: OutlinedButton.icon(
                          onPressed: () => push(context, const SeasonReportScreen()),
                          icon: const Icon(Icons.summarize_outlined),
                          label: const Text('تقرير الموسم بالتفصيل (الفلاحين والتجار والخصومات)'),
                        ),
                      ),
                    const SectionTitle('الأرباح والخسائر'),
                    _pnlBox(d.pnl),
                    if (app.isCrops) ..._cropsSection(d) else ..._showroomSection(d),
                    ..._expensesSection(d),
                    const SectionTitle('الفلوس والبضاعة دلوقتي'),
                    CardRow(children: [
                      StatCard(label: 'في الخزن', value: egp(d.cash), icon: Icons.account_balance_wallet_outlined),
                      StatCard(label: 'قيمة البضاعة', value: egp(d.stock), icon: Icons.inventory_2_outlined),
                    ]),
                    const Gap(10),
                    CardRow(children: [
                      StatCard(label: 'لينا عند الناس', value: egp(d.receivable), color: AppColors.good, icon: Icons.call_received),
                      StatCard(label: 'علينا للناس', value: egp(d.payable), color: AppColors.bad, icon: Icons.call_made),
                    ]),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: OutlinedButton.icon(
                        onPressed: () => openWhatsApp(context, null, _summary(d)),
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('ابعت ملخص التقرير على واتساب'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _resultCard(ProfitLoss p) {
    final good = p.net >= 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: good ? AppColors.goodSoft : AppColors.badSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: (good ? AppColors.good : AppColors.bad).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(good ? Icons.trending_up : Icons.trending_down, size: 40, color: good ? AppColors.good : AppColors.bad),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(good ? 'صافي الربح' : 'صافي الخسارة', style: const TextStyle(color: AppColors.muted)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      egp(p.net.abs()),
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: good ? AppColors.good : AppColors.bad),
                    ),
                  ),
                  Text('المبيعات ${egp(p.revenue)}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pnlBox(ProfitLoss p) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Box(
          child: Column(
            children: [
              InfoRow(app.isCrops ? 'صافي المبيعات (بعد المصاريف)' : 'صافي المبيعات (بعد المرتجعات)', egp(p.revenue)),
              InfoRow('تكلفة البضاعة المباعة', egp(p.cogs)),
              if (!app.isCrops) InfoRow('أرباح التقسيط (الزيادة)', egp(p.extraIncome)),
              InfoRow('مجمل الربح', egp(p.gross), bold: true),
              InfoRow('المصروفات', egp(p.expenses)),
              const Divider(),
              InfoRow(
                p.net >= 0 ? 'صافي الربح' : 'صافي الخسارة',
                egp(p.net.abs()),
                bold: true,
                big: true,
                color: p.net >= 0 ? AppColors.good : AppColors.bad,
              ),
            ],
          ),
        ),
      );

  List<Widget> _cropsSection(_ReportData d) => [
        if (d.cropRows.isNotEmpty) ...[
          const SectionTitle('حسب المحصول'),
          TileGroup(children: [
            for (final r in d.cropRows)
              ListTile(
                title: Text(s(r['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  'شراء ${unitsOf(n(r['bought_kg']), s(r['unit_name']), n(r['kg_per_unit']))} بـ ${money(n(r['bought_cost']))}\n'
                  'بيع ${unitsOf(n(r['sold_kg']), s(r['unit_name']), n(r['kg_per_unit']))} بـ ${money(n(r['sales_net']))}',
                ),
                isThreeLine: true,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('المكسب', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    Text(
                      money(n(r['profit'])),
                      style: TextStyle(fontWeight: FontWeight.w700, color: n(r['profit']) >= 0 ? AppColors.good : AppColors.bad),
                    ),
                  ],
                ),
              ),
          ]),
        ],
      ];

  List<Widget> _showroomSection(_ReportData d) {
    final count = n(d.sales['sales_count']);
    final net = n(d.sales['sales']) - n(d.sales['returns']);
    return [
      const SectionTitle('حركة البيع والشراء'),
      CardRow(children: [
        StatCard(label: 'عدد فواتير البيع', value: intf(count), icon: Icons.receipt_long_outlined),
        StatCard(label: 'متوسط الفاتورة', value: egp(count == 0 ? 0 : net / count), icon: Icons.calculate_outlined),
      ]),
      const Gap(10),
      CardRow(children: [
        StatCard(label: 'المرتجعات', value: egp(n(d.sales['returns'])), icon: Icons.assignment_return_outlined, color: AppColors.warn),
        StatCard(label: 'المشتريات', value: egp(n(d.sales['purchases'])), icon: Icons.add_shopping_cart, color: AppColors.crops),
      ]),
      if (d.topProducts.isNotEmpty) ...[
        const SectionTitle('الأكثر مبيعاً'),
        TileGroup(children: [
          for (final (i, r) in d.topProducts.indexed)
            ListTile(
              leading: CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.primarySoft,
                child: Text('${i + 1}', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              title: Text(s(r['name'])),
              subtitle: Text('الكمية: ${qty(n(r['qty']))}'),
              trailing: Text(egp(n(r['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ]),
      ],
    ];
  }

  List<Widget> _expensesSection(_ReportData d) {
    if (d.expenses.isEmpty) return const [];
    final total = d.expenses.fold<double>(0, (a, e) => a + n(e['amount']));
    return [
      const SectionTitle('المصروفات حسب البند'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Box(
          child: Column(
            children: [
              for (final e in d.expenses)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(s(e['category']), style: const TextStyle(fontWeight: FontWeight.w600))),
                          Text(egp(n(e['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total <= 0 ? 0 : n(e['amount']) / total,
                          minHeight: 6,
                          color: AppColors.warn,
                          backgroundColor: AppColors.warnSoft,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  String _summary(_ReportData d) {
    final p = d.pnl;
    return [
      'تقرير ${app.companyName} - ${app.divisionName}',
      'الفترة: ${_period.rangeText}',
      '',
      'المبيعات: ${egp(p.revenue)}',
      'تكلفة البضاعة: ${egp(p.cogs)}',
      if (p.extraIncome > 0) 'أرباح التقسيط: ${egp(p.extraIncome)}',
      'المصروفات: ${egp(p.expenses)}',
      '${p.net >= 0 ? 'صافي الربح' : 'صافي الخسارة'}: ${egp(p.net.abs())}',
      '',
      'في الخزن: ${egp(d.cash)}',
      'لينا عند الناس: ${egp(d.receivable)}',
      'علينا للناس: ${egp(d.payable)}',
      'قيمة البضاعة: ${egp(d.stock)}',
    ].join('\n');
  }
}
