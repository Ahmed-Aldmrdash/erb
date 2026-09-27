import 'package:excel/excel.dart';
import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/db/schema.dart';
import '../../core/util/format.dart';
import '../../data/appliances_repo.dart';
import '../../data/calc.dart';
import '../../data/labels.dart';
import 'file_out.dart';

enum XKind { text, money, qty, int, date, code }

/// One column of a sheet: its title, how to read it from a row, its width.
class XCol {
  const XCol(this.title, this.value, {this.kind = XKind.text, this.width = 16});

  final String title;
  final Object? Function(DbRow r) value;
  final XKind kind;
  final double width;
}

class XSheet {
  const XSheet(this.name, this.columns, this.rows);

  /// At most 31 characters (an Excel limit).
  final String name;
  final List<XCol> columns;
  final List<DbRow> rows;
}

/// Excel workbooks of the open division: the stock, the accounts, invoices,
/// weighings, money... to keep a copy or to move to another system. Every
/// sheet has one row per record, right-to-left, with an ID column at the end
/// so the sheets can be linked together.
class ExcelExport {
  static final _qty = NumFormat.custom(formatCode: '#,##0.###');
  static final _date = NumFormat.custom(formatCode: 'dd/mm/yyyy');

  static List<int> encode(List<XSheet> sheets) {
    final excel = Excel.createExcel();
    final first = excel.getDefaultSheet() ?? 'Sheet1';
    final head = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString(app.isCrops ? 'FF2F6B33' : 'FF1C4E8C'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
    );
    for (var si = 0; si < sheets.length; si++) {
      final x = sheets[si];
      final name = x.name.length > 31 ? x.name.substring(0, 31) : x.name;
      if (si == 0) excel.rename(first, name);
      final sheet = excel[name];
      for (var c = 0; c < x.columns.length; c++) {
        sheet.setColumnWidth(c, x.columns[c].width);
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
          TextCellValue(x.columns[c].title),
          cellStyle: head,
        );
      }
      sheet.setRowHeight(0, 30);
      for (var r = 0; r < x.rows.length; r++) {
        for (var c = 0; c < x.columns.length; c++) {
          final col = x.columns[c];
          final v = col.value(x.rows[r]);
          if (v == null || (v is String && v.isEmpty)) continue;
          final index = CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1);
          switch (col.kind) {
            case XKind.money:
              sheet.updateCell(index, DoubleCellValue(roundMoney(n(v))), cellStyle: CellStyle(numberFormat: NumFormat.standard_4));
            case XKind.qty:
              // Whole numbers as integers: '#,##0.###' would show "12." in Excel.
              final q = round3(n(v));
              sheet.updateCell(
                index,
                q == q.roundToDouble() ? IntCellValue(q.round()) : DoubleCellValue(q),
                cellStyle: CellStyle(numberFormat: q == q.roundToDouble() ? NumFormat.standard_3 : _qty),
              );
            case XKind.int:
              sheet.updateCell(index, IntCellValue(ni(v)));
            case XKind.date:
              final d = parseDate(v);
              if (d == null) continue;
              sheet.updateCell(index, DateCellValue.fromDateTime(d), cellStyle: CellStyle(numberFormat: _date));
            case XKind.code:
            case XKind.text:
              // Codes and phone numbers stay text: leading zeros are kept and
              // long barcodes don't turn into 6.22E+12.
              sheet.updateCell(index, TextCellValue(s(v)));
          }
        }
      }
    }
    // The package re-reads a new sheet while saving it and loses the
    // right-to-left flag, so save once to create the sheets, then set it.
    excel.encode();
    for (final name in excel.tables.keys) {
      excel[name].isRTL = true;
    }
    return excel.encode()!;
  }

  static const mime = excelMime;
  static const green = excelGreen;

  /// Builds the workbook, then lets the user save it in the phone's Downloads
  /// or send it (WhatsApp, e-mail, Drive...).
  static Future<void> export(BuildContext context, String title, Future<List<XSheet>> Function() build) async {
    List<XSheet> sheets = const [];
    await saveOrSendFile(
      context,
      title: title,
      extension: 'xlsx',
      mime: excelMime,
      icon: Icons.table_view_outlined,
      build: () async {
        sheets = await build();
        return encode(sheets);
      },
      details: () {
        final rows = sheets.fold<int>(0, (a, x) => a + x.rows.length);
        return sheets.length == 1 ? 'عدد السطور: $rows' : 'عدد الصفحات: ${sheets.length} • عدد السطور: $rows';
      },
    );
  }

  // ---------------------------------------------------------------- sheets

  static XCol _id() => XCol('المعرّف (ID)', (r) => r['id'], width: 38);

  static XCol _by() => XCol('سجّلها', (r) => r['created_by_name'], width: 14);

  /// {item: {warehouse: qty}} and the warehouses that hold something.
  static Future<({Map<String, Map<String, double>> byItem, List<DbRow> warehouses})> _stockByWarehouse(
      String view) async {
    final rows = await app.db.q('SELECT item_id, warehouse_id, SUM(qty) AS qty FROM $view GROUP BY item_id, warehouse_id');
    final byItem = <String, Map<String, double>>{};
    for (final r in rows) {
      byItem.putIfAbsent(s(r['item_id']), () => {})[s(r['warehouse_id'])] = n(r['qty']);
    }
    final warehouses = await app.crops.warehouses(activeOnly: false);
    return (byItem: byItem, warehouses: warehouses);
  }

  /// أصناف المعرض: codes, prices, quantity in every warehouse, cost and value.
  static Future<XSheet> products() async {
    final rows = await app.appliances.products(activeOnly: false);
    final st = await _stockByWarehouse('v_product_moves');
    return XSheet('الأصناف', [
      XCol('رقم الصنف (الكود)', (r) => r['barcode'], kind: XKind.code, width: 18),
      XCol('اسم الصنف', (r) => r['name'], width: 30),
      XCol('القسم', (r) => r['category']),
      XCol('الماركة', (r) => r['brand']),
      XCol('الموديل', (r) => r['model']),
      XCol('الوحدة', (r) => r['unit'], width: 10),
      XCol('الكمية الموجودة', (r) => r['stock'], kind: XKind.qty, width: 14),
      if (st.warehouses.length > 1)
        for (final w in st.warehouses)
          XCol('في ${s(w['name'])}', (r) => st.byItem[s(r['id'])]?[s(w['id'])] ?? 0, kind: XKind.qty, width: 14),
      XCol('سعر الشراء', (r) => r['cost_price'], kind: XKind.money),
      XCol('متوسط التكلفة', (r) => r['unit_cost'], kind: XKind.money),
      XCol('سعر القطاعي', (r) => r['retail_price'], kind: XKind.money),
      XCol('سعر الجملة', (r) => r['wholesale_price'], kind: XKind.money),
      XCol('قيمة المخزون بالتكلفة', (r) => n(r['stock']) > 0 ? n(r['stock']) * n(r['unit_cost']) : 0, kind: XKind.money, width: 18),
      XCol('حد الطلب', (r) => r['min_qty'], kind: XKind.qty, width: 10),
      XCol('الحالة', (r) => n(r['active']) == 1 ? 'شغال' : 'موقوف', width: 10),
      XCol('ملاحظات', (r) => r['notes'], width: 24),
      _id(),
    ], rows);
  }

  /// المحاصيل: stock in kilos and units, per warehouse, cost and today's prices.
  static Future<XSheet> crops() async {
    final rows = await app.crops.crops(activeOnly: false);
    final st = await _stockByWarehouse('v_crop_moves');
    double units(DbRow r, double kg) => n(r['kg_per_unit']) > 0 ? kg / n(r['kg_per_unit']) : 0;
    return XSheet('المحاصيل', [
      XCol('المحصول', (r) => r['name'], width: 18),
      XCol('الوحدة', (r) => r['unit_name'], width: 10),
      XCol('كيلو في الوحدة', (r) => r['kg_per_unit'], kind: XKind.qty, width: 12),
      XCol('الرصيد (كجم)', (r) => r['stock_kg'], kind: XKind.qty),
      XCol('الرصيد بالوحدة', (r) => units(r, n(r['stock_kg'])), kind: XKind.qty),
      if (st.warehouses.length > 1)
        for (final w in st.warehouses)
          XCol('في ${s(w['name'])} (كجم)', (r) => st.byItem[s(r['id'])]?[s(w['id'])] ?? 0, kind: XKind.qty),
      XCol('متوسط التكلفة للكيلو', (r) => r['cost_per_kg'], kind: XKind.money),
      XCol('متوسط التكلفة للوحدة', (r) => n(r['cost_per_kg']) * n(r['kg_per_unit']), kind: XKind.money),
      XCol('قيمة المخزون', (r) => n(r['stock_kg']) > 0 ? n(r['stock_kg']) * n(r['cost_per_kg']) : 0, kind: XKind.money),
      XCol('سعر الشراء النهارده', (r) => r['buy_price'], kind: XKind.money),
      XCol('سعر البيع النهارده', (r) => r['sell_price'], kind: XKind.money),
      XCol('الحالة', (r) => n(r['active']) == 1 ? 'شغال' : 'موقوف', width: 10),
      _id(),
    ], rows);
  }

  /// الحسابات: every customer / supplier / farmer / trader with the balance.
  static Future<XSheet> parties() async {
    final rows = await app.accounts.parties();
    return XSheet('الحسابات', [
      XCol('الاسم', (r) => r['name'], width: 26),
      XCol('النوع', (r) => partyKinds[r['kind']] ?? r['kind'], width: 12),
      XCol('التليفون', (r) => r['phone'], kind: XKind.code, width: 15),
      XCol('العنوان', (r) => r['address'], width: 22),
      XCol('الرقم القومي', (r) => r['national_id'], kind: XKind.code, width: 17),
      XCol('لينا عنده', (r) => n(r['balance']) > 0.009 ? n(r['balance']) : null, kind: XKind.money),
      XCol('علينا له', (r) => n(r['balance']) < -0.009 ? -n(r['balance']) : null, kind: XKind.money),
      XCol('الرصيد (+ لينا / - علينا)', (r) => r['balance'], kind: XKind.money, width: 20),
      XCol('رصيد أول المدة', (r) => r['opening_balance'], kind: XKind.money),
      XCol('ميعاد التحصيل', (r) => r['collect_on'], kind: XKind.date, width: 13),
      XCol('آخر حركة', (r) => r['last_date'], kind: XKind.date, width: 13),
      XCol('ملاحظات', (r) => r['notes'], width: 24),
      _id(),
    ], rows);
  }

  static Future<XSheet> invoices() async {
    final rows = await app.appliances.invoices();
    return XSheet('الفواتير', [
      XCol('رقم الفاتورة', (r) => r['number'], kind: XKind.code, width: 12),
      XCol('التاريخ', (r) => r['date'], kind: XKind.date, width: 13),
      XCol('النوع', (r) => invoiceKinds[r['kind']] ?? r['kind'], width: 13),
      XCol('العميل / المورد', (r) => s(r['party_name']).isNotEmpty ? r['party_name'] : r['customer_name'], width: 24),
      XCol('طريقة الدفع', (r) => paymentTypes[r['payment_type']] ?? r['payment_type'], width: 11),
      XCol('نوع السعر', (r) => priceLevels[r['price_level']] ?? r['price_level'], width: 10),
      XCol('الإجمالي', (r) => r['subtotal'], kind: XKind.money),
      XCol('الخصم', (r) => r['discount'], kind: XKind.money),
      XCol('الصافي', (r) => r['total'], kind: XKind.money),
      XCol('زيادة التقسيط', (r) => r['markup_amount'], kind: XKind.money),
      XCol('الإجمالي النهائي', (r) => r['grand_total'], kind: XKind.money),
      XCol('المدفوع وقت الفاتورة', (r) => r['paid_amount'], kind: XKind.money),
      XCol('اتحصل بعد كده', (r) => r['collected'], kind: XKind.money),
      XCol('الباقي', (r) => AppliancesRepo.remainingOf(r), kind: XKind.money),
      XCol('عدد الأقساط', (r) => n(r['inst_months']) > 0 ? r['inst_months'] : null, kind: XKind.int, width: 10),
      XCol('الضامن', (r) => r['guarantor_name']),
      XCol('المخزن', (r) => r['warehouse_name']),
      XCol('الخزنة', (r) => r['box_name']),
      XCol('اتعملت من', (r) => r['source'] == 'pos' ? 'الكاشير' : 'فاتورة', width: 11),
      XCol('ملاحظات', (r) => r['notes'], width: 22),
      _by(),
      _id(),
    ], rows);
  }

  static Future<XSheet> invoiceLines() async {
    final rows = await app.db.q('''
SELECT l.*, i.number AS inv_number, i.date AS inv_date, i.kind AS inv_kind,
  p.name AS product_name, p.barcode, p.model
FROM v_lines l JOIN invoices i ON i.id = l.invoice_id
LEFT JOIN products p ON p.id = l.product_id
ORDER BY i.date DESC, i.number, l.sort''');
    return XSheet('أصناف الفواتير', [
      XCol('رقم الفاتورة', (r) => r['inv_number'], kind: XKind.code, width: 12),
      XCol('التاريخ', (r) => r['inv_date'], kind: XKind.date, width: 13),
      XCol('نوع الفاتورة', (r) => invoiceKinds[r['inv_kind']] ?? r['inv_kind'], width: 13),
      XCol('الكود', (r) => r['barcode'], kind: XKind.code, width: 16),
      XCol('الصنف', (r) => r['product_name'], width: 28),
      XCol('الموديل', (r) => r['model']),
      XCol('الكمية', (r) => r['qty'], kind: XKind.qty, width: 10),
      XCol('السعر', (r) => r['price'], kind: XKind.money),
      XCol('الإجمالي', (r) => r['total'], kind: XKind.money),
      XCol('ملاحظات', (r) => r['notes'], width: 20),
      XCol('معرّف الفاتورة', (r) => r['invoice_id'], width: 38),
      XCol('معرّف الصنف', (r) => r['product_id'], width: 38),
    ], rows);
  }

  static Future<XSheet> installments() async {
    final invoices = await app.appliances.invoices(paymentType: 'installment');
    final today = todayStr();
    final rows = <DbRow>[];
    for (final inv in invoices.where((i) => i['kind'] == 'sale')) {
      for (final it in await app.appliances.invoiceInstallments(s(inv['id']))) {
        rows.add({
          'number': inv['number'],
          'party': inv['party_name'],
          'phone': inv['party_phone'],
          'seq': it.seq,
          'due': it.dueDate,
          'amount': it.amount,
          'paid': it.paid,
          'remaining': it.remaining,
          'state': switch (it.stateOn(today)) {
            InstallmentState.paid => 'مدفوع',
            InstallmentState.partial => 'مدفوع جزء',
            InstallmentState.overdue => 'متأخر',
            InstallmentState.due => 'لسه',
          },
          'invoice_id': inv['id'],
        });
      }
    }
    return XSheet('الأقساط', [
      XCol('رقم الفاتورة', (r) => r['number'], kind: XKind.code, width: 12),
      XCol('العميل', (r) => r['party'], width: 24),
      XCol('التليفون', (r) => r['phone'], kind: XKind.code, width: 15),
      XCol('رقم القسط', (r) => r['seq'], kind: XKind.int, width: 9),
      XCol('تاريخ الاستحقاق', (r) => r['due'], kind: XKind.date, width: 14),
      XCol('القيمة', (r) => r['amount'], kind: XKind.money),
      XCol('المدفوع', (r) => r['paid'], kind: XKind.money),
      XCol('الباقي', (r) => r['remaining'], kind: XKind.money),
      XCol('الحالة', (r) => r['state'], width: 11),
      XCol('معرّف الفاتورة', (r) => r['invoice_id'], width: 38),
    ], rows);
  }

  static Future<XSheet> cropTrades() async {
    final rows = await app.crops.trades();
    CropCalc c(DbRow r) => CropCalc.fromRow(r);
    return XSheet('التوريد والبيع', [
      XCol('رقم العملية', (r) => r['number'], kind: XKind.code, width: 11),
      XCol('التاريخ', (r) => r['date'], kind: XKind.date, width: 13),
      XCol('النوع', (r) => cropTradeKinds[r['kind']] ?? r['kind'], width: 13),
      XCol('الاسم', (r) => r['party_name'], width: 24),
      XCol('المحصول', (r) => r['crop_name'], width: 14),
      XCol('المخزن', (r) => r['warehouse_name'], width: 16),
      XCol('طريقة الوزن', (r) => r['weigh_mode'] == 'sacks' ? 'بالشكارة' : 'باسكول', width: 11),
      XCol('القايم / وزن الشكاير (كجم)', (r) => r['gross_kg'], kind: XKind.qty, width: 18),
      XCol('الفارغ (كجم)', (r) => r['tare_kg'], kind: XKind.qty, width: 12),
      XCol('عدد الشكاير', (r) => r['bags_count'], kind: XKind.qty, width: 11),
      XCol('وزن الشكارة الفاضية', (r) => r['bag_weight_kg'], kind: XKind.qty, width: 14),
      XCol('أوزان الشكاير', (r) => sackWeightsOf(r['sack_weights']).map(qty).join(' + '), width: 30),
      XCol('خصم رطوبة (كجم)', (r) => c(r).moistureDeductionKg, kind: XKind.qty, width: 14),
      XCol('خصم شوائب (كجم)', (r) => c(r).impuritiesDeductionKg, kind: XKind.qty, width: 14),
      XCol('خصم تاني (كجم)', (r) => r['other_deduction_kg'], kind: XKind.qty, width: 13),
      XCol('الصافي (كجم)', (r) => r['net_kg'], kind: XKind.qty),
      XCol('الوحدة', (r) => r['unit_name'], width: 9),
      XCol('الصافي بالوحدة', (r) => c(r).units, kind: XKind.qty),
      XCol('السعر للوحدة', (r) => r['price_per_unit'], kind: XKind.money),
      XCol('قيمة المحصول', (r) => r['subtotal'], kind: XKind.money),
      XCol('نولون', (r) => r['freight'], kind: XKind.money, width: 11),
      XCol('عتالة وتحميل', (r) => r['loading'], kind: XKind.money, width: 12),
      XCol('مصاريف أخرى', (r) => r['other_expenses'], kind: XKind.money, width: 12),
      XCol('المصاريف على', (r) => n(r['expenses_on_party']) == 1 ? 'الطرف التاني' : 'علينا', width: 12),
      XCol('صافي الحساب', (r) => r['party_total'], kind: XKind.money),
      XCol('المدفوع', (r) => r['paid_amount'], kind: XKind.money),
      XCol('الباقي', (r) => c(r).remaining, kind: XKind.money),
      XCol('رقم الكارتة', (r) => r['ticket_no'], kind: XKind.code, width: 12),
      XCol('العربية / السواق', (r) => r['vehicle'], width: 16),
      XCol('ملاحظات', (r) => r['notes'], width: 22),
      _by(),
      _id(),
    ], rows);
  }

  static Future<XSheet> vouchers({List<String>? kinds, String name = 'حركات الفلوس'}) async {
    final rows = await app.accounts.vouchers(kinds: kinds);
    return XSheet(name, [
      XCol('الرقم', (r) => r['number'], kind: XKind.code, width: 10),
      XCol('التاريخ', (r) => r['date'], kind: XKind.date, width: 13),
      XCol('النوع', (r) => voucherKinds[r['kind']] ?? r['kind'], width: 15),
      XCol('الاسم', (r) => r['party_name'], width: 24),
      XCol('المبلغ', (r) => r['amount'], kind: XKind.money),
      XCol('الخزنة', (r) => r['box_name']),
      XCol('إلى خزنة', (r) => r['to_box_name']),
      XCol('البند', (r) => r['category']),
      XCol('عن فاتورة', (r) => r['invoice_number'], kind: XKind.code, width: 11),
      XCol('اللي استلم / دفع', (r) => r['handled_by'], width: 15),
      XCol('البيان', (r) => r['notes'], width: 28),
      _by(),
      _id(),
    ], rows);
  }

  static Future<XSheet> cashBoxes() async {
    final rows = await app.accounts.cashBoxes(activeOnly: false);
    return XSheet('الخزن', [
      XCol('الخزنة', (r) => r['name'], width: 20),
      XCol('رصيد أول المدة', (r) => r['opening_balance'], kind: XKind.money),
      XCol('الرصيد دلوقتي', (r) => r['balance'], kind: XKind.money),
      XCol('الحالة', (r) => n(r['active']) == 1 ? 'شغالة' : 'موقوفة', width: 10),
      XCol('ملاحظات', (r) => r['notes'], width: 22),
      _id(),
    ], rows);
  }

  static Future<XSheet> warehouses() async {
    final rows = await app.crops.warehouses(activeOnly: false);
    return XSheet('المخازن', [
      XCol('المخزن', (r) => r['name'], width: 22),
      XCol('العنوان / ملاحظات', (r) => r['notes'], width: 26),
      XCol('الحالة', (r) => n(r['active']) == 1 ? 'شغال' : 'موقوف', width: 10),
      _id(),
    ], rows);
  }

  static Future<XSheet> stockMoves() async {
    final rows = await app.crops.stockMoves(app.isCrops ? 'crop' : 'product');
    return XSheet('حركات المخزن', [
      XCol('الرقم', (r) => r['number'], kind: XKind.code, width: 10),
      XCol('التاريخ', (r) => r['date'], kind: XKind.date, width: 13),
      XCol('النوع', (r) => stockMoveKinds[r['kind']] ?? r['kind'], width: 15),
      XCol(app.isCrops ? 'المحصول' : 'الصنف', (r) => r['item_name'], width: 26),
      XCol('المخزن', (r) => r['warehouse_name']),
      XCol('إلى مخزن', (r) => r['to_warehouse_name']),
      XCol(app.isCrops ? 'الكمية (كجم)' : 'الكمية', (r) => r['qty'], kind: XKind.qty),
      XCol('ملاحظات', (r) => r['notes'], width: 24),
      _by(),
      _id(),
    ], rows);
  }

  static Future<XSheet> notes() async {
    final rows = await app.db.q("SELECT * FROM notes WHERE deleted = 0 ORDER BY done, created_at DESC");
    return XSheet('التذكرة', [
      XCol('النوع', (r) => noteKinds[r['kind']] ?? r['kind'], width: 12),
      XCol('التذكرة', (r) => r['body'], width: 40),
      XCol('المبلغ', (r) => n(r['amount']) > 0 ? r['amount'] : null, kind: XKind.money),
      XCol('لمين', (r) => r['person'], width: 14),
      XCol('الميعاد', (r) => r['due_date'], kind: XKind.date, width: 13),
      XCol('للقسمين', (r) => r['division'] == Division.all ? 'أيوه' : '', width: 9),
      XCol('خلصت', (r) => n(r['done']) == 1 ? 'أيوه' : 'لسه', width: 8),
      XCol('خلّصها', (r) => r['done_by'], width: 12),
      XCol('كتبها', (r) => r['created_by_name'], width: 12),
      XCol('اتكتبت يوم', (r) => s(r['created_at']).length >= 10 ? s(r['created_at']).substring(0, 10) : null, kind: XKind.date, width: 13),
      _id(),
    ], rows);
  }

  /// First sheet of the full backup: what it is and the main totals.
  static Future<XSheet> summary() async {
    final rp = await app.reports.receivablesPayables();
    final now = DateTime.now();
    final time = '${now.hour % 12 == 0 ? 12 : now.hour % 12}:${now.minute.toString().padLeft(2, '0')} '
        '${now.hour < 12 ? 'صباحاً' : 'مساءً'}';
    final rows = <DbRow>[
      {'k': 'المؤسسة', 'v': app.companyName},
      {'k': 'القسم', 'v': Division.long[app.division]},
      {'k': 'تاريخ التنزيل', 'v': '${showDate(todayStr())} الساعة $time'},
      {'k': 'نزّله', 'v': app.person},
      {'k': 'لينا عند الناس', 'v': egp(rp.receivable)},
      {'k': 'علينا للناس', 'v': egp(rp.payable)},
      {'k': 'في الخزن', 'v': egp(await app.reports.cashTotal())},
      {'k': 'قيمة المخزون بالتكلفة', 'v': egp(app.isCrops ? await app.crops.stockValue() : await app.appliances.stockValue())},
    ];
    return XSheet('ملخص', [
      XCol('البيان', (r) => r['k'], width: 24),
      XCol('القيمة', (r) => r['v'], width: 40),
    ], rows);
  }

  /// Everything of the open division, one sheet per kind of record.
  static Future<List<XSheet>> everything() async => [
        await summary(),
        if (app.isCrops) ...[
          await crops(),
          await cropTrades(),
        ] else ...[
          await products(),
          await invoices(),
          await invoiceLines(),
          await installments(),
        ],
        await parties(),
        await vouchers(),
        await cashBoxes(),
        await warehouses(),
        await stockMoves(),
        await notes(),
      ];
}

/// App-bar button that downloads [sheets] as an Excel file and shares it.
class ExcelButton extends StatelessWidget {
  const ExcelButton({super.key, required this.title, required this.sheets});

  /// Also the file name.
  final String title;
  final Future<List<XSheet>> Function() sheets;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'تنزيل شيت Excel',
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: ExcelExport.green,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () => ExcelExport.export(context, title, sheets),
          icon: const Icon(Icons.download_rounded, size: 20),
          label: const Text('Excel', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      );
}
