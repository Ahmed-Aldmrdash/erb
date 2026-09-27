// Single source of truth for every table that lives both on the phone
// (SQLite) and on the server (Supabase / Postgres).
//
// The same definitions create the local tables, convert rows while syncing and
// generate supabase/schema.sql (dart run tool/gen_supabase_sql.dart), so the
// two sides can never drift apart.
//
// Keep this file free of Flutter imports: the SQL generator runs on plain Dart.

enum ColType { text, real, integer, boolean, date, timestamp, uuid }

class Col {
  const Col(this.name, this.type, {this.def});

  final String name;
  final ColType type;

  /// Default value. Columns that have a default are NOT NULL on both sides.
  final Object? def;

  bool get notNull => def != null;
}

/// The two businesses. Every row belongs to one of them; 'all' is only used
/// for notes both sides should see.
class Division {
  static const crops = 'crops';
  static const appliances = 'appliances';
  static const all = 'all';

  static const names = {crops: 'التجارة', appliances: 'المعرض'};
  static const long = {crops: 'تجارة المحاصيل', appliances: 'الأدوات المنزلية والأجهزة الكهربائية'};
}

class TableDef {
  const TableDef(this.name, this.cols, {this.textId = false, this.division = Division.crops});

  final String name;
  final List<Col> cols;

  /// Primary key is free text instead of a UUID (settings keys).
  final bool textId;

  /// Default division of new rows (the writer always fills it in anyway).
  final String division;

  static const _common = [
    Col('created_at', ColType.timestamp),
    Col('updated_at', ColType.timestamp),
    Col('deleted', ColType.boolean, def: false),
    // The name typed at login by whoever created / last changed the row.
    Col('created_by_name', ColType.text),
    Col('updated_by_name', ColType.text),
  ];

  List<Col> get allCols => [
        Col('id', textId ? ColType.text : ColType.uuid),
        Col('division', ColType.text, def: division),
        ...cols,
        ..._common,
      ];

