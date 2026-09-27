import '../core/db/app_db.dart';
import '../core/util/format.dart';
import 'labels.dart';

/// Parties (customers, suppliers, farmers, traders), cash boxes, vouchers and
/// the settings of the open division.
class AccountsRepo {
  AccountsRepo(this.db);

  final AppDb db;

  static const _balanceSql =
      'SELECT party_id, SUM(debit) - SUM(credit) AS balance FROM v_party_ledger GROUP BY party_id';

  // ---------------------------------------------------------------- parties

  /// [balanceFilter] 1: they owe us, -1: we owe them. [sort] name | balance | recent.
  Future<List<DbRow>> parties({
    String search = '',
    List<String>? kinds,
    int balanceFilter = 0,
    String sort = 'name',
  }) {
    final where = <String>['p.deleted = 0'];
    final args = <Object?>[];
    if (search.trim().isNotEmpty) {
      where.add('(${arFoldSql('p.name')} LIKE ? OR IFNULL(p.phone, \'\') LIKE ?)');
      args
        ..add('%${arFold(search)}%')
        ..add('%${normalizeDigits(search.trim())}%');
    }
    if (kinds != null && kinds.isNotEmpty) {
      where.add('p.kind IN (${List.filled(kinds.length, '?').join(', ')})');
      args.addAll(kinds);
    }
    if (balanceFilter > 0) where.add('IFNULL(b.balance, 0) > 0.009');
    if (balanceFilter < 0) where.add('IFNULL(b.balance, 0) < -0.009');
    final order = switch (sort) {
      'balance' => 'ABS(IFNULL(b.balance, 0)) DESC',
      'recent' => 'IFNULL(last_date, p.created_at) DESC',
      _ => balanceFilter != 0 ? 'ABS(IFNULL(b.balance, 0)) DESC' : 'p.name',
    };
    return db.q('''
SELECT p.*, IFNULL(b.balance, 0) AS balance,
  (SELECT MAX(date) FROM v_party_ledger l WHERE l.party_id = p.id AND l.doc_type <> 'opening') AS last_date
FROM parties p
LEFT JOIN ($_balanceSql) b ON b.party_id = p.id
WHERE ${where.join(' AND ')}
ORDER BY $order''', args);
  }

  Future<DbRow?> party(String id) => db.q1('''
SELECT p.*, IFNULL((SELECT SUM(debit) - SUM(credit) FROM v_party_ledger WHERE party_id = p.id), 0) AS balance
FROM parties p WHERE p.id = ?''', [id]);

  /// Everything we gave him (عليه) and everything we took from him (له).
  Future<({double gave, double took})> partyTotals(String id) async {
    final r = await db.q1(
      'SELECT IFNULL(SUM(debit), 0) AS gave, IFNULL(SUM(credit), 0) AS took FROM v_party_ledger WHERE party_id = ?',
      [id],
    );
    return (gave: n(r?['gave']), took: n(r?['took']));
  }

  Future<double> partyBalance(String? id) async {
    if (id == null) return 0;
    return db.val('SELECT IFNULL(SUM(debit) - SUM(credit), 0) FROM v_party_ledger WHERE party_id = ?', [id]);
  }

  Future<String> saveParty(DbRow values, {String? id}) => db.write((w) async {
        if (id == null) return w.insert('parties', values);
        await w.update('parties', id, values);
        return id;
      });

  Future<void> setCollectDate(String partyId, String? date) =>
      db.write((w) => w.update('parties', partyId, {'collect_on': date}));

  /// Returns an error message when the party still has documents.
  Future<String?> deleteParty(String id) async {
    final used = await db.val(
      "SELECT COUNT(*) FROM v_party_ledger WHERE party_id = ? AND doc_type <> 'opening'",
      [id],
    );
    if (used > 0) return 'لا يمكن الحذف: له حركات مسجلة. احذف الحركات الأول.';
    await db.write((w) => w.delete('parties', id));
    return null;
  }

