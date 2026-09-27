import 'schema.dart';

String _sqliteType(ColType t) => switch (t) {
      ColType.real => 'REAL',
      ColType.integer || ColType.boolean => 'INTEGER',
      _ => 'TEXT',
    };

String _sqliteLiteral(Object d) {
  if (d is bool) return d ? '1' : '0';
  if (d is num) return '$d';
  return "'${d.toString().replaceAll("'", "''")}'";
}

String localColumnSql(Col c) {
  if (c.name == 'id') return 'id TEXT PRIMARY KEY NOT NULL';
  final base = '${c.name} ${_sqliteType(c.type)}';
  return c.def == null ? base : '$base NOT NULL DEFAULT ${_sqliteLiteral(c.def!)}';
}

/// Rows written by the user get dirty = 1 until the server accepted them.
String createLocalTableSql(TableDef t) => 'CREATE TABLE IF NOT EXISTS ${t.name} (\n  '
    '${[...t.allCols.map(localColumnSql), 'dirty INTEGER NOT NULL DEFAULT 0'].join(',\n  ')}\n)';

const localIndexSql = [
  'CREATE INDEX IF NOT EXISTS ix_trades_party ON crop_trades(party_id)',
  'CREATE INDEX IF NOT EXISTS ix_trades_crop ON crop_trades(crop_id)',
  'CREATE INDEX IF NOT EXISTS ix_trades_date ON crop_trades(date)',
  'CREATE INDEX IF NOT EXISTS ix_invoices_party ON invoices(party_id)',
  'CREATE INDEX IF NOT EXISTS ix_invoices_date ON invoices(date)',
  'CREATE INDEX IF NOT EXISTS ix_lines_invoice ON invoice_lines(invoice_id)',
  'CREATE INDEX IF NOT EXISTS ix_lines_product ON invoice_lines(product_id)',
  'CREATE INDEX IF NOT EXISTS ix_inst_invoice ON installments(invoice_id)',
  'CREATE INDEX IF NOT EXISTS ix_vouchers_party ON vouchers(party_id)',
  'CREATE INDEX IF NOT EXISTS ix_vouchers_box ON vouchers(cash_box_id)',
  'CREATE INDEX IF NOT EXISTS ix_vouchers_invoice ON vouchers(invoice_id)',
  'CREATE INDEX IF NOT EXISTS ix_vouchers_date ON vouchers(date)',
  'CREATE INDEX IF NOT EXISTS ix_moves_item ON stock_moves(item_id)',
];

