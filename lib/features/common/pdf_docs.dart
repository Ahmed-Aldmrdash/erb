import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/db/schema.dart';
import '../../core/util/format.dart';
import '../../core/util/tafqit.dart';
import '../../data/appliances_repo.dart';
import '../../data/barcode.dart';
import '../../data/calc.dart';
import '../../data/labels.dart';
import '../../data/reports_repo.dart';
import '../../ui/widgets.dart' show balanceForParty;

/// Arabic PDFs (invoices, cashier receipts, weighing receipts, account pages,
/// money receipts) shared through the phone share sheet, e.g. to WhatsApp.
class PdfDocs {
  static pw.ThemeData? _theme;
  static pw.MemoryImage? _logo;

  static const _grey = PdfColor.fromInt(0xFF66716D);
  static const _ink = PdfColor.fromInt(0xFF17202A);
  static const _line = PdfColor.fromInt(0xFFD5DBD8);
  static const _zebra = PdfColor.fromInt(0xFFF6F8F9);
  static const _paper = PdfColor.fromInt(0xFFFFF8E6);
  static const _paperLine = PdfColor.fromInt(0xFFF0E2BD);
  static const _red = PdfColor.fromInt(0xFFC0392B);
  static const _green = PdfColor.fromInt(0xFF1E8A4C);

  /// Color of the open division (المعرض blue, التجارة green).
  static PdfColor get _brand => app.isCrops ? const PdfColor.fromInt(0xFF2F6B33) : const PdfColor.fromInt(0xFF1C4E8C);
  static PdfColor get _brandSoft => app.isCrops ? const PdfColor.fromInt(0xFFE9F2E4) : const PdfColor.fromInt(0xFFE7EEF8);

  static Future<pw.ThemeData> _loadTheme() async {
    final cached = _theme;
    if (cached != null) return cached;
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'));
    return _theme = pw.ThemeData.withFont(base: regular, bold: bold);
  }

  static Future<pw.MemoryImage> _loadLogo() async =>
      _logo ??= pw.MemoryImage((await rootBundle.load('assets/images/logo.png')).buffer.asUint8List());

  static Future<void> share(Uint8List bytes, String filename) =>
      Printing.sharePdf(bytes: bytes, filename: filename);