  /// People who promised to pay by [until] and still owe us.
  Future<List<DbRow>> dueCollections(String until) => db.q('''
SELECT p.*, b.balance FROM parties p
JOIN ($_balanceSql) b ON b.party_id = p.id
WHERE p.deleted = 0 AND IFNULL(p.collect_on, '') <> '' AND p.collect_on <= ? AND b.balance > 0.009
ORDER BY p.collect_on''', [until]);

  /// Account statement (صفحة الحساب) with a running balance.
  Future<List<DbRow>> partyLedger(String partyId, {String? from, String? to}) async {
    final rows = await db.q('''
SELECT l.*, c.name AS crop_name, t.net_kg, t.unit_name, t.kg_per_unit, t.price_per_unit,
  i.payment_type, v.handled_by, v.category,
  COALESCE(t.created_by_name, i.created_by_name, v.created_by_name) AS by_name
FROM v_party_ledger l
LEFT JOIN crop_trades t ON l.doc_type = 'crop_trade' AND t.id = l.doc_id
LEFT JOIN crops c ON c.id = t.crop_id
LEFT JOIN invoices i ON l.doc_type = 'invoice' AND i.id = l.doc_id
LEFT JOIN vouchers v ON l.doc_type = 'voucher' AND v.id = l.doc_id
WHERE l.party_id = ?
ORDER BY CASE WHEN l.doc_type = 'opening' THEN 0 ELSE 1 END, l.date, l.created_at''', [partyId]);
    var balance = 0.0;
    final all = [
      for (final r in rows)
        {
          ...r,
          'title': _ledgerTitle(r),
          'balance': balance = roundMoney(balance + n(r['debit']) - n(r['credit'])),
        },
    ];
    if (from == null && to == null) return all;
    // Period view: a carried-forward line, then the period's lines.
    final before = all.where((r) => from != null && s(r['date']).compareTo(from) < 0).toList();
    final inside = all.where((r) {
      final d = s(r['date']);
      return (from == null || d.compareTo(from) >= 0) && (to == null || d.compareTo(to) <= 0);
    }).toList();
    final carried = before.isEmpty ? 0.0 : n(before.last['balance']);
    return [
      if (before.isNotEmpty)
        {
          'doc_type': 'carried',
          'title': 'رصيد سابق',
          'date': from,
          'debit': carried > 0 ? carried : 0.0,
          'credit': carried < 0 ? -carried : 0.0,
          'balance': carried,
        },
      ...inside,
    ];
  }

  /// What happened, told on the party's page ("ورّد قمح 40 أردب", "دفع فلوس").
  String _ledgerTitle(DbRow r) {
    final kind = s(r['kind']);
    switch (r['doc_type']) {
      case 'opening':
        return 'رصيد سابق';
      case 'crop_trade':
        final what = '${s(r['crop_name'])} ${unitsOf(n(r['net_kg']), s(r['unit_name']), n(r['kg_per_unit']))}';
        return kind == 'sale' ? 'اشترى $what' : 'ورّد $what';
      case 'invoice':
        return switch (kind) {
          'sale' => 'اشترى بضاعة (${paymentTypes[r['payment_type']] ?? ''})',
          'purchase' => 'ورّد بضاعة',
          'sale_return' => 'رجّع بضاعة',
          _ => 'رجّعناله بضاعة',
        };
      case 'voucher':
        return switch (kind) {
          'receipt' => 'دفع فلوس',
          'payment' => 'خد فلوس',
          'advance' => 'خد سلفة',
          'debit_adj' => 'زيادة على حسابه',
          'credit_adj' => 'خصم من حسابه',
          _ => docLabel('voucher', kind),
        };
    }
    return docLabel(s(r['doc_type']), kind);
  }

  // ---------------------------------------------------------------- cash

  Future<List<DbRow>> cashBoxes({bool activeOnly = true}) => db.q('''
SELECT c.*, IFNULL((SELECT SUM(amount_in) - SUM(amount_out) FROM v_cash_ledger WHERE cash_box_id = c.id), 0) AS balance
FROM cash_boxes c WHERE c.deleted = 0 ${activeOnly ? 'AND c.active = 1' : ''} ORDER BY c.name''');

