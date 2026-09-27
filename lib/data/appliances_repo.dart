import '../core/db/app_db.dart';
import 'barcode.dart';
import '../core/util/format.dart';
import '../core/util/uuid.dart';
import 'calc.dart';

class InvoiceLineDraft {
  InvoiceLineDraft({
    required this.productId,
    required this.name,
    required this.qty,
    required this.price,
    this.notes = '',
    this.unit = '',
  });

  String productId;
  String name;
  String unit;
  double qty;
  double price;
  String notes;

  double get total => roundMoney(qty * price);
}

class InstallmentRow {
  InstallmentRow({required this.status, required this.invoice});

  final InstallmentStatus status;

  /// Invoice with party_name / party_phone.
  final DbRow invoice;
}

/// A product whose purchase price changed on a purchase invoice, with the
/// selling prices that follow it. The user sees and can change these before
/// the invoice is saved.
class PriceUpdate {
  PriceUpdate({
    required this.productId,
    required this.name,
    required this.oldCost,
    required this.cost,
    required this.oldRetail,
    required this.retail,
    required this.oldWholesale,
    required this.wholesale,
  });

  final String productId;
  final String name;
  final double oldCost;
  final double cost;
  final double oldRetail;
  double retail;
  final double oldWholesale;
  double wholesale;

  bool get changesPrices =>
      (retail - oldRetail).abs() > 0.009 || (wholesale - oldWholesale).abs() > 0.009;
}

/// Selling a piece the warehouse does not have.
class OutOfStock implements Exception {
  OutOfStock(this.items);

  /// One line per product: "ثلاجة: المتاح 2".
  final List<String> items;

  @override
  String toString() => 'مينفعش تبيع أصناف مش موجودة في المخزن:\n${items.join('\n')}';
}

/// Household tools & appliances division: products, invoices, installments.
class AppliancesRepo {
  AppliancesRepo(this.db);

  final AppDb db;

  // ---------------------------------------------------------------- products

  static const _productSelect = '''
SELECT p.*, IFNULL(st.qty, 0) AS stock, IFNULL(pc.unit_cost, p.cost_price) AS unit_cost
FROM products p
LEFT JOIN (SELECT item_id, SUM(qty) AS qty FROM v_product_moves GROUP BY item_id) st ON st.item_id = p.id
LEFT JOIN v_product_cost pc ON pc.product_id = p.id''';

  Future<List<DbRow>> products({String search = '', String? category, bool lowOnly = false, bool activeOnly = true, String? boughtBy}) async {
    final where = <String>['p.deleted = 0'];
    final args = <Object?>[];
    if (activeOnly) where.add('p.active = 1');
    if (category != null) {
      where.add('p.category = ?');
      args.add(category);
    }
    if (lowOnly) where.add('IFNULL(st.qty, 0) <= p.min_qty AND p.min_qty > 0');
    if (boughtBy != null) {
      where.add('p.id IN (SELECT product_id FROM v_lines l JOIN invoices i ON i.id = l.invoice_id WHERE i.party_id = ?)');
      args.add(boughtBy);
    }

    if (search.trim().isNotEmpty) {
      final qTrim = search.trim();
      final digits = normalizeDigits(qTrim);
      // 1. Try exact barcode/code match first
      if (digits.isNotEmpty) {
        final exact = await db.q('$_productSelect WHERE ${[...where, 'p.barcode = ?'].join(' AND ')}', [...args, digits]);
        if (exact.isNotEmpty) return exact;
      }
      // 2. Fallback to LIKE
      final q = '%${arFold(qTrim)}%';
      where.add('(${arFoldSql('p.name')} LIKE ? OR ${arFoldSql('p.brand')} LIKE ? OR '
          '${arFoldSql('p.model')} LIKE ? OR IFNULL(p.barcode, \'\') LIKE ?)');
      args.addAll([q, q, q, '%$digits%']);
    }
    return db.q('$_productSelect WHERE ${where.join(' AND ')} ORDER BY p.category, p.name', args);
  }

  Future<DbRow?> product(String id) => db.q1('$_productSelect WHERE p.id = ?', [id]);

