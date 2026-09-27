// Renders sample PDFs from the demo databases for a visual check:
//   flutter test tool/demo_db_test.dart
//   flutter test tool/pdf_preview_test.dart
// Output: build/pdf_preview/*.pdf
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trade_erp/core/app_state.dart';
import 'package:trade_erp/core/db/prefs.dart';
import 'package:trade_erp/core/db/schema.dart';
import 'package:trade_erp/core/util/format.dart';
import 'package:trade_erp/features/common/pdf_docs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('sample pdfs', () async {
    final dbDir = await databaseFactoryFfi.getDatabasesPath();
    Directory(dbDir).createSync(recursive: true);
    for (final f in ['erp_crops.db', 'erp_appliances.db']) {
      File('build/demo/$f').copySync('$dbDir${Platform.pathSeparator}$f');
    }
    app = AppState();
    app.prefs = await Prefs.open(path: '$dbDir${Platform.pathSeparator}erp_prefs_preview.db', factory: databaseFactoryFfi);
    await app.prefs.set('mode', 'local');
    final out = Directory('build/pdf_preview')..createSync(recursive: true);
    Future<void> save(String name, Future<List<int>> bytes) async =>
        File('${out.path}${Platform.pathSeparator}$name.pdf').writeAsBytesSync(await bytes);

    await app.openDivision(Division.appliances);
    final inst = await app.db.q1("SELECT id FROM invoices WHERE kind = 'sale' AND payment_type = 'installment' LIMIT 1");
    await save('invoice_installment', PdfDocs.invoice(s(inst!['id'])));
    final cash = await app.db.q1("SELECT id FROM invoices WHERE source = 'pos' ORDER BY date DESC LIMIT 1");
    await save('receipt', PdfDocs.receipt(s(cash!['id'])));
    final products = await app.appliances.products();
    await save('labels', PdfDocs.labels([for (final p in products.take(5)) (p, 2)]));
    final customer = await app.db.q1("SELECT id FROM parties WHERE name = 'أم أحمد'");
    await save('statement_customer', PdfDocs.statement(s(customer!['id'])));
    final voucher = await app.db.q1("SELECT id FROM vouchers WHERE kind = 'receipt' LIMIT 1");
    await save('voucher', PdfDocs.voucher(s(voucher!['id'])));

    await app.openDivision(Division.crops);
    final scale = await app.db.q1("SELECT id FROM crop_trades WHERE weigh_mode = 'scale' AND tare_kg > 0 LIMIT 1");
    await save('crop_scale', PdfDocs.cropTrade(s(scale!['id'])));
    final sacks = await app.db.q1("SELECT id FROM crop_trades WHERE weigh_mode = 'sacks' LIMIT 1");
    await save('crop_sacks', PdfDocs.cropTrade(s(sacks!['id'])));
    final farmer = await app.db.q1("SELECT id FROM parties WHERE name = 'الحاج محمود عبد الله'");
    await save('statement_farmer', PdfDocs.statement(s(farmer!['id'])));
    final from = dateStr(DateTime.now().subtract(const Duration(days: 120)));
    final report = await app.reports.season(from, todayStr());
    await save('season', PdfDocs.season(report, title: 'موسم القمح', from: from, to: todayStr()));
  });
}
