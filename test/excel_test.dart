import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trade_erp/core/app_state.dart';
import 'package:trade_erp/core/db/prefs.dart';
import 'package:trade_erp/core/db/schema.dart';
import 'package:trade_erp/core/util/format.dart';
import 'package:trade_erp/features/common/excel_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('excel_test');
    await databaseFactoryFfi.setDatabasesPath(dir.path);
    app = AppState();
    app.prefs = await Prefs.open(path: '${dir.path}${Platform.pathSeparator}prefs.db', factory: databaseFactoryFfi);
    await app.prefs.set('mode', 'local');
    await app.prefs.set('person', 'أحمد');
    await app.openDivision(Division.appliances);
  });

  tearDown(() async {
    await app.db.close();
    await app.prefs.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  List<Object?> row(Sheet sheet, int i) => [for (final c in sheet.row(i)) c?.value];

  Object? valueOf(CellValue? v) => switch (v) {
        TextCellValue() => v.value.text,
        IntCellValue() => v.value,
        DoubleCellValue() => v.value,
        DateCellValue() => dateStr(v.asDateTimeLocal()),
        _ => v,
      };

  test('showroom stock sheet: codes stay text, quantity in every warehouse, right to left', () async {
    final main = s((await app.crops.warehouses()).first['id']);
    final upstairs = await app.crops.saveWarehouse({'name': 'مخزن الدور التاني'});
    final fridge = await app.appliances.saveProduct({
      'name': 'تلاجة 16 قدم',
      'barcode': '0012345678901',
      'brand': 'شارب',
      'model': 'SJ-48',
      'category': 'ثلاجات',
      'cost_price': 15000,
      'retail_price': 17500,
      'wholesale_price': 16800,
      'min_qty': 2,
    });
    await app.crops.saveStockMove({
      'kind': 'adjust',
      'date': todayStr(),
      'item_type': 'product',
      'item_id': fridge,
      'warehouse_id': main,
      'qty': 5,
    });
    await app.crops.saveStockMove({
      'kind': 'transfer',
      'date': todayStr(),
      'item_type': 'product',
      'item_id': fridge,
      'warehouse_id': main,
      'to_warehouse_id': upstairs,
      'qty': 2,
    });

    final book = Excel.decodeBytes(ExcelExport.encode([await ExcelExport.products()]));
    expect(book.tables.keys, ['الأصناف']);
    final sheet = book['الأصناف'];
    expect(sheet.isRTL, isTrue);

    final head = [for (final v in row(sheet, 0)) valueOf(v as CellValue?)];
    final line = {
      for (var c = 0; c < head.length; c++) s(head[c]): valueOf(row(sheet, 1)[c] as CellValue?),
    };
    expect(sheet.maxRows, 2);
    expect(line['رقم الصنف (الكود)'], '0012345678901');
    expect(row(sheet, 1).first, isA<TextCellValue>());
    expect(line['اسم الصنف'], 'تلاجة 16 قدم');
    expect(line['الكمية الموجودة'], 5);
    expect(line['في ${(await app.crops.warehouses()).firstWhere((w) => w['id'] == main)['name']}'], 3);
    expect(line['في مخزن الدور التاني'], 2);
    expect(line['سعر الشراء'], 15000.0);
    expect(line['سعر القطاعي'], 17500.0);
    expect(line['قيمة المخزون بالتكلفة'], 75000.0);
    expect(line['الحالة'], 'شغال');
    expect(line['المعرّف (ID)'], fridge);
  });

  test('the full export has every kind of record, each sheet right to left', () async {
    final party = await app.accounts.saveParty({'name': 'أم أحمد', 'kind': 'customer', 'phone': '01066666666'});
    await app.notes.save({'kind': 'task', 'body': 'طلبية مراوح'});
    final book = Excel.decodeBytes(ExcelExport.encode(await ExcelExport.everything()));
    expect(book.tables.keys, [
      'ملخص',
      'الأصناف',
      'الفواتير',
      'أصناف الفواتير',
      'الأقساط',
      'الحسابات',
      'حركات الفلوس',
      'الخزن',
      'المخازن',
      'حركات المخزن',
      'التذكرة',
    ]);
    for (final sheet in book.tables.values) {
      expect(sheet.isRTL, isTrue, reason: sheet.sheetName);
    }
    final accounts = book['الحسابات'];
    expect(valueOf(row(accounts, 1).first as CellValue?), 'أم أحمد');
    // Phone numbers keep their leading zero.
    expect(valueOf(row(accounts, 1)[2] as CellValue?), '01066666666');
    expect(valueOf(row(accounts, 1).last as CellValue?), party);
    expect(valueOf(row(book['التذكرة'], 1)[1] as CellValue?), 'طلبية مراوح');
  });
}
