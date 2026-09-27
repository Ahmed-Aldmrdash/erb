import '../core/db/app_db.dart';
import '../core/util/format.dart';

/// Who added, changed or deleted what: every row keeps the name typed at
/// login by whoever created it and whoever changed it last.
class ActivityRepo {
  ActivityRepo(this.db);

  final AppDb db;

  static const _union = '''
SELECT 'crop_trade' AS doc_type, id AS doc_id, kind, number, date, party_total AS amount, party_id,
  created_at, updated_at, created_by_name, updated_by_name, deleted FROM crop_trades
UNION ALL SELECT 'invoice', id, kind, number, date, grand_total, party_id,
  created_at, updated_at, created_by_name, updated_by_name, deleted FROM invoices
UNION ALL SELECT 'voucher', id, kind, number, date, amount, party_id,
  created_at, updated_at, created_by_name, updated_by_name, deleted FROM vouchers
UNION ALL SELECT 'stock_move', id, kind, number, date, qty, NULL,
  created_at, updated_at, created_by_name, updated_by_name, deleted FROM stock_moves
UNION ALL SELECT 'note', id, kind, NULL, due_date, amount, NULL,
  created_at, updated_at, created_by_name, updated_by_name, deleted FROM notes
UNION ALL SELECT 'party', id, kind, NULL, NULL, opening_balance, id,
  created_at, updated_at, created_by_name, updated_by_name, deleted FROM parties
UNION ALL SELECT 'product', id, NULL, NULL, NULL, retail_price, NULL,
  created_at, updated_at, created_by_name, updated_by_name, deleted FROM products''';

  Future<List<DbRow>> recent({String person = '', int limit = 300}) async {
    final rows = await db.q('''
SELECT a.*, p.name AS party_name, n.body AS note_body, pr.name AS product_name
FROM ($_union) a
LEFT JOIN parties p ON p.id = a.party_id
LEFT JOIN notes n ON a.doc_type = 'note' AND n.id = a.doc_id
LEFT JOIN products pr ON a.doc_type = 'product' AND pr.id = a.doc_id
ORDER BY a.updated_at DESC LIMIT $limit''');
    final list = [
      for (final r in rows)
        {
          ...r,
          // added | edited | deleted
          'action': n(r['deleted']) == 1
              ? 'deleted'
              : (s(r['created_at']) == s(r['updated_at']) ? 'added' : 'edited'),
          'who': n(r['deleted']) == 1 || s(r['created_at']) != s(r['updated_at'])
              ? s(r['updated_by_name'])
              : s(r['created_by_name']),
        },
    ];
    if (person.isEmpty) return list;
    return list.where((r) => r['who'] == person).toList();
  }

  Future<List<String>> people() async {
    final rows = await db.q('''
SELECT DISTINCT name FROM (SELECT created_by_name AS name FROM ($_union) UNION SELECT updated_by_name FROM ($_union))
WHERE IFNULL(name, '') <> '' ORDER BY name''');
    return rows.map((r) => s(r['name'])).toList();
  }
}