  Future<DbRow?> defaultCashBox() async {
    final boxes = await cashBoxes();
    return boxes.isEmpty ? null : boxes.first;
  }

  Future<DbRow?> cashBox(String id) => db.q1('''
SELECT c.*, IFNULL((SELECT SUM(amount_in) - SUM(amount_out) FROM v_cash_ledger WHERE cash_box_id = c.id), 0) AS balance
FROM cash_boxes c WHERE c.id = ?''', [id]);

  Future<String> saveCashBox(DbRow values, {String? id}) => db.write((w) async {
        if (id == null) return w.insert('cash_boxes', values);
        await w.update('cash_boxes', id, values);
        return id;
      });

  Future<String?> deleteCashBox(String id) async {
    final used = await db.val(
      "SELECT COUNT(*) FROM v_cash_ledger WHERE cash_box_id = ? AND doc_type <> 'opening'",
      [id],
    );
    if (used > 0) return 'لا يمكن الحذف: عليها حركات. ممكن توقفها بدل الحذف.';
    await db.write((w) => w.delete('cash_boxes', id));
    return null;
  }

  static const _cashDetail = '''
SELECT l.*, p.name AS party_name, v.category, v.handled_by, c.name AS crop_name, b.name AS box_name,
  COALESCE(v.created_by_name, t.created_by_name, i.created_by_name) AS by_name
FROM v_cash_ledger l
LEFT JOIN parties p ON p.id = l.party_id
LEFT JOIN vouchers v ON l.doc_type = 'voucher' AND v.id = l.doc_id
LEFT JOIN crop_trades t ON l.doc_type = 'crop_trade' AND t.id = l.doc_id
LEFT JOIN crops c ON c.id = t.crop_id
LEFT JOIN invoices i ON l.doc_type = 'invoice' AND i.id = l.doc_id
LEFT JOIN cash_boxes b ON b.id = l.cash_box_id''';

  /// Movements of a cash box between two dates, with the balance carried in.
  Future<({double opening, List<DbRow> rows})> cashLedger(String boxId, String from, String to) async {
    final opening = await db.val(
      'SELECT IFNULL(SUM(amount_in) - SUM(amount_out), 0) FROM v_cash_ledger WHERE cash_box_id = ? AND date < ?',
      [boxId, from],
    );
    final rows = await db.q('$_cashDetail WHERE l.cash_box_id = ? AND l.date >= ? AND l.date <= ? '
        'ORDER BY l.date, l.created_at', [boxId, from, to]);
    var balance = opening;
    return (
      opening: opening,
      rows: [
        for (final r in rows)
          {
            ...r,
            'title': docLabel(s(r['doc_type']), s(r['kind'])),
            'balance': balance = roundMoney(balance + n(r['amount_in']) - n(r['amount_out'])),
          },
      ],
    );
  }

  /// Daily cash book (يومية الخزنة): every box's opening / in / out /
  /// closing on [date], and all movements of the day.
  Future<({List<DbRow> boxes, List<DbRow> rows})> cashDay(String date) async {
    final boxes = await db.q('''
SELECT c.id, c.name,
  IFNULL((SELECT SUM(amount_in) - SUM(amount_out) FROM v_cash_ledger WHERE cash_box_id = c.id AND date < ?), 0) AS opening,
  IFNULL((SELECT SUM(amount_in) FROM v_cash_ledger WHERE cash_box_id = c.id AND date = ?), 0) AS amount_in,
  IFNULL((SELECT SUM(amount_out) FROM v_cash_ledger WHERE cash_box_id = c.id AND date = ?), 0) AS amount_out
FROM cash_boxes c WHERE c.deleted = 0 ORDER BY c.name''', [date, date, date]);
    final rows = await db.q("$_cashDetail WHERE l.date = ? AND l.doc_type <> 'opening' ORDER BY l.created_at", [date]);
    return (
      boxes: [
        for (final b in boxes)
          {...b, 'closing': roundMoney(n(b['opening']) + n(b['amount_in']) - n(b['amount_out']))},
      ],
      rows: [for (final r in rows) {...r, 'title': docLabel(s(r['doc_type']), s(r['kind']))}],
    );
  }