  /// Active products with their stock in one warehouse (for a stock count).
  Future<List<DbRow>> productsAtWarehouse(String warehouseId, {String search = ''}) {
    final args = <Object?>[warehouseId];
    var extra = '';
    if (search.trim().isNotEmpty) {
      final q = '%${arFold(search)}%';
      extra = 'AND (${arFoldSql('p.name')} LIKE ? OR ${arFoldSql('p.model')} LIKE ? OR IFNULL(p.barcode, \'\') LIKE ?)';
      args.addAll([q, q, '%${normalizeDigits(search.trim())}%']);
    }
    return db.q('''
SELECT p.id, p.name, p.brand, p.model, p.unit, IFNULL(st.qty, 0) AS stock
FROM products p
LEFT JOIN (SELECT item_id, SUM(qty) AS qty FROM v_product_moves WHERE warehouse_id = ? GROUP BY item_id) st ON st.item_id = p.id
WHERE p.deleted = 0 AND p.active = 1 $extra
ORDER BY p.category, p.name''', args);
  }

  Future<DbRow?> productByBarcode(String code) {
    final c = normalizeDigits(code.trim());
    if (c.isEmpty) return Future.value(null);
    return db.q1('$_productSelect WHERE p.deleted = 0 AND p.barcode = ? LIMIT 1', [c]);
  }

  Future<List<String>> categories() async {
    final rows = await db.q(
      "SELECT DISTINCT category FROM products WHERE deleted = 0 AND IFNULL(category, '') <> '' ORDER BY category",
    );
    return rows.map((r) => s(r['category'])).toList();
  }

  Future<List<String>> brands() async {
    final rows = await db.q(
      "SELECT DISTINCT brand FROM products WHERE deleted = 0 AND IFNULL(brand, '') <> '' ORDER BY brand",
    );
    return rows.map((r) => s(r['brand'])).toList();
  }

  Future<String> saveProduct(DbRow values, {String? id}) => db.write((w) async {
        if (id == null) return w.insert('products', values);
        await w.update('products', id, values);
        return id;
      });

  Future<String?> deleteProduct(String id) async {
    final used = await db.val('SELECT COUNT(*) FROM v_product_moves WHERE item_id = ?', [id]);
    if (used > 0) return 'لا يمكن الحذف: عليه حركات. ممكن توقفه بدل الحذف.';
    await db.write((w) => w.delete('products', id));
    return null;
  }

  /// Auto-generates the next product code: max existing numeric barcode + 1.
  /// A free product number: four random digits, so every number is the same
  /// length. Numbers of deleted products count as taken too — a printed label
  /// still stuck on a box must never point at another product.
  Future<String> nextProductCode() async {
    final rows = await db.q("SELECT barcode FROM products WHERE IFNULL(barcode, '') <> ''");
    return ProductCode.newCode({for (final r in rows) s(r['barcode'])});
  }

  /// Gives a number to every product that has none, and (with [unify]) a new
  /// one to the products whose number is shorter than the rest, so all the
  /// numbers read the same. Returns how many products got a number.
  Future<int> codeAllProducts({bool unify = false}) async {
    final where = unify
        ? "IFNULL(barcode, '') = '' OR (barcode GLOB '[0-9]*' AND LENGTH(barcode) < ${ProductCode.digits})"
        : "IFNULL(barcode, '') = ''";
    final rows = await db.q('SELECT id FROM products WHERE deleted = 0 AND ($where) ORDER BY created_at');
    for (final r in rows) {
      await saveProduct({'barcode': await nextProductCode()}, id: s(r['id']));
    }
    return rows.length;
  }

  /// How many products still need a number, and how many carry a short one
  /// from an older version.
  Future<({int missing, int short})> productCodeState() async {
    final r = await db.q1('''
SELECT
  SUM(CASE WHEN IFNULL(barcode, '') = '' THEN 1 ELSE 0 END) AS missing,
  SUM(CASE WHEN barcode GLOB '[0-9]*' AND LENGTH(barcode) < ${ProductCode.digits} THEN 1 ELSE 0 END) AS short
FROM products WHERE deleted = 0''');
    return (missing: ni(r?['missing']), short: ni(r?['short']));
  }

