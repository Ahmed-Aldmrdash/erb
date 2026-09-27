import '../core/db/app_db.dart';
import '../core/util/format.dart';
import 'appliances_repo.dart';
import 'crops_repo.dart';

class ProfitLoss {
  const ProfitLoss({
    required this.revenue,
    required this.cogs,
    required this.expenses,
    this.extraIncome = 0,
  });

  /// Net sales.
  final double revenue;

  /// Cost of the goods that were sold.
  final double cogs;
  final double expenses;

  /// Installment markup.
  final double extraIncome;

  double get gross => roundMoney(revenue - cogs + extraIncome);

  double get net => roundMoney(gross - expenses);
}

class ReportsRepo {
  ReportsRepo(this.db, this.crops, this.appliances);

  final AppDb db;
  final CropsRepo crops;
  final AppliancesRepo appliances;

  /// What people owe us and what we owe them.
  Future<({double receivable, double payable})> receivablesPayables() async {
    final r = await db.q1('''
SELECT IFNULL(SUM(CASE WHEN balance > 0.009 THEN balance END), 0) AS receivable,
  IFNULL(SUM(CASE WHEN balance < -0.009 THEN -balance END), 0) AS payable
FROM (SELECT party_id, SUM(debit) - SUM(credit) AS balance FROM v_party_ledger GROUP BY party_id)''');
    return (receivable: n(r?['receivable']), payable: n(r?['payable']));
  }

  Future<double> cashTotal() => db.val('''
SELECT IFNULL(SUM(l.amount_in) - SUM(l.amount_out), 0)
FROM v_cash_ledger l JOIN cash_boxes c ON c.id = l.cash_box_id
WHERE c.deleted = 0''');

  /// Last [days] days, oldest first: sales (المعرض) or purchases and sales
  /// (التجارة) per day, for the dashboard chart.
  Future<List<({String date, double a, double b})>> dailySeries(int days) async {
    final start = DateTime.now().subtract(Duration(days: days - 1));
    final from = dateStr(start);
    final rows = await db.q('''
SELECT date,
  SUM(CASE WHEN src = 'a' THEN amount ELSE 0 END) AS a,
  SUM(CASE WHEN src = 'b' THEN amount ELSE 0 END) AS b
FROM (
  SELECT date, 'a' AS src, CASE WHEN kind = 'sale' THEN total ELSE -total END AS amount
    FROM invoices WHERE deleted = 0 AND kind IN ('sale', 'sale_return') AND date >= ?
  UNION ALL SELECT date, CASE WHEN kind = 'purchase' THEN 'b' ELSE 'a' END, party_total
    FROM crop_trades WHERE deleted = 0 AND date >= ?
) GROUP BY date''', [from, from]);
    final byDate = {for (final r in rows) s(r['date']): r};
    return [
      for (var i = 0; i < days; i++)
        () {
          final d = dateStr(start.add(Duration(days: i)));
          final r = byDate[d];
          return (date: d, a: n(r?['a']), b: n(r?['b']));
        }(),
    ];
  }

  Future<DbRow> cropsActivity(String from, String to) async => (await db.q1('''
SELECT
  IFNULL(SUM(CASE WHEN kind = 'purchase' THEN net_kg END), 0) AS bought_kg,
  IFNULL(SUM(CASE WHEN kind = 'purchase' THEN party_total END), 0) AS bought_amount,
  COUNT(CASE WHEN kind = 'purchase' THEN 1 END) AS bought_count,
  IFNULL(SUM(CASE WHEN kind = 'sale' THEN net_kg END), 0) AS sold_kg,
  IFNULL(SUM(CASE WHEN kind = 'sale' THEN party_total END), 0) AS sold_amount,
  COUNT(CASE WHEN kind = 'sale' THEN 1 END) AS sold_count
FROM crop_trades WHERE deleted = 0 AND date >= ? AND date <= ?''', [from, to]))!;

  Future<double> expensesTotal(String from, String to) => db.val('''
SELECT IFNULL(SUM(amount), 0) FROM vouchers
WHERE deleted = 0 AND kind = 'expense' AND date >= ? AND date <= ?''', [from, to]);

  Future<List<DbRow>> expensesByCategory(String from, String to) => db.q('''
SELECT IFNULL(NULLIF(category, ''), 'أخرى') AS category, SUM(amount) AS amount
FROM vouchers WHERE deleted = 0 AND kind = 'expense' AND date >= ? AND date <= ?
GROUP BY 1 ORDER BY amount DESC''', [from, to]);

  Future<ProfitLoss> cropsProfit(String from, String to) async {
    final rows = await crops.profitByCrop(from, to);
    var revenue = 0.0, cogs = 0.0;
    for (final r in rows) {
      revenue += n(r['sales_net']);
      cogs += n(r['cogs']);
    }
    return ProfitLoss(
      revenue: roundMoney(revenue),
      cogs: roundMoney(cogs),
      expenses: await expensesTotal(from, to),
    );
  }

  Future<ProfitLoss> appliancesProfit(String from, String to) async {
    final r = await appliances.salesSummary(from, to);
    return ProfitLoss(
      revenue: roundMoney(n(r['sales']) - n(r['returns'])),
      cogs: n(r['cogs']),
      extraIncome: n(r['markup']),
      expenses: await expensesTotal(from, to),
    );
  }