  // ---------------------------------------------------------------- vouchers

  Future<List<DbRow>> vouchers({
    List<String>? kinds,
    String? from,
    String? to,
    String? partyId,
    String? invoiceId,
    String search = '',
  }) {
    final where = <String>['v.deleted = 0'];
    final args = <Object?>[];
    if (kinds != null && kinds.isNotEmpty) {
      where.add('v.kind IN (${List.filled(kinds.length, '?').join(', ')})');
      args.addAll(kinds);
    }
    void add(String cond, Object? v) {
      if (v == null) return;
      where.add(cond);
      args.add(v);
    }

    add('v.date >= ?', from);
    add('v.date <= ?', to);
    add('v.party_id = ?', partyId);
    add('v.invoice_id = ?', invoiceId);
    if (search.trim().isNotEmpty) {
      where.add('(${arFoldSql('p.name')} LIKE ? OR ${arFoldSql('v.category')} LIKE ? OR '
          '${arFoldSql('v.notes')} LIKE ? OR ${arFoldSql('v.handled_by')} LIKE ? OR v.number LIKE ?)');
      final q = '%${arFold(search)}%';
      args.addAll([q, q, q, q, '%${normalizeDigits(search.trim())}%']);
    }
    return db.q('''
SELECT v.*, p.name AS party_name, p.phone AS party_phone, c.name AS box_name, c2.name AS to_box_name,
  i.number AS invoice_number
FROM vouchers v
LEFT JOIN parties p ON p.id = v.party_id
LEFT JOIN cash_boxes c ON c.id = v.cash_box_id
LEFT JOIN cash_boxes c2 ON c2.id = v.to_cash_box_id
LEFT JOIN invoices i ON i.id = v.invoice_id
WHERE ${where.join(' AND ')}
ORDER BY v.date DESC, v.created_at DESC''', args);
  }

  Future<DbRow?> voucher(String id) => db.q1('''
SELECT v.*, p.name AS party_name, p.phone AS party_phone, c.name AS box_name, c2.name AS to_box_name,
  i.number AS invoice_number
FROM vouchers v
LEFT JOIN parties p ON p.id = v.party_id
LEFT JOIN cash_boxes c ON c.id = v.cash_box_id
LEFT JOIN cash_boxes c2 ON c2.id = v.to_cash_box_id
LEFT JOIN invoices i ON i.id = v.invoice_id
WHERE v.id = ?''', [id]);

  Future<String> saveVoucher(DbRow values, {String? id}) => db.write((w) async {
        if (id == null) {
          values['number'] = await w.nextNumber('vouchers', s(values['kind']));
          return w.insert('vouchers', values);
        }
        await w.update('vouchers', id, values);
        return id;
      });

  Future<void> deleteVoucher(String id) => db.write((w) => w.delete('vouchers', id));

  Future<List<String>> expenseCategories() async {
    final rows = await db.q(
      "SELECT DISTINCT category FROM vouchers WHERE kind = 'expense' AND deleted = 0 AND IFNULL(category, '') <> '' ORDER BY category",
    );
    final used = rows.map((r) => s(r['category'])).toList();
    return {...used, ...defaultExpenseCategories}.toList();
  }

  // ---------------------------------------------------------------- settings

  /// Settings of the open division, keys without the division prefix.
  Future<Map<String, String>> settings() async {
    final prefix = '${db.division}:';
    final rows = await db.q('SELECT id, value FROM app_settings WHERE deleted = 0 AND id LIKE ?', ['$prefix%']);
    return {for (final r in rows) s(r['id']).substring(prefix.length): s(r['value'])};
  }

  Future<void> saveSettings(Map<String, String> values) => db.write((w) async {
        for (final e in values.entries) {
          final id = '${db.division}:${e.key}';
          final exists = await w.ex.rawQuery('SELECT 1 FROM app_settings WHERE id = ?', [id]);
          if (exists.isEmpty) {
            await w.insert('app_settings', {'id': id, 'value': e.value});
          } else {
            await w.update('app_settings', id, {'value': e.value, 'deleted': false});
          }
        }
      });
}