  /// The product behind something that was scanned or typed: the number on
  /// its own, a label (number + price), or the factory barcode of the box.
  ///
  /// [labelPrice] is the price printed on that label, so the showroom can be
  /// told when a box is still carrying an old price.
  Future<({DbRow product, double? labelPrice})?> productByScan(String scanned) async {
    final code = normalizeDigits(scanned.trim());
    if (code.isEmpty) return null;
    final exact = await productByBarcode(code);
    if (exact != null) return (product: exact, labelPrice: null);
    // A label: the product number with the price stuck on the end. The
    // longest number that fits wins, so a short old code cannot swallow a
    // scan that belongs to a longer one.
    final row = await db.q1('''
$_productSelect WHERE p.deleted = 0 AND IFNULL(p.barcode, '') <> ''
  AND ? LIKE p.barcode || '%'
  AND LENGTH(?) - LENGTH(p.barcode) BETWEEN 2 AND ${ProductCode.priceDigits + 1}
ORDER BY LENGTH(p.barcode) DESC LIMIT 1''', [code, code]);
    if (row == null) return null;
    return (product: row, labelPrice: ProductCode.priceOnLabel(code, s(row['barcode'])));
  }

  /// What the prices of a purchase invoice's products would become: the cost
  /// is the price on the invoice, and every selling price moves by the same
  /// ratio, rounded up to [step].
  Future<List<PriceUpdate>> suggestPriceUpdates(
    List<InvoiceLineDraft> lines, {
    double step = 10,
    double marginPct = 0,
  }) async {
    final out = <PriceUpdate>[];
    for (final l in lines) {
      if (l.price <= 0) continue;
      final p = await db.q1('SELECT name, cost_price, retail_price, wholesale_price FROM products WHERE id = ?', [l.productId]);
      if (p == null) continue;
      final oldCost = n(p['cost_price']);
      final oldRetail = n(p['retail_price']);
      final oldWholesale = n(p['wholesale_price']);
      final costChanged = (oldCost - l.price).abs() > 0.009;
      final u = PriceUpdate(
        productId: l.productId,
        name: s(p['name']),
        oldCost: oldCost,
        cost: l.price,
        oldRetail: oldRetail,
        retail: priceFollowingCost(
          oldCost: oldCost,
          newCost: l.price,
          oldPrice: oldRetail,
          step: step,
          marginPct: marginPct,
        ),
        oldWholesale: oldWholesale,
        wholesale: priceFollowingCost(
          oldCost: oldCost,
          newCost: l.price,
          oldPrice: oldWholesale,
          step: step,
          marginPct: marginPct,
          fillEmpty: false,
        ),
      );
      if (costChanged || u.changesPrices) out.add(u);
    }
    return out;
  }

  /// Changes prices without touching anything else (the quick price sheet).
  Future<void> setPrices(String productId, {double? cost, double? retail, double? wholesale}) => saveProduct({
        'cost_price': ?cost,
        'retail_price': ?retail,
        'wholesale_price': ?wholesale,
      }, id: productId);

  Future<List<DbRow>> productStockByWarehouse(String productId) => db.q('''
SELECT m.warehouse_id, w.name AS warehouse_name, SUM(m.qty) AS qty
FROM v_product_moves m LEFT JOIN warehouses w ON w.id = m.warehouse_id
WHERE m.item_id = ?
GROUP BY m.warehouse_id
HAVING ABS(SUM(m.qty)) > 0.0005''', [productId]);

  Future<double> stockAt(String productId, String? warehouseId, {String? excludeInvoiceId}) => db.val('''
SELECT IFNULL(SUM(qty), 0) FROM v_product_moves
WHERE item_id = ? AND (? IS NULL OR warehouse_id = ?) AND doc_id IS NOT ?''',
      [productId, warehouseId, warehouseId, excludeInvoiceId]);