/// Every balance, stock level and cost is derived from the documents through
/// these views; nothing is stored as a running counter. That keeps the data
/// correct no matter in which order phones sync their records.
///
/// Views are dropped and recreated on every start, so they can change freely
/// between app versions.
const localViews = <String, String>{
  // Invoice lines that belong to the current revision of a live invoice.
  'v_lines': '''
SELECT l.*, i.kind AS inv_kind, i.date AS inv_date, i.number AS inv_number,
  i.warehouse_id AS warehouse_id, i.party_id AS party_id,
  CASE WHEN i.subtotal > 0 THEN i.total / i.subtotal ELSE 1 END AS disc_factor
FROM invoice_lines l
JOIN invoices i ON i.id = l.invoice_id AND IFNULL(i.rev, '') = IFNULL(l.rev, '')
WHERE l.deleted = 0 AND i.deleted = 0''',

  'v_installments': '''
SELECT s.*, i.number AS inv_number
FROM installments s
JOIN invoices i ON i.id = s.invoice_id AND IFNULL(i.rev, '') = IFNULL(s.rev, '')
WHERE s.deleted = 0 AND i.deleted = 0''',

  // debit: the party owes us more. credit: we owe the party more.
  'v_party_ledger': '''
SELECT id AS party_id, substr(IFNULL(created_at, ''), 1, 10) AS date, 'opening' AS doc_type,
  id AS doc_id, NULL AS number, 'opening' AS kind,
  CASE WHEN opening_balance > 0 THEN opening_balance ELSE 0 END AS debit,
  CASE WHEN opening_balance < 0 THEN -opening_balance ELSE 0 END AS credit,
  IFNULL(created_at, '') AS created_at, NULL AS notes
FROM parties WHERE deleted = 0 AND opening_balance <> 0
UNION ALL
SELECT party_id, date, 'crop_trade', id, number, kind,
  CASE WHEN kind = 'sale' THEN party_total ELSE paid_amount END,
  CASE WHEN kind = 'sale' THEN paid_amount ELSE party_total END,
  IFNULL(created_at, ''), notes
FROM crop_trades WHERE deleted = 0 AND party_id IS NOT NULL
UNION ALL
SELECT party_id, date, 'invoice', id, number, kind,
  CASE WHEN kind IN ('sale', 'purchase_return') THEN grand_total ELSE paid_amount END,
  CASE WHEN kind IN ('sale', 'purchase_return') THEN paid_amount ELSE grand_total END,
  IFNULL(created_at, ''), notes
FROM invoices WHERE deleted = 0 AND party_id IS NOT NULL
UNION ALL
SELECT party_id, date, 'voucher', id, number, kind,
  CASE WHEN kind IN ('payment', 'advance', 'debit_adj') THEN amount ELSE 0 END,
  CASE WHEN kind IN ('receipt', 'credit_adj') THEN amount ELSE 0 END,
  IFNULL(created_at, ''), notes
FROM vouchers
WHERE deleted = 0 AND party_id IS NOT NULL AND kind IN ('receipt', 'payment', 'advance', 'debit_adj', 'credit_adj')''',

  'v_cash_ledger': '''
SELECT id AS cash_box_id, substr(IFNULL(created_at, ''), 1, 10) AS date, 'opening' AS doc_type,
  id AS doc_id, NULL AS number, 'opening' AS kind, NULL AS party_id,
  CASE WHEN opening_balance > 0 THEN opening_balance ELSE 0 END AS amount_in,
  CASE WHEN opening_balance < 0 THEN -opening_balance ELSE 0 END AS amount_out,
  IFNULL(created_at, '') AS created_at, NULL AS notes
FROM cash_boxes WHERE deleted = 0 AND opening_balance <> 0
UNION ALL
SELECT cash_box_id, date, 'crop_trade', id, number, kind, party_id,
  CASE WHEN kind = 'sale' THEN paid_amount ELSE 0 END,
  (CASE WHEN kind = 'sale' THEN 0 ELSE paid_amount END) + freight + loading + other_expenses,
  IFNULL(created_at, ''), notes
FROM crop_trades WHERE deleted = 0 AND cash_box_id IS NOT NULL
UNION ALL
SELECT cash_box_id, date, 'invoice', id, number, kind, party_id,
  CASE WHEN kind IN ('sale', 'purchase_return') THEN paid_amount ELSE 0 END,
  CASE WHEN kind IN ('sale', 'purchase_return') THEN 0 ELSE paid_amount END,
  IFNULL(created_at, ''), notes
FROM invoices WHERE deleted = 0 AND cash_box_id IS NOT NULL
UNION ALL
SELECT cash_box_id, date, 'voucher', id, number, kind, party_id,
  CASE WHEN kind IN ('receipt', 'deposit') THEN amount ELSE 0 END,
  CASE WHEN kind IN ('payment', 'advance', 'expense', 'withdrawal', 'transfer') THEN amount ELSE 0 END,
  IFNULL(created_at, ''), notes
FROM vouchers WHERE deleted = 0 AND cash_box_id IS NOT NULL AND kind NOT IN ('debit_adj', 'credit_adj')
UNION ALL
SELECT to_cash_box_id, date, 'voucher', id, number, 'transfer_in', NULL, amount, 0,
  IFNULL(created_at, ''), notes
FROM vouchers WHERE deleted = 0 AND kind = 'transfer' AND to_cash_box_id IS NOT NULL''',

  // qty in kg, signed.
  'v_crop_moves': '''
SELECT crop_id AS item_id, warehouse_id, date, 'crop_trade' AS doc_type, id AS doc_id, number, kind,
  CASE WHEN kind = 'purchase' THEN stock_kg ELSE -stock_kg END AS qty,
  party_id, IFNULL(created_at, '') AS created_at
FROM crop_trades WHERE deleted = 0
UNION ALL
SELECT item_id, warehouse_id, date, 'stock_move', id, number, kind,
  CASE WHEN kind = 'transfer' THEN -qty ELSE qty END, NULL, IFNULL(created_at, '')
FROM stock_moves WHERE deleted = 0 AND item_type = 'crop'
UNION ALL
SELECT item_id, to_warehouse_id, date, 'stock_move', id, number, 'transfer_in', qty, NULL,
  IFNULL(created_at, '')
FROM stock_moves WHERE deleted = 0 AND item_type = 'crop' AND kind = 'transfer' ''',

  // qty in pieces, signed.
  'v_product_moves': '''
SELECT l.product_id AS item_id, i.warehouse_id, i.date, 'invoice' AS doc_type, i.id AS doc_id,
  i.number, i.kind,
  CASE WHEN i.kind IN ('purchase', 'sale_return') THEN l.qty ELSE -l.qty END AS qty,
  i.party_id, IFNULL(l.created_at, '') AS created_at
FROM invoice_lines l
JOIN invoices i ON i.id = l.invoice_id AND IFNULL(i.rev, '') = IFNULL(l.rev, '')
WHERE l.deleted = 0 AND i.deleted = 0
UNION ALL
SELECT item_id, warehouse_id, date, 'stock_move', id, number, kind,
  CASE WHEN kind = 'transfer' THEN -qty ELSE qty END, NULL, IFNULL(created_at, '')
FROM stock_moves WHERE deleted = 0 AND item_type = 'product'
UNION ALL
SELECT item_id, to_warehouse_id, date, 'stock_move', id, number, 'transfer_in', qty, NULL,
  IFNULL(created_at, '')
FROM stock_moves WHERE deleted = 0 AND item_type = 'product' AND kind = 'transfer' ''',

  // Weighted average purchase cost per kg, including our share of expenses.
  'v_crop_cost': '''
SELECT crop_id,
  SUM(party_total + freight + loading + other_expenses) AS cost,
  SUM(stock_kg) AS kg,
  CASE WHEN SUM(stock_kg) > 0
    THEN SUM(party_total + freight + loading + other_expenses) / SUM(stock_kg) ELSE 0 END AS cost_per_kg
FROM crop_trades WHERE deleted = 0 AND kind = 'purchase'
GROUP BY crop_id''',

  // Weighted average purchase cost per piece (invoice discount spread over lines).
  'v_product_cost': '''
SELECT p.id AS product_id,
  CASE WHEN IFNULL(c.qty, 0) > 0 THEN c.cost / c.qty ELSE p.cost_price END AS unit_cost
FROM products p
LEFT JOIN (
  SELECT product_id, SUM(total * disc_factor) AS cost, SUM(qty) AS qty
  FROM v_lines WHERE inv_kind = 'purchase' GROUP BY product_id
) c ON c.product_id = p.id''',
};