  // ---------------------------------------------------------------- season

  /// Everything about a crop season (or any period): per crop, per farmer,
  /// per trader, advances, expenses and profit.
  Future<SeasonReport> season(String from, String to, {String? cropId}) async {
    final cropCond = cropId == null ? '' : 'AND t.crop_id = ?';
    final args = [from, to, ?cropId];
    final byCrop = await db.q('''
SELECT t.crop_id, c.name, c.unit_name, c.kg_per_unit, t.kind,
  COUNT(*) AS cnt,
  IFNULL(SUM(t.gross_kg - t.tare_kg), 0) AS load_kg,
  IFNULL(SUM(t.gross_kg - t.tare_kg - t.net_kg), 0) AS deducted_kg,
  IFNULL(SUM(t.net_kg), 0) AS net_kg,
  IFNULL(SUM(t.subtotal), 0) AS value,
  IFNULL(SUM(t.party_total), 0) AS party_total,
  IFNULL(SUM(t.paid_amount), 0) AS paid,
  IFNULL(SUM(t.freight + t.loading + t.other_expenses), 0) AS expenses
FROM crop_trades t LEFT JOIN crops c ON c.id = t.crop_id
WHERE t.deleted = 0 AND t.date >= ? AND t.date <= ? $cropCond
GROUP BY t.crop_id, t.kind
ORDER BY c.name''', args);
    final byParty = await db.q('''
SELECT t.party_id, p.name, p.phone, t.kind,
  COUNT(*) AS cnt,
  IFNULL(SUM(t.net_kg), 0) AS net_kg,
  IFNULL(SUM(t.party_total), 0) AS party_total,
  IFNULL(SUM(t.paid_amount), 0) AS paid,
  (SELECT IFNULL(SUM(debit) - SUM(credit), 0) FROM v_party_ledger l WHERE l.party_id = t.party_id) AS balance
FROM crop_trades t LEFT JOIN parties p ON p.id = t.party_id
WHERE t.deleted = 0 AND t.date >= ? AND t.date <= ? $cropCond
GROUP BY t.party_id, t.kind
ORDER BY party_total DESC''', args);
    final advances = await db.q('''
SELECT v.party_id, p.name, COUNT(*) AS cnt, SUM(v.amount) AS amount
FROM vouchers v LEFT JOIN parties p ON p.id = v.party_id
WHERE v.deleted = 0 AND v.kind = 'advance' AND v.date >= ? AND v.date <= ?
GROUP BY v.party_id ORDER BY amount DESC''', [from, to]);
    final profit = (await crops.profitByCrop(from, to)).where((r) => cropId == null || r['id'] == cropId).toList();
    final stock = (await crops.crops()).where((c) => cropId == null || c['id'] == cropId).toList();
    return SeasonReport(
      purchases: byCrop.where((r) => r['kind'] == 'purchase').toList(),
      sales: byCrop.where((r) => r['kind'] == 'sale').toList(),
      farmers: byParty.where((r) => r['kind'] == 'purchase').toList(),
      traders: byParty.where((r) => r['kind'] == 'sale').toList(),
      advances: advances,
      profit: profit,
      stock: stock.where((c) => n(c['stock_kg']).abs() > 0.0005).toList(),
      expenses: cropId == null ? await expensesByCategory(from, to) : const [],
    );
  }
}

class SeasonReport {
  const SeasonReport({
    required this.purchases,
    required this.sales,
    required this.farmers,
    required this.traders,
    required this.advances,
    required this.profit,
    required this.stock,
    required this.expenses,
  });

  /// Per crop (kind = purchase / sale): cnt, load_kg, deducted_kg, net_kg,
  /// value, party_total, paid, expenses.
  final List<DbRow> purchases;
  final List<DbRow> sales;

  /// Per farmer / trader, with the whole account balance today.
  final List<DbRow> farmers;
  final List<DbRow> traders;
  final List<DbRow> advances;
  final List<DbRow> profit;
  final List<DbRow> stock;
  final List<DbRow> expenses;

  double _sum(List<DbRow> rows, String key) => roundMoney(rows.fold<double>(0, (a, r) => a + n(r[key])));

  double get boughtKg => _sum(purchases, 'net_kg');
  double get boughtAmount => _sum(purchases, 'party_total');
  double get soldKg => _sum(sales, 'net_kg');
  double get soldAmount => _sum(sales, 'party_total');
  double get tradeExpenses => roundMoney(_sum(purchases, 'expenses') + _sum(sales, 'expenses'));
  double get deductedKg => _sum(purchases, 'deducted_kg');
  double get advancesTotal => _sum(advances, 'amount');
  double get otherExpenses => _sum(expenses, 'amount');
  double get grossProfit => _sum(profit, 'profit');
  double get netProfit => roundMoney(grossProfit - otherExpenses);
  int get tripsIn => purchases.fold<int>(0, (a, r) => a + ni(r['cnt']));
  int get tripsOut => sales.fold<int>(0, (a, r) => a + ni(r['cnt']));
}