  Col? col(String name) {
    for (final c in allCols) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// Settings are stored per division: id = `division:key`.
const settingsTable = TableDef('app_settings', [
  Col('value', ColType.text),
], textId: true);

const partiesTable = TableDef('parties', [
  Col('name', ColType.text, def: ''),
  // customer | supplier | farmer | trader | other
  Col('kind', ColType.text, def: 'customer'),
  Col('phone', ColType.text),
  Col('address', ColType.text),
  Col('national_id', ColType.text),
  // Positive: the party owes us. Negative: we owe the party.
  Col('opening_balance', ColType.real, def: 0),
  // Promised payment date (ميعاد التحصيل / السداد).
  Col('collect_on', ColType.date),
  // Warn when the party owes us more than this (0 = no limit).
  Col('credit_limit', ColType.real, def: 0),
  Col('notes', ColType.text),
]);

const warehousesTable = TableDef('warehouses', [
  Col('name', ColType.text, def: ''),
  Col('notes', ColType.text),
  Col('active', ColType.boolean, def: true),
]);

const cashBoxesTable = TableDef('cash_boxes', [
  Col('name', ColType.text, def: ''),
  Col('opening_balance', ColType.real, def: 0),
  Col('notes', ColType.text),
  Col('active', ColType.boolean, def: true),
]);

const cropsTable = TableDef('crops', [
  Col('name', ColType.text, def: ''),
  Col('unit_name', ColType.text, def: 'طن'),
  Col('kg_per_unit', ColType.real, def: 1000),
  // Today's prices per unit, used to pre-fill weighings.
  Col('buy_price', ColType.real, def: 0),
  Col('sell_price', ColType.real, def: 0),
  Col('notes', ColType.text),
  Col('active', ColType.boolean, def: true),
]);

/// One weighing: a purchase from a farmer or a sale to a trader / factory.
const cropTradesTable = TableDef('crop_trades', [
  // purchase | sale
  Col('kind', ColType.text, def: 'purchase'),
  Col('number', ColType.text),
  Col('date', ColType.date),
  Col('party_id', ColType.uuid),
  Col('crop_id', ColType.uuid),
  Col('warehouse_id', ColType.uuid),
  Col('cash_box_id', ColType.uuid),
  // Snapshot of the crop unit at the time of the trade.
  Col('unit_name', ColType.text),
  Col('kg_per_unit', ColType.real, def: 1000),
  // scale: weighbridge, gross minus the empty truck | sacks: sack by sack.
  Col('weigh_mode', ColType.text, def: 'scale'),
  // Scale: loaded truck (القائم). Sacks: total of the sack weights.
  Col('gross_kg', ColType.real, def: 0),
  // Empty truck (الفارغ).
  Col('tare_kg', ColType.real, def: 0),
  // Sacks mode: every sack's weight as a JSON list (empty when only the
  // total was written).
  Col('sack_weights', ColType.text),
  Col('bags_count', ColType.real, def: 0),
  // Weight of one empty sack, deducted per sack.
  Col('bag_weight_kg', ColType.real, def: 0),
  // Quality deductions in kilos.
  Col('moisture_kg', ColType.real, def: 0),
  Col('impurities_kg', ColType.real, def: 0),
  // Old weighings stored the quality deductions as percentages.
  Col('moisture_pct', ColType.real, def: 0),
  Col('impurities_pct', ColType.real, def: 0),
  Col('other_deduction_kg', ColType.real, def: 0),
  // Weight that is paid for.
  Col('net_kg', ColType.real, def: 0),
  // Weight that enters (purchase) or leaves (sale) the warehouse.
  Col('stock_kg', ColType.real, def: 0),
  Col('price_per_unit', ColType.real, def: 0),
  Col('subtotal', ColType.real, def: 0),
  Col('freight', ColType.real, def: 0),
  Col('loading', ColType.real, def: 0),
  Col('other_expenses', ColType.real, def: 0),
  // Expenses are always paid from the cash box; when this flag is set they
  // are charged to the farmer / trader instead of being our cost.
  Col('expenses_on_party', ColType.boolean, def: false),
  // Amount posted to the party account.
  Col('party_total', ColType.real, def: 0),
  Col('paid_amount', ColType.real, def: 0),
  Col('ticket_no', ColType.text),
  Col('vehicle', ColType.text),
  Col('notes', ColType.text),
]);

const productsTable = TableDef('products', [
  Col('name', ColType.text, def: ''),
  Col('category', ColType.text),
  Col('brand', ColType.text),
  Col('model', ColType.text),
  Col('barcode', ColType.text),
  Col('unit', ColType.text, def: 'قطعة'),
  Col('cost_price', ColType.real, def: 0),
  Col('retail_price', ColType.real, def: 0),
  Col('wholesale_price', ColType.real, def: 0),
  Col('min_qty', ColType.real, def: 0),
  Col('notes', ColType.text),
  Col('active', ColType.boolean, def: true),
], division: Division.appliances);

const invoicesTable = TableDef('invoices', [
  // sale | purchase | sale_return | purchase_return
  Col('kind', ColType.text, def: 'sale'),
  Col('number', ColType.text),
  Col('date', ColType.date),
  Col('party_id', ColType.uuid),
  // Walk-in cash customer without an account.
  Col('customer_name', ColType.text),
  Col('warehouse_id', ColType.uuid),
  Col('cash_box_id', ColType.uuid),
  // retail | wholesale
  Col('price_level', ColType.text, def: 'retail'),
  // cash | credit | installment
  Col('payment_type', ColType.text, def: 'cash'),
  Col('subtotal', ColType.real, def: 0),
  Col('discount', ColType.real, def: 0),
  Col('total', ColType.real, def: 0),
  Col('markup_pct', ColType.real, def: 0),
  Col('markup_amount', ColType.real, def: 0),
  // total + installment markup: the amount posted to the party.
  Col('grand_total', ColType.real, def: 0),
  // Paid now (the down payment for installment sales).
  Col('paid_amount', ColType.real, def: 0),
  Col('inst_months', ColType.integer, def: 0),
  Col('inst_first_due', ColType.date),
  Col('guarantor_name', ColType.text),
  Col('guarantor_phone', ColType.text),
  Col('ref_invoice_id', ColType.uuid),
  // pos | form: where the sale was made.
  Col('source', ColType.text, def: 'form'),
  // Changes on every edit. Lines and installments count only when their rev
  // matches, so two phones editing the same invoice offline can't mix lines.
  Col('rev', ColType.text),
  Col('notes', ColType.text),
], division: Division.appliances);

const invoiceLinesTable = TableDef('invoice_lines', [
  Col('invoice_id', ColType.uuid),
  Col('rev', ColType.text),
  Col('sort', ColType.integer, def: 0),
  Col('product_id', ColType.uuid),
  Col('qty', ColType.real, def: 0),
  Col('price', ColType.real, def: 0),
  Col('total', ColType.real, def: 0),
  Col('notes', ColType.text),
], division: Division.appliances);

const installmentsTable = TableDef('installments', [
  Col('invoice_id', ColType.uuid),
  Col('rev', ColType.text),
  Col('party_id', ColType.uuid),
  Col('seq', ColType.integer, def: 0),
  Col('due_date', ColType.date),
  Col('amount', ColType.real, def: 0),
], division: Division.appliances);

/// Every cash movement that is not part of an invoice or a crop trade.
const vouchersTable = TableDef('vouchers', [
  // receipt | payment | advance | expense | transfer | deposit | withdrawal,
  // or, without any cash: debit_adj (زيادة على حسابه) | credit_adj (خصم من
  // حسابه).
  Col('kind', ColType.text, def: 'receipt'),
  Col('number', ColType.text),
  Col('date', ColType.date),
  Col('party_id', ColType.uuid),
  Col('cash_box_id', ColType.uuid),
  Col('to_cash_box_id', ColType.uuid),
  Col('amount', ColType.real, def: 0),
  Col('category', ColType.text),
  // Installment collections and payments against a specific invoice.
  Col('invoice_id', ColType.uuid),
  // Who of us physically received / handed over the money.
  Col('handled_by', ColType.text),
  Col('notes', ColType.text),
]);

/// Warehouse transfers and stock adjustments (shrinkage, stock count).
const stockMovesTable = TableDef('stock_moves', [
  // transfer | adjust
  Col('kind', ColType.text, def: 'adjust'),
  Col('number', ColType.text),
  Col('date', ColType.date),
  // crop (qty in kg) | product (qty in pieces)
  Col('item_type', ColType.text, def: 'crop'),
  Col('item_id', ColType.uuid),
  Col('warehouse_id', ColType.uuid),
  Col('to_warehouse_id', ColType.uuid),
  // Adjust: signed. Transfer: positive, from warehouse_id to to_warehouse_id.
  Col('qty', ColType.real, def: 0),
  Col('notes', ColType.text),
]);

/// Reminders shared by everybody working in a division (or in both when the
/// division is 'all'), e.g. money left with one brother for the other.
const notesTable = TableDef('notes', [
  // note | money | task
  Col('kind', ColType.text, def: 'note'),
  Col('body', ColType.text, def: ''),
  Col('amount', ColType.real, def: 0),
  // Who it is for / about.
  Col('person', ColType.text),
  Col('due_date', ColType.date),
  Col('done', ColType.boolean, def: false),
  Col('done_by', ColType.text),
  Col('done_at', ColType.timestamp),
  Col('pinned', ColType.boolean, def: false),
]);

/// Tables pushed and pulled by the sync engine, in push order.
const syncedTables = [
  settingsTable,
  partiesTable,
  warehousesTable,
  cashBoxesTable,
  cropsTable,
  productsTable,
  cropTradesTable,
  invoicesTable,
  invoiceLinesTable,
  installmentsTable,
  vouchersTable,
  stockMovesTable,
  notesTable,
];

const allTables = syncedTables;

final Map<String, TableDef> tableByName = {for (final t in allTables) t.name: t};

// ---------------------------------------------------------------- conversion

Object? toLocalValue(Col c, Object? v) {
  if (v == null) return c.def == null ? null : toLocalValue(c, c.def);
  switch (c.type) {
    case ColType.boolean:
      return (v == true || v == 1 || v == 'true') ? 1 : 0;
    case ColType.real:
      return v is num ? v.toDouble() : (double.tryParse('$v') ?? 0.0);
    case ColType.integer:
      return v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
    case ColType.uuid:
      final t = '$v';
      return t.isEmpty ? null : t;
    case ColType.text:
    case ColType.date:
    case ColType.timestamp:
      return '$v';
  }
}

Object? toRemoteValue(Col c, Object? v) {
  if (v == null) return c.def;
  switch (c.type) {
    case ColType.boolean:
      return v == 1 || v == true;
    case ColType.real:
      return v is num ? v.toDouble() : (double.tryParse('$v') ?? 0.0);
    case ColType.integer:
      return v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
    case ColType.uuid:
    case ColType.date:
    case ColType.timestamp:
      final t = '$v';
      return t.isEmpty ? null : t;
    case ColType.text:
      return '$v';
  }
}

Map<String, Object?> rowToRemote(TableDef t, Map<String, Object?> local) => {
      for (final c in t.allCols) c.name: toRemoteValue(c, local[c.name]),
    };

Map<String, Object?> rowFromRemote(TableDef t, Map<String, dynamic> remote) => {
      for (final c in t.allCols) c.name: toLocalValue(c, remote[c.name]),
    };