  static pw.TextStyle _t(double size, {bool bold = false, PdfColor? color}) =>
      pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null, color: color);

  static Future<Uint8List> _document({
    required String title,
    String? number,
    required String date,
    required List<pw.Widget> body,
  }) async {
    final theme = await _loadTheme();
    final logo = await _loadLogo();
    final settings = app.settings;
    final brand = _brand;
    final phone = settings['company_phone'] ?? '';
    final address = settings['company_address'] ?? '';
    final doc = pw.Document(title: title, author: app.companyName);
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          theme: theme,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.fromLTRB(30, 26, 30, 26),
        ),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.ClipRRect(horizontalRadius: 10, verticalRadius: 10, child: pw.Image(logo, width: 50, height: 50)),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(app.companyName, style: _t(19, bold: true, color: brand)),
                      pw.Text(Division.long[app.division] ?? '', style: _t(10.5, color: _grey)),
                      if (phone.isNotEmpty || address.isNotEmpty)
                        pw.Text(
                          [if (phone.isNotEmpty) 'ت: $phone', if (address.isNotEmpty) address].join('  •  '),
                          style: _t(9.5, color: _grey),
                        ),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: pw.BoxDecoration(color: brand, borderRadius: pw.BorderRadius.circular(8)),
                  child: pw.Column(
                    children: [
                      pw.Text(title, style: _t(14, bold: true, color: PdfColors.white)),
                      if (number != null && number.isNotEmpty) pw.Text('رقم $number', style: _t(10.5, color: PdfColors.white)),
                      pw.Text(showDate(date), style: _t(10.5, color: PdfColors.white)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Container(height: 2.5, color: brand),
            pw.SizedBox(height: 12),
          ],
        ),
        footer: (ctx) => pw.Column(
          children: [
            pw.Container(height: 0.6, color: _line),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Expanded(child: pw.Text(settings['invoice_footer'] ?? '', style: _t(9, color: _grey))),
                pw.Text('صفحة ${ctx.pageNumber} من ${ctx.pagesCount}', style: _t(9, color: _grey)),
              ],
            ),
          ],
        ),
        build: (ctx) => body,
      ),
    );
    return doc.save();
  }

  /// RTL table (the first column is drawn on the right) with a colored head
  /// and striped rows. [align] is per column; centered by default.
  static pw.Widget _table(
    List<String> headers,
    List<List<String>> rows, {
    List<double>? flex,
    bool boldLastRow = false,
    PdfColor? headColor,
    PdfColor? headText,
    List<pw.TextAlign>? align,
  }) {
    final cols = headers.length;
    final widths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < cols; i++) cols - 1 - i: pw.FlexColumnWidth(flex != null && i < flex.length ? flex[i] : 1),
    };
    pw.Widget cell(String text, int col, {bool head = false, bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: pw.Text(
            text,
            textAlign: head ? pw.TextAlign.center : (align != null && col < align.length ? align[col] : pw.TextAlign.center),
            style: _t(head ? 10 : 10.5, bold: head || bold, color: head ? (headText ?? PdfColors.white) : _ink),
          ),
        );
    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _line, width: 0.5),
        bottom: pw.BorderSide(color: _line, width: 0.8),
      ),
      columnWidths: widths,
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headColor ?? _brand),
          children: [for (var i = cols - 1; i >= 0; i--) cell(headers[i], i, head: true)],
        ),
        for (var r = 0; r < rows.length; r++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: boldLastRow && r == rows.length - 1 ? _brandSoft : (r.isOdd ? _zebra : PdfColors.white),
            ),
            children: [
              for (var i = cols - 1; i >= 0; i--) cell(rows[r][i], i, bold: boldLastRow && r == rows.length - 1),
            ],
          ),
      ],
    );
  }

  static pw.Widget _kv(String label, String value, {bool bold = false, PdfColor? color, double size = 11}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
        child: pw.Row(
          children: [
            pw.Expanded(child: pw.Text(label, style: _t(size, color: bold ? _ink : _grey))),
            pw.Text(value, style: _t(bold ? size + 1.5 : size, bold: bold, color: color ?? _ink)),
          ],
        ),
      );

  static pw.Widget _box(List<pw.Widget> children, {PdfColor? color, PdfColor? border}) => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: color,
          border: pw.Border.all(color: border ?? _line),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: children),
      );

  static pw.Widget _partyBox(String label, DbRow r) => _box([
        _kv(label, s(r['party_name']).isNotEmpty ? s(r['party_name']) : s(r['customer_name']), bold: true),
        if (s(r['party_phone']).isNotEmpty) _kv('التليفون', s(r['party_phone'])),
        if (s(r['party_address']).isNotEmpty) _kv('العنوان', s(r['party_address'])),
      ], color: _brandSoft, border: _brandSoft);

  /// The total in a colored strip, and the same amount in words.
  static pw.Widget _grandTotal(String label, double amount) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(color: _brand, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(
              children: [
                pw.Expanded(child: pw.Text(label, style: _t(12.5, bold: true, color: PdfColors.white))),
                pw.Text(egp(amount), style: _t(15, bold: true, color: PdfColors.white)),
              ],
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(amountInWords(amount), style: _t(10, color: _grey)),
        ],
      );

  static pw.Widget _signatures(String left, String right) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 34),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('$right: ....................', style: _t(11)),
            pw.Text('$left: ....................', style: _t(11)),
          ],
        ),
      );

  // ---------------------------------------------------------------- invoice

  static Future<Uint8List> invoice(String invoiceId) async {
    final inv = (await app.appliances.invoice(invoiceId))!;
    final lines = await app.appliances.invoiceLines(invoiceId);
    final kind = s(inv['kind']);
    final isInstallment = inv['payment_type'] == 'installment';
    final installments = isInstallment ? await app.appliances.invoiceInstallments(invoiceId) : <InstallmentStatus>[];
    final remaining = AppliancesRepo.remainingOf(inv);
    final grand = n(inv['grand_total']);
    final paid = roundMoney(grand - remaining);
    final today = todayStr();
    return _document(
      title: invoiceKinds[kind] ?? 'فاتورة',
      number: s(inv['number']),
      date: s(inv['date']),
      body: [
        _partyBox(kind.startsWith('purchase') ? 'المورد' : 'العميل', inv),
        pw.SizedBox(height: 12),
        _table(
          ['#', 'الصنف', 'الكمية', 'السعر', 'الإجمالي'],
          [
            for (var i = 0; i < lines.length; i++)
              [
                '${i + 1}',
                [s(lines[i]['product_name']), s(lines[i]['model']), s(lines[i]['notes'])].where((x) => x.isNotEmpty).join(' - '),
                qty(n(lines[i]['qty'])),
                money(n(lines[i]['price'])),
                money(n(lines[i]['total'])),
              ],
          ],
          flex: [0.5, 4, 1, 1.4, 1.6],
          align: const [pw.TextAlign.center, pw.TextAlign.right],
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _box([
                _kv('طريقة الدفع', paymentTypes[inv['payment_type']] ?? ''),
                if (kind == 'sale') _kv('نوع السعر', priceLevels[inv['price_level']] ?? ''),
                if (isInstallment) ...[
                  _kv('عدد الأقساط', '${ni(inv['inst_months'])} شهر'),
                  if (s(inv['guarantor_name']).isNotEmpty) _kv('الضامن', s(inv['guarantor_name'])),
                ],
                if (s(inv['created_by_name']).isNotEmpty) _kv('سجّلها', s(inv['created_by_name'])),
              ]),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: _box([
                _kv('الإجمالي', egp(n(inv['subtotal']))),
                if (n(inv['discount']) > 0) _kv('الخصم', egp(n(inv['discount']))),
                if (isInstallment) ...[
                  _kv('الصافي', egp(n(inv['total']))),
                  _kv('زيادة التقسيط (${qty(n(inv['markup_pct']))}%)', egp(n(inv['markup_amount']))),
                  _kv('المقدم', egp(n(inv['paid_amount']))),
                ],
                _kv('المدفوع', egp(paid), color: _green),
                if (remaining > 0.009) _kv('الباقي', egp(remaining), bold: true, color: _red),
              ]),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        _grandTotal(isInstallment ? 'الإجمالي بالتقسيط' : 'المطلوب', grand),
        if (installments.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text('جدول الأقساط', style: _t(13, bold: true, color: _brand)),
          pw.SizedBox(height: 6),
          _table(
            ['القسط', 'تاريخ الاستحقاق', 'القيمة', 'المدفوع', 'الحالة'],
            [
              for (final it in installments)
                [
                  '${it.seq}',
                  showDate(it.dueDate),
                  money(it.amount),
                  money(it.paid),
                  switch (it.stateOn(today)) {
                    InstallmentState.paid => 'مدفوع',
                    InstallmentState.partial => 'مدفوع جزء',
                    InstallmentState.overdue => 'متأخر',
                    InstallmentState.due => 'لم يستحق',
                  },
                ],
            ],
            flex: [0.7, 1.6, 1.3, 1.3, 1.2],
          ),
        ],
        if (s(inv['notes']).isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text('ملاحظات: ${s(inv['notes'])}', style: _t(10.5)),
        ],
        _signatures(kind.startsWith('purchase') ? 'توقيع المورد' : 'توقيع العميل', 'المسئول'),
      ],
    );
  }

  // ---------------------------------------------------------------- crops

  static Future<Uint8List> cropTrade(String tradeId) async {
    final t = (await app.crops.trade(tradeId))!;
    final isSale = t['kind'] == 'sale';
    final unit = s(t['unit_name']);
    final kpu = n(t['kg_per_unit']);
    final c = CropCalc.fromRow(t);
    final sacks = s(t['weigh_mode']) == 'sacks';
    final sackWeights = sackWeightsOf(t['sack_weights']);
    final balance = await app.accounts.partyBalance(s(t['party_id']));
    final weights = <List<String>>[
      if (sacks) ...[
        ['عدد الشكاير', intf(c.bagsCount)],
        ['وزن الشكاير', '${qty(c.grossKg)} كجم'],
      ] else ...[
        ['القايم (محمّل)', '${qty(c.grossKg)} كجم'],
        if (c.tareKg > 0) ...[
          ['الفارغ', '${qty(c.tareKg)} كجم'],
          ['الحمولة (القايم - الفارغ)', '${qty(c.loadKg)} كجم'],
        ],
      ],
      if (c.bagsKg > 0) ['خصم الشكاير الفاضية (${qty(c.bagsCount)} × ${qty(c.bagWeightKg)} كجم)', '${qty(c.bagsKg)} كجم'],
      if (c.moistureDeductionKg > 0) ['خصم الرطوبة', '${qty(c.moistureDeductionKg)} كجم'],
      if (c.impuritiesDeductionKg > 0) ['خصم الشوائب', '${qty(c.impuritiesDeductionKg)} كجم'],
      if (c.otherDeductionKg > 0) ['خصم تاني', '${qty(c.otherDeductionKg)} كجم'],
      ['الوزن الصافي', kpu > 1 ? '${qty(c.netKg)} كجم\n${unitsOf(c.netKg, unit, kpu)}' : '${qty(c.netKg)} كجم'],
    ];
    return _document(
      title: isSale ? 'فاتورة بيع محصول' : 'بون توريد محصول',
      number: s(t['number']),
      date: s(t['date']),
      body: [
        _box([
          _kv(isSale ? 'التاجر / المشتري' : 'الفلاح / المورد', s(t['party_name']), bold: true),
          if (s(t['party_phone']).isNotEmpty) _kv('التليفون', s(t['party_phone'])),
          _kv('المحصول', s(t['crop_name']), bold: true),
          if (s(t['warehouse_name']).isNotEmpty) _kv('المخزن / الشونة', s(t['warehouse_name'])),
          if (s(t['ticket_no']).isNotEmpty) _kv('رقم الكارتة / بون الميزان', s(t['ticket_no'])),
          if (s(t['vehicle']).isNotEmpty) _kv('العربية / السواق', s(t['vehicle'])),
        ], color: _brandSoft, border: _brandSoft),
        pw.SizedBox(height: 12),
        pw.Text(sacks ? 'الوزن بالشكارة' : 'الوزن على الباسكول', style: _t(12.5, bold: true, color: _brand)),
        pw.SizedBox(height: 6),
        _table(['البيان', 'الوزن'], weights, flex: [3, 2], boldLastRow: true, align: const [pw.TextAlign.right]),
        if (sackWeights.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text('أوزان الشكاير واحدة واحدة', style: _t(10.5, bold: true, color: _grey)),
          pw.SizedBox(height: 4),
          pw.Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var i = 0; i < sackWeights.length; i++)
                pw.Container(
                  width: 44,
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(3)),
                  child: pw.Column(
                    children: [
                      pw.Text('${i + 1}', style: _t(7, color: _grey)),
                      pw.Text(qty(sackWeights[i]), style: _t(9.5, bold: true)),
                    ],
                  ),
                ),
            ],
          ),
        ],
        pw.SizedBox(height: 12),
        _box([
          _kv('سعر ال$unit', egp(c.pricePerUnit)),
          _kv('قيمة المحصول', egp(c.subtotal), bold: true),
          if (c.expenses > 0) ...[
            if (c.freight > 0) _kv('نولون', egp(c.freight)),
            if (c.loading > 0) _kv('عتالة وتحميل', egp(c.loading)),
            if (c.otherExpenses > 0) _kv('مصاريف أخرى', egp(c.otherExpenses)),
            _kv('المصاريف', c.expensesOnParty ? (isSale ? 'على حساب التاجر' : 'مخصومة من الفلاح') : 'على حسابنا'),
          ],
          _kv(isSale ? 'المقبوض' : 'المدفوع', egp(c.paid), color: _green),
          if (c.remaining > 0.009)
            _kv(isSale ? 'الباقي على التاجر' : 'الباقي للفلاح', egp(c.remaining), bold: true, color: _red),
          if (c.remaining < -0.009) _kv('مدفوع زيادة', egp(-c.remaining), bold: true),
        ]),
        pw.SizedBox(height: 10),
        _grandTotal('صافي الحساب', c.partyTotal),
        pw.SizedBox(height: 8),
        _kv('رصيد حسابك كله لحد النهارده', balanceForParty(balance), bold: true),
        if (s(t['notes']).isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text('ملاحظات: ${s(t['notes'])}', style: _t(10.5)),
        ],
        _signatures(isSale ? 'توقيع التاجر' : 'توقيع الفلاح', 'المسئول'),
      ],
    );
  }

  // ---------------------------------------------------------------- labels

  /// Price labels to stick on the goods: the shop name, the product, its
  /// number as a scannable barcode, and today's selling price.
  ///
  /// [products] are rows of [AppliancesRepo.products] paired with how many
  /// stickers each one needs. Everything is read now, so a label always
  /// carries the current price.
  /// An A4 sheet of price stickers, three to a row.
  ///
  /// The rows are the page's children, so the document can be split between
  /// them: one giant [pw.Wrap] of every sticker cannot be paginated, and on a
  /// few hundred labels it took the whole app down with it.
  static const labelsPerRow = 3;

  static Future<Uint8List> labels(List<(DbRow product, int count)> products, {bool wholesale = false}) async {
    final doc = pw.Document(theme: await _loadTheme());
    final shop = app.companyName;
    final cells = <pw.Widget>[];
    for (final (p, count) in products) {
      final code = s(p['barcode']);
      final price = n(p[wholesale ? 'wholesale_price' : 'retail_price']);
      // The bars carry the number and the price behind it, and the digits
      // under them are spaced so the price can be read off the end.
      final data = ProductCode.labelBarcode(code, price);
      for (var i = 0; i < count; i++) {
        cells.add(
          pw.Container(
            width: 170,
            height: 108,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.7)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(shop, style: _t(8, color: _grey), maxLines: 1),
                pw.SizedBox(height: 1),
                pw.SizedBox(
                  height: 22,
                  child: pw.Text(
                    s(p['name']),
                    style: _t(9.5, bold: true),
                    textAlign: pw.TextAlign.center,
                    maxLines: 2,
                    overflow: pw.TextOverflow.clip,
                  ),
                ),
                pw.Text(egp(price), style: _t(15, bold: true)),
                pw.SizedBox(height: 2),
                pw.Expanded(
                  child: pw.BarcodeWidget(
                    data: data,
                    barcode: pw.Barcode.code128(escapes: true),
                    drawText: false,
                  ),
                ),
                // One number, one size, one colour: the last five digits are
                // the price, and only the people working here know that.
                pw.Text(ProductCode.printed(code, price), style: _t(9)),
              ],
            ),
          ),
        );
      }
    }
    final rows = <pw.Widget>[];
    for (var i = 0; i < cells.length; i += labelsPerRow) {
      final end = i + labelsPerRow < cells.length ? i + labelsPerRow : cells.length;
      rows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.start,
            children: [
              for (var j = i; j < end; j++) ...[
                cells[j],
                if (j < end - 1) pw.SizedBox(width: 8),
              ],
            ],
          ),
        ),
      );
    }
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        textDirection: pw.TextDirection.rtl,
        build: (_) => rows,
      ),
    );
    return doc.save();
  }

  // ---------------------------------------------------------------- receipt

  /// Small cashier receipt for 80 mm thermal printers (also fine on WhatsApp).
  static Future<Uint8List> receipt(String invoiceId) async {
    final inv = (await app.appliances.invoice(invoiceId))!;
    final lines = await app.appliances.invoiceLines(invoiceId);
    final theme = await _loadTheme();
    final settings = app.settings;
    final remaining = AppliancesRepo.remainingOf(inv);
    final paid = roundMoney(n(inv['grand_total']) - remaining);
    final created = DateTime.tryParse(s(inv['created_at']))?.toLocal();
    final time = created == null ? '' : '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
    final customer = s(inv['party_name']).isNotEmpty ? s(inv['party_name']) : s(inv['customer_name']);
    final cashier = s(inv['created_by_name']);
    pw.Widget center(String text, {double size = 9, bool bold = false, PdfColor? color}) =>
        pw.Text(text, textAlign: pw.TextAlign.center, style: _t(size, bold: bold, color: color));
    pw.Widget dashed() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Divider(height: 1, thickness: 0.7, borderStyle: pw.BorderStyle.dashed, color: PdfColors.grey600),
        );
    final doc = pw.Document(title: 'إيصال', author: app.companyName);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            center(app.companyName, size: 15, bold: true),
            center(Division.long[app.division] ?? '', size: 8.5, color: _grey),
            if ((settings['company_phone'] ?? '').isNotEmpty) center('ت: ${settings['company_phone']}', size: 8.5),
            if ((settings['company_address'] ?? '').isNotEmpty) center(settings['company_address']!, size: 8.5),
            dashed(),
            _kv('${invoiceKinds[inv['kind']] ?? 'فاتورة'} رقم', s(inv['number']), size: 9),
            _kv('التاريخ', '${showDate(inv['date'])} $time', size: 9),
            _kv('العميل', customer.isEmpty ? 'نقدي' : customer, size: 9),
            _kv('الدفع', paymentTypes[inv['payment_type']] ?? '', size: 9),
            dashed(),
            for (final l in lines)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Text(s(l['product_name']), style: _t(9.5, bold: true)),
                    pw.Row(
                      children: [
                        pw.Expanded(child: pw.Text('${qty(n(l['qty']))} × ${money(n(l['price']))}', style: _t(9))),
                        pw.Text(money(n(l['total'])), style: _t(9.5)),
                      ],
                    ),
                  ],
                ),
              ),
            dashed(),
            _kv('الإجمالي', egp(n(inv['subtotal'])), size: 9.5),
            if (n(inv['discount']) > 0) _kv('الخصم', egp(n(inv['discount'])), size: 9.5),
            if (inv['payment_type'] == 'installment') _kv('الإجمالي بالتقسيط', egp(n(inv['grand_total'])), size: 9.5),
            _kv('المطلوب', egp(n(inv['payment_type'] == 'installment' ? inv['grand_total'] : inv['total'])), bold: true, size: 10.5),
            _kv('المدفوع', egp(paid), size: 9.5),
            if (remaining > 0.009) _kv('الباقي', egp(remaining), bold: true, size: 9.5),
            dashed(),
            if ((settings['invoice_footer'] ?? '').isNotEmpty) center(settings['invoice_footer']!, size: 8.5),
            pw.SizedBox(height: 2),
            center('شكراً لزيارتكم', size: 10, bold: true),
            if (cashier.isNotEmpty) center('الكاشير: $cashier', size: 8, color: _grey),
          ],
        ),
      ),
    );
    return doc.save();
  }

  // ---------------------------------------------------------------- statement

  /// كشف الحساب sent to the customer: every movement with its date, what it
  /// was, and the running balance in his own words (عليه / له).
  static Future<Uint8List> statement(String partyId, {String? from, String? to, String? periodText}) async {
    final p = (await app.accounts.party(partyId))!;
    final rows = await app.accounts.partyLedger(partyId, from: from, to: to);
    final balance = n(p['balance']);
    final endBalance = rows.isEmpty ? balance : n(rows.last['balance']);
    var totalDebit = 0.0, totalCredit = 0.0;
    for (final r in rows) {
      totalDebit += n(r['debit']);
      totalCredit += n(r['credit']);
    }
    String side(double v) => v > 0.009 ? 'عليه' : (v < -0.009 ? 'له' : 'خالص');
    String what(DbRow r) => [
          s(r['title']),
          if (s(r['number']).isNotEmpty) '(${s(r['number'])})',
          if (s(r['notes']).isNotEmpty) '- ${s(r['notes'])}',
          if (s(r['handled_by']).isNotEmpty) '- ${r['kind'] == 'receipt' ? 'استلمها' : 'سلّمها'} ${s(r['handled_by'])}',
        ].join(' ');
    return _document(
      title: 'كشف حساب',
      date: todayStr(),
      body: [
        _box([
          _kv('الاسم', s(p['name']), bold: true),
          if (s(p['phone']).isNotEmpty) _kv('التليفون', s(p['phone'])),
          if (s(p['address']).isNotEmpty) _kv('العنوان', s(p['address'])),
          _kv('الفترة', periodText ?? 'الحساب كله'),
        ], color: _paper, border: _paperLine),
        pw.SizedBox(height: 12),
        _table(
          ['التاريخ', 'البيان', 'عليه', 'له', 'الرصيد'],
          [
            for (final r in rows)
              [
                showDate(r['date']),
                what(r),
                n(r['debit']) > 0 ? money(n(r['debit'])) : '',
                n(r['credit']) > 0 ? money(n(r['credit'])) : '',
                '${money(n(r['balance']).abs())} ${side(n(r['balance']))}',
              ],
            ['', 'الإجمالي', money(totalDebit), money(totalCredit), ''],
          ],
          flex: [1.3, 4.6, 1.3, 1.3, 1.8],
          boldLastRow: true,
          align: const [pw.TextAlign.center, pw.TextAlign.right],
        ),
        pw.SizedBox(height: 12),
        _box([
          _kv(
            to != null && to.compareTo(todayStr()) < 0 ? 'الرصيد في آخر الفترة' : 'الرصيد',
            balanceForParty(endBalance),
            bold: true,
            color: endBalance > 0.009 ? _red : (endBalance < -0.009 ? _green : null),
          ),
          if ((endBalance - balance).abs() > 0.009) _kv('الرصيد النهارده', balanceForParty(balance), bold: true),
          if (balance > 0.009 && s(p['collect_on']).isNotEmpty) _kv('ميعاد السداد', showDate(p['collect_on'])),
        ], color: _paper, border: _paperLine),
      ],
    );
  }

  // ---------------------------------------------------------------- voucher

  static Future<Uint8List> voucher(String voucherId) async {
    final v = (await app.accounts.voucher(voucherId))!;
    final kind = s(v['kind']);
    final isIn = kind == 'receipt' || kind == 'deposit';
    final party = s(v['party_name']);
    final label = switch (kind) {
      'receipt' || 'deposit' => 'استلمنا مبلغ',
      'expense' => 'مصروف بمبلغ',
      'debit_adj' => 'اتضاف على الحساب',
      'credit_adj' => 'اتخصم من الحساب',
      _ => 'دفعنا مبلغ',
    };
    return _document(
      title: voucherKinds[kind] ?? 'سند',
      number: s(v['number']),
      date: s(v['date']),
      body: [
        _grandTotal(label, n(v['amount'])),
        pw.SizedBox(height: 12),
        _box([
          if (party.isNotEmpty) _kv(isIn ? 'من' : 'الاسم', party, bold: true),
          if (s(v['category']).isNotEmpty) _kv('البند', s(v['category'])),
          if (s(v['invoice_number']).isNotEmpty) _kv('عن فاتورة رقم', s(v['invoice_number'])),
          if (s(v['box_name']).isNotEmpty) _kv('الخزنة', s(v['box_name'])),
          if (s(v['handled_by']).isNotEmpty) _kv(isIn ? 'اللي استلم الفلوس' : 'اللي دفع الفلوس', s(v['handled_by'])),
          if (s(v['notes']).isNotEmpty) _kv('البيان', s(v['notes'])),
        ]),
        if (s(v['party_id']).isNotEmpty) ...[
          pw.SizedBox(height: 10),
          _kv('رصيد الحساب بعد كده', balanceForParty(await app.accounts.partyBalance(s(v['party_id']))), bold: true),
        ],
        _signatures(isIn ? 'توقيع اللي دفع' : 'توقيع المستلم', 'المسئول'),
      ],
    );
  }

  // ---------------------------------------------------------------- season

  static Future<Uint8List> season(SeasonReport r,
      {required String title, required String from, required String to, String cropName = ''}) async {
    String avg(DbRow x) {
      final kpu = n(x['kg_per_unit']);
      final units = kpu > 0 ? n(x['net_kg']) / kpu : 0;
      return units > 0 ? money(n(x['value']) / units) : '-';
    }

    final crops = <String, DbRow>{for (final x in [...r.purchases, ...r.sales]) s(x['crop_id']): x};
    List<String> partyRow(DbRow p) => [
          s(p['name']),
          intf(n(p['cnt'])),
          qty(n(p['net_kg'])),
          money(n(p['party_total'])),
          balanceForParty(n(p['balance'])).replaceAll('عليك لينا', 'عليه').replaceAll('ليك عندنا', 'له'),
        ];
    return _document(
      title: 'تقرير موسم',
      date: todayStr(),
      body: [
        _box([
          _kv('الموسم', '$title${cropName.isEmpty ? '' : ' - $cropName'}', bold: true),
          _kv('الفترة', 'من ${showDate(from)} لحد ${showDate(to)}'),
          _kv('التوريد', '${intf(r.tripsIn)} نقلة  •  ${qty(r.boughtKg)} كجم  •  ${egp(r.boughtAmount)}'),
          _kv('البيع', '${intf(r.tripsOut)} نقلة  •  ${qty(r.soldKg)} كجم  •  ${egp(r.soldAmount)}'),
          _kv('اتخصم في التوريد', '${qty(r.deductedKg)} كجم'),
          if (r.advancesTotal > 0) _kv('السلف', egp(r.advancesTotal)),
          if (r.otherExpenses > 0) _kv('المصروفات', egp(r.otherExpenses)),
          _kv(r.netProfit >= 0 ? 'صافي المكسب' : 'صافي الخسارة', egp(r.netProfit.abs()),
              bold: true, color: r.netProfit >= 0 ? _green : _red),
        ], color: _brandSoft, border: _brandSoft),
        pw.SizedBox(height: 12),
        pw.Text('حسب المحصول', style: _t(12.5, bold: true, color: _brand)),
        pw.SizedBox(height: 6),
        _table(
          ['المحصول', 'توريد (كجم)', 'متوسط الشراء', 'بيع (كجم)', 'متوسط البيع', 'المكسب'],
          [
            for (final e in crops.entries)
              () {
                final buy = r.purchases.where((x) => x['crop_id'] == e.key).firstOrNull;
                final sell = r.sales.where((x) => x['crop_id'] == e.key).firstOrNull;
                final profit = r.profit.where((x) => x['id'] == e.key).firstOrNull;
                return [
                  '${s(e.value['name'])} (${s(e.value['unit_name'])})',
                  buy == null ? '-' : qty(n(buy['net_kg'])),
                  buy == null ? '-' : avg(buy),
                  sell == null ? '-' : qty(n(sell['net_kg'])),
                  sell == null ? '-' : avg(sell),
                  profit == null ? '-' : money(n(profit['profit'])),
                ];
              }(),
          ],
          flex: [2.2, 1.4, 1.3, 1.4, 1.3, 1.3],
        ),
        if (r.farmers.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text('الفلاحين والموردين', style: _t(12.5, bold: true, color: _brand)),
          pw.SizedBox(height: 6),
          _table(['الاسم', 'النقلات', 'الصافي (كجم)', 'القيمة', 'الحساب النهارده'], [for (final p in r.farmers) partyRow(p)],
              flex: [2.6, 0.9, 1.3, 1.4, 1.8], align: const [pw.TextAlign.right]),
        ],
        if (r.traders.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text('التجار والمصانع', style: _t(12.5, bold: true, color: _brand)),
          pw.SizedBox(height: 6),
          _table(['الاسم', 'النقلات', 'الصافي (كجم)', 'القيمة', 'الحساب النهارده'], [for (final p in r.traders) partyRow(p)],
              flex: [2.6, 0.9, 1.3, 1.4, 1.8], align: const [pw.TextAlign.right]),
        ],
        if (r.advances.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text('السلف', style: _t(12.5, bold: true, color: _brand)),
          pw.SizedBox(height: 6),
          _table(['الاسم', 'عدد السلف', 'المبلغ'], [
            for (final a in r.advances) [s(a['name']), intf(n(a['cnt'])), money(n(a['amount']))],
          ], flex: [3, 1, 1.5], align: const [pw.TextAlign.right]),
        ],
        if (r.expenses.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text('المصروفات', style: _t(12.5, bold: true, color: _brand)),
          pw.SizedBox(height: 6),
          _table(['البند', 'المبلغ'], [for (final e in r.expenses) [s(e['category']), money(n(e['amount']))]],
              flex: [3, 1.5], align: const [pw.TextAlign.right]),
        ],
      ],
    );
  }
}
