import '../core/db/app_db.dart';
import '../core/util/format.dart';

/// Crops division: crop types, warehouses (shonas), weighings, stock, profit.
class CropsRepo {
  CropsRepo(this.db);

  final AppDb db;

  // ---------------------------------------------------------------- crops

  Future<List<DbRow>> crops({bool activeOnly = true}) => db.q('''
SELECT c.*,
  IFNULL((SELECT SUM(qty) FROM v_crop_moves WHERE item_id = c.id), 0) AS stock_kg,
  IFNULL(cc.cost_per_kg, 0) AS cost_per_kg
FROM crops c LEFT JOIN v_crop_cost cc ON cc.crop_id = c.id
WHERE c.deleted = 0 ${activeOnly ? 'AND c.active = 1' : ''}
ORDER BY c.name''');

  Future<String> saveCrop(DbRow values, {String? id}) => db.write((w) async {
        if (id == null) return w.insert('crops', values);
        await w.update('crops', id, values);
        return id;
      });

  /// Today's buying / selling price per unit.
  Future<void> saveCropPrices(String id, double buy, double sell) =>
      db.write((w) => w.update('crops', id, {'buy_price': buy, 'sell_price': sell}));

  Future<String?> deleteCrop(String id) async {
    final used = await db.val('SELECT COUNT(*) FROM v_crop_moves WHERE item_id = ?', [id]);
    if (used > 0) return 'لا يمكن الحذف: عليه حركات. ممكن توقفه بدل الحذف.';
    await db.write((w) => w.delete('crops', id));
    return null;
  }

  // ---------------------------------------------------------------- warehouses

  Future<List<DbRow>> warehouses({bool activeOnly = true}) => db.q('''
SELECT * FROM warehouses WHERE deleted = 0 ${activeOnly ? 'AND active = 1' : ''}
ORDER BY name''');

  Future<String> saveWarehouse(DbRow values, {String? id}) => db.write((w) async {
        if (id == null) return w.insert('warehouses', values);
        await w.update('warehouses', id, values);
        return id;
      });

  Future<String?> deleteWarehouse(String id) async {
    final used = await db.val('''
SELECT (SELECT COUNT(*) FROM v_crop_moves WHERE warehouse_id = ?) + (SELECT COUNT(*) FROM v_product_moves WHERE warehouse_id = ?)''',
        [id, id]);
    if (used > 0) return 'لا يمكن الحذف: عليه حركات. ممكن توقفه بدل الحذف.';
    await db.write((w) => w.delete('warehouses', id));
    return null;
  }

  // ---------------------------------------------------------------- stock

  /// Stock per crop and warehouse (kg).
  Future<List<DbRow>> stockByWarehouse({String? cropId}) => db.q('''
SELECT m.item_id AS crop_id, m.warehouse_id, SUM(m.qty) AS kg,
  c.name AS crop_name, c.unit_name, c.kg_per_unit, w.name AS warehouse_name
FROM v_crop_moves m
JOIN crops c ON c.id = m.item_id
LEFT JOIN warehouses w ON w.id = m.warehouse_id
WHERE (? IS NULL OR m.item_id = ?)
GROUP BY m.item_id, m.warehouse_id
HAVING ABS(SUM(m.qty)) > 0.0005
ORDER BY c.name, w.name''', [cropId, cropId]);

  Future<double> stockAt(String cropId, String warehouseId, {String? excludeDocId}) => db.val('''
SELECT IFNULL(SUM(qty), 0) FROM v_crop_moves
WHERE item_id = ? AND warehouse_id = ? AND doc_id IS NOT ?''', [cropId, warehouseId, excludeDocId]);

  Future<double> costPerKg(String cropId) =>
      db.val('SELECT IFNULL(cost_per_kg, 0) FROM v_crop_cost WHERE crop_id = ?', [cropId]);

  Future<List<DbRow>> cropMoves(String cropId) => db.q('''
SELECT m.*, p.name AS party_name, w.name AS warehouse_name
FROM v_crop_moves m
LEFT JOIN parties p ON p.id = m.party_id
LEFT JOIN warehouses w ON w.id = m.warehouse_id
WHERE m.item_id = ?
ORDER BY m.date DESC, m.created_at DESC''', [cropId]);

  // ---------------------------------------------------------------- trades

  static const _tradeSelect = '''
SELECT t.*, p.name AS party_name, p.phone AS party_phone, c.name AS crop_name,
  w.name AS warehouse_name, b.name AS box_name
FROM crop_trades t
LEFT JOIN parties p ON p.id = t.party_id
LEFT JOIN crops c ON c.id = t.crop_id
LEFT JOIN warehouses w ON w.id = t.warehouse_id
LEFT JOIN cash_boxes b ON b.id = t.cash_box_id''';

  Future<List<DbRow>> trades({
    String? kind,
    String? from,
    String? to,
    String? partyId,
    String? cropId,
    String search = '',
    int? limit,
  }) {
    final where = <String>['t.deleted = 0'];
    final args = <Object?>[];
    void add(String cond, Object? v) {
      if (v == null) return;
      where.add(cond);
      args.add(v);
    }

    add('t.kind = ?', kind);
    add('t.date >= ?', from);
    add('t.date <= ?', to);
    add('t.party_id = ?', partyId);
    add('t.crop_id = ?', cropId);
    if (search.trim().isNotEmpty) {
      where.add('(${arFoldSql('p.name')} LIKE ? OR t.number LIKE ? OR IFNULL(t.ticket_no, \'\') LIKE ?)');
      final d = '%${normalizeDigits(search.trim())}%';
      args.addAll(['%${arFold(search)}%', d, d]);
    }
    return db.q(
      '$_tradeSelect WHERE ${where.join(' AND ')} ORDER BY t.date DESC, t.created_at DESC'
      '${limit != null ? ' LIMIT $limit' : ''}',
      args,
    );
  }