  Future<List<DbRow>> productMoves(String productId) => db.q('''
SELECT m.*, p.name AS party_name, w.name AS warehouse_name,
  (SELECT l.price FROM v_lines l WHERE l.invoice_id = m.doc_id AND l.product_id = m.item_id LIMIT 1) AS price
FROM v_product_moves m
LEFT JOIN parties p ON p.id = m.party_id
LEFT JOIN warehouses w ON w.id = m.warehouse_id
WHERE m.item_id = ?
ORDER BY m.date DESC, m.created_at DESC''', [productId]);

  Future<double> stockValue() => db.val('''
SELECT IFNULL(SUM(st.qty * IFNULL(pc.unit_cost, p.cost_price)), 0)
FROM products p
JOIN (SELECT item_id, SUM(qty) AS qty FROM v_product_moves GROUP BY item_id) st ON st.item_id = p.id
LEFT JOIN v_product_cost pc ON pc.product_id = p.id
WHERE p.deleted = 0 AND st.qty > 0''');

  Future<int> lowStockCount() async => (await db.val('''
SELECT COUNT(*) FROM products p
LEFT JOIN (SELECT item_id, SUM(qty) AS qty FROM v_product_moves GROUP BY item_id) st ON st.item_id = p.id
WHERE p.deleted = 0 AND p.active = 1 AND p.min_qty > 0 AND IFNULL(st.qty, 0) <= p.min_qty''')).toInt();

  // ---------------------------------------------------------------- invoices

  static const _invoiceSelect = '''
SELECT i.*, p.name AS party_name, p.phone AS party_phone, p.address AS party_address,
  p.national_id AS party_national_id, w.name AS warehouse_name, b.name AS box_name,
  IFNULL((SELECT SUM(amount) FROM vouchers v WHERE v.invoice_id = i.id AND v.deleted = 0
    AND v.kind = CASE WHEN i.kind IN ('sale', 'purchase_return') THEN 'receipt' ELSE 'payment' END), 0) AS collected,
  (SELECT COUNT(*) FROM v_lines l WHERE l.invoice_id = i.id) AS line_count,
  (SELECT SUM(debit) - SUM(credit) FROM v_party_ledger WHERE party_id = i.party_id) AS party_balance
FROM invoices i
LEFT JOIN parties p ON p.id = i.party_id
LEFT JOIN warehouses w ON w.id = i.warehouse_id
LEFT JOIN cash_boxes b ON b.id = i.cash_box_id''';

  Future<List<DbRow>> invoices({
    List<String>? kinds,
    String? paymentType,
    String? from,
    String? to,
    String? partyId,
    String search = '',
    int? limit,

    /// Only what this person wrote, for a cashier who may see his own sales.
    String? byPerson,
  }) {
    final where = <String>['i.deleted = 0'];
    final args = <Object?>[];
    if (kinds != null && kinds.isNotEmpty) {
      where.add('i.kind IN (${List.filled(kinds.length, '?').join(', ')})');
      args.addAll(kinds);
    }
    void add(String cond, Object? v) {
      if (v == null) return;
      where.add(cond);
      args.add(v);
    }

    add('i.payment_type = ?', paymentType);
    add('i.created_by_name = ?', byPerson);
    add('i.date >= ?', from);
    add('i.date <= ?', to);
    add('i.party_id = ?', partyId);
    if (search.trim().isNotEmpty) {
      where.add('(${arFoldSql('p.name')} LIKE ? OR ${arFoldSql('i.customer_name')} LIKE ? OR i.number LIKE ?)');
      final q = '%${arFold(search)}%';
      args.addAll([q, q, '%${normalizeDigits(search.trim())}%']);
    }
    return db.q(
      '$_invoiceSelect WHERE ${where.join(' AND ')} ORDER BY i.date DESC, i.created_at DESC'
      '${limit != null ? ' LIMIT $limit' : ''}',
      args,
    );
  }

  Future<DbRow?> invoice(String id) => db.q1('$_invoiceSelect WHERE i.id = ?', [id]);