  Future<DbRow?> trade(String id) => db.q1('$_tradeSelect WHERE t.id = ?', [id]);

  Future<String> saveTrade(DbRow values, {String? id}) => db.write((w) async {
        if (id == null) {
          values['number'] = await w.nextNumber('crop_trades', s(values['kind']));
          return w.insert('crop_trades', values);
        }
        await w.update('crop_trades', id, values);
        return id;
      });

  Future<void> deleteTrade(String id) => db.write((w) => w.delete('crop_trades', id));

  // ---------------------------------------------------------------- stock moves

  Future<String> saveStockMove(DbRow values, {String? id}) => db.write((w) async {
        if (id == null) {
          values['number'] = await w.nextNumber('stock_moves', s(values['kind']));
          return w.insert('stock_moves', values);
        }
        await w.update('stock_moves', id, values);
        return id;
      });

  Future<void> deleteStockMove(String id) => db.write((w) => w.delete('stock_moves', id));

  /// Stock count (جرد): one adjustment per item whose counted quantity
  /// differs from the system quantity. Returns how many were adjusted.
  Future<int> saveStocktake({
    required String itemType,
    required String warehouseId,
    required String date,
    required List<({String itemId, double system, double counted})> lines,
  }) =>
      db.write((w) async {
        var count = 0;
        for (final l in lines) {
          final diff = round3(l.counted - l.system);
          if (diff.abs() < 0.0005) continue;
          await w.insert('stock_moves', {
            'kind': 'adjust',
            'number': await w.nextNumber('stock_moves', 'adjust'),
            'date': date,
            'item_type': itemType,
            'item_id': l.itemId,
            'warehouse_id': warehouseId,
            'qty': diff,
            'notes': 'جرد: الموجود ${qty(l.counted)} بدل ${qty(l.system)}',
          });
          count++;
        }
        return count;
      });

  Future<List<DbRow>> stockMoves(String itemType) => db.q('''
SELECT m.*, w.name AS warehouse_name, w2.name AS to_warehouse_name,
  COALESCE(c.name, pr.name) AS item_name, c.unit_name, c.kg_per_unit
FROM stock_moves m
LEFT JOIN warehouses w ON w.id = m.warehouse_id
LEFT JOIN warehouses w2 ON w2.id = m.to_warehouse_id
LEFT JOIN crops c ON c.id = m.item_id
LEFT JOIN products pr ON pr.id = m.item_id
WHERE m.deleted = 0 AND m.item_type = ?
ORDER BY m.date DESC, m.created_at DESC''', [itemType]);

  // ---------------------------------------------------------------- reports

  /// Per crop: bought, sold, cost of what was sold and gross profit.
  Future<List<DbRow>> profitByCrop(String from, String to) async {
    final rows = await db.q('''
SELECT c.id, c.name, c.unit_name, c.kg_per_unit, IFNULL(cc.cost_per_kg, 0) AS cost_per_kg,
  IFNULL(SUM(CASE WHEN t.kind = 'purchase' THEN t.stock_kg END), 0) AS bought_kg,
  IFNULL(SUM(CASE WHEN t.kind = 'purchase' THEN t.party_total + t.freight + t.loading + t.other_expenses END), 0) AS bought_cost,
  IFNULL(SUM(CASE WHEN t.kind = 'sale' THEN t.stock_kg END), 0) AS sold_kg,
  IFNULL(SUM(CASE WHEN t.kind = 'sale' THEN t.net_kg END), 0) AS sold_net_kg,
  IFNULL(SUM(CASE WHEN t.kind = 'sale' THEN t.party_total - t.freight - t.loading - t.other_expenses END), 0) AS sales_net
FROM crops c
LEFT JOIN v_crop_cost cc ON cc.crop_id = c.id
LEFT JOIN crop_trades t ON t.crop_id = c.id AND t.deleted = 0 AND t.date >= ? AND t.date <= ?
WHERE c.deleted = 0
GROUP BY c.id
ORDER BY c.name''', [from, to]);
    return [
      for (final r in rows)
        if (n(r['bought_kg']) != 0 || n(r['sold_kg']) != 0)
          {
            ...r,
            'cogs': roundMoney(n(r['sold_kg']) * n(r['cost_per_kg'])),
            'profit': roundMoney(n(r['sales_net']) - n(r['sold_kg']) * n(r['cost_per_kg'])),
          },
    ];
  }

  Future<double> stockValue() => db.val('''
SELECT IFNULL(SUM(s.kg * IFNULL(cc.cost_per_kg, 0)), 0)
FROM (SELECT item_id, SUM(qty) AS kg FROM v_crop_moves GROUP BY item_id) s
LEFT JOIN v_crop_cost cc ON cc.crop_id = s.item_id
WHERE s.kg > 0''');
}