  /// What is still open on an invoice row from [invoices] / [invoice].
  /// Payments linked to the invoice are subtracted; general payments on the
  /// account are respected too, because the invoice can never be more open
  /// than the whole account.
  static double remainingOf(DbRow inv) {
    final linked = roundMoney(n(inv['grand_total']) - n(inv['paid_amount']) - n(inv['collected']));
    if (inv['payment_type'] == 'cash' || inv['party_id'] == null || linked <= 0) return linked < 0 ? 0 : linked;
    final kind = s(inv['kind']);
    final balance = n(inv['party_balance']);
    final owed = kind == 'sale' || kind == 'purchase_return' ? balance : -balance;
    return roundMoney(owed <= 0 ? 0 : (owed < linked ? owed : linked));
  }

  Future<List<DbRow>> invoiceLines(String invoiceId) => db.q('''
SELECT l.*, p.name AS product_name, p.unit, p.model, p.brand
FROM v_lines l LEFT JOIN products p ON p.id = l.product_id
WHERE l.invoice_id = ?
ORDER BY l.sort''', [invoiceId]);

  /// Saves header, lines and installment schedule in one transaction. Every
  /// save gets a new revision id; lines of older revisions stop counting.
  ///
  /// [priceUpdates] are the new purchase / selling prices the user confirmed
  /// for the products of a purchase invoice (see [suggestPriceUpdates]).
  /// Selling a product the warehouse does not have throws [OutOfStock].
  Future<String> saveInvoice({
    required DbRow header,
    required List<InvoiceLineDraft> lines,
    List<PlannedInstallment> schedule = const [],
    List<PriceUpdate> priceUpdates = const [],
    String? id,
  }) =>
      db.write((w) async {
        final kind = s(header['kind']);
        // The last word on stock: two phones can sell the same piece offline,
        // and the screens check before the user reaches this point.
        if (kind == 'sale' || kind == 'purchase_return') {
          final short = <String>[];
          for (final l in lines) {
            if (l.qty <= 0) continue;
            final rows = await w.ex.rawQuery('''
SELECT IFNULL(SUM(qty), 0) AS available FROM v_product_moves
WHERE item_id = ? AND (? IS NULL OR warehouse_id = ?) AND doc_id IS NOT ?''',
                [l.productId, header['warehouse_id'], header['warehouse_id'], id]);
            final available = n(rows.first['available']);
            if (l.qty > available + 0.0001) short.add('${l.name}: المتاح ${qty(available)}');
          }
          if (short.isNotEmpty) throw OutOfStock(short);
        }
        final rev = newId();
        header['rev'] = rev;
        final String invoiceId;
        if (id == null) {
          header['number'] = await w.nextNumber('invoices', s(header['kind']));
          invoiceId = await w.insert('invoices', header);
        } else {
          invoiceId = id;
          await w.update('invoices', id, header);
          await w.deleteWhere('invoice_lines', 'invoice_id = ?', [id]);
          await w.deleteWhere('installments', 'invoice_id = ?', [id]);
        }
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          await w.insert('invoice_lines', {
            'invoice_id': invoiceId,
            'rev': rev,
            'sort': i,
            'product_id': l.productId,
            'qty': l.qty,
            'price': l.price,
            'total': l.total,
            'notes': l.notes,
          });
        }
        for (final it in schedule) {
          await w.insert('installments', {
            'invoice_id': invoiceId,
            'rev': rev,
            'party_id': header['party_id'],
            'seq': it.seq,
            'due_date': dateStr(it.dueDate),
            'amount': it.amount,
          });
        }
        // The new prices the user confirmed on a purchase invoice.
        for (final u in priceUpdates) {
          await w.update('products', u.productId, {
            'cost_price': u.cost,
            'retail_price': u.retail,
            'wholesale_price': u.wholesale,
          });
        }

        return invoiceId;
      });

  Future<void> deleteInvoice(String id) => db.write((w) async {
        await w.delete('invoices', id);
        await w.deleteWhere('invoice_lines', 'invoice_id = ?', [id]);
        await w.deleteWhere('installments', 'invoice_id = ?', [id]);
      });

  // ---------------------------------------------------------------- installments

  Future<List<InstallmentStatus>> invoiceInstallments(String invoiceId) async {
    final inv = await db.q1(
      "SELECT IFNULL((SELECT SUM(amount) FROM vouchers WHERE invoice_id = ? AND deleted = 0 AND kind = 'receipt'), 0) AS collected",
      [invoiceId],
    );
    final rows = await db.q('SELECT * FROM v_installments WHERE invoice_id = ? ORDER BY seq', [invoiceId]);
    return allocateInstallments([
      for (final r in rows)
        (id: s(r['id']), seq: ni(r['seq']), dueDate: s(r['due_date']), amount: n(r['amount'])),
    ], n(inv?['collected']));
  }

  /// Unpaid installments of all live installment invoices, oldest first.
  Future<List<InstallmentRow>> openInstallments({String? until, String? partyId}) async {
    final partyFilter = partyId != null ? ' AND i.party_id = "$partyId"' : '';
    final invoices = await db.q('''
SELECT i.id, i.number, i.party_id, i.grand_total, i.paid_amount, i.date,
  p.name AS party_name, p.phone AS party_phone,
  IFNULL((SELECT SUM(amount) FROM vouchers v WHERE v.invoice_id = i.id AND v.deleted = 0 AND v.kind = 'receipt'), 0) AS collected
FROM invoices i LEFT JOIN parties p ON p.id = i.party_id
WHERE i.deleted = 0 AND i.kind = 'sale' AND i.payment_type = 'installment'$partyFilter ''');
    final all = await db.q('SELECT * FROM v_installments ORDER BY invoice_id, seq');
    final byInvoice = <String, List<DbRow>>{};
    for (final r in all) {
      byInvoice.putIfAbsent(s(r['invoice_id']), () => []).add(r);
    }
    final result = <InstallmentRow>[];
    for (final inv in invoices) {
      final items = byInvoice[s(inv['id'])] ?? const [];
      final statuses = allocateInstallments([
        for (final r in items)
          (id: s(r['id']), seq: ni(r['seq']), dueDate: s(r['due_date']), amount: n(r['amount'])),
      ], n(inv['collected']));
      for (final st in statuses) {
        if (st.remaining <= 0.009) continue;
        if (until != null && st.dueDate.compareTo(until) > 0) continue;
        result.add(InstallmentRow(status: st, invoice: inv));
      }
    }
    result.sort((a, b) => a.status.dueDate.compareTo(b.status.dueDate));
    return result;
  }

  // ---------------------------------------------------------------- reports

  Future<DbRow> salesSummary(String from, String to) async {
    final r = await db.q1('''
SELECT
  IFNULL(SUM(CASE WHEN kind = 'sale' THEN total END), 0) AS sales,
  IFNULL(SUM(CASE WHEN kind = 'sale_return' THEN total END), 0) AS returns,
  IFNULL(SUM(CASE WHEN kind = 'sale' THEN markup_amount END), 0) AS markup,
  IFNULL(SUM(CASE WHEN kind = 'purchase' THEN total END), 0) AS purchases,
  IFNULL(SUM(CASE WHEN kind = 'purchase_return' THEN total END), 0) AS purchase_returns,
  COUNT(CASE WHEN kind = 'sale' THEN 1 END) AS sales_count
FROM invoices WHERE deleted = 0 AND date >= ? AND date <= ?''', [from, to]);
    final cogs = await db.val('''
SELECT IFNULL(SUM(CASE WHEN l.inv_kind = 'sale' THEN l.qty ELSE -l.qty END * IFNULL(pc.unit_cost, 0)), 0)
FROM v_lines l LEFT JOIN v_product_cost pc ON pc.product_id = l.product_id
WHERE l.inv_kind IN ('sale', 'sale_return') AND l.inv_date >= ? AND l.inv_date <= ?''', [from, to]);
    return {...?r, 'cogs': roundMoney(cogs)};
  }

  Future<List<DbRow>> topProducts(String from, String to, {int limit = 10}) => db.q('''
SELECT l.product_id, p.name, SUM(l.qty) AS qty, SUM(l.total * l.disc_factor) AS amount
FROM v_lines l LEFT JOIN products p ON p.id = l.product_id
WHERE l.inv_kind = 'sale' AND l.inv_date >= ? AND l.inv_date <= ?
GROUP BY l.product_id ORDER BY amount DESC LIMIT $limit''', [from, to]);
}
