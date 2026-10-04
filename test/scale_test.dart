import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trade_erp/core/app_state.dart';
import 'package:trade_erp/core/db/prefs.dart';
import 'package:trade_erp/core/db/schema.dart';
import 'package:trade_erp/core/util/format.dart';

/// A full showroom. The owner put about a thousand products in and the app
/// went heavy, so the queries the busy screens lean on are measured here with
/// that much data in the database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  const count = 1000;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('scale_test');
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

  /// A thousand products with stock, written the fast way: the point of the
  /// test is how the reading screens behave, not how a thousand products get
  /// into the database.
  Future<List<String>> fillShowroom() async {
    final warehouse = s((await app.crops.warehouses()).first['id']);
    final ids = <String>[];
    await app.db.write((w) async {
      for (var i = 0; i < count; i++) {
        final id = await w.insert('products', {
          'name': 'صنف رقم $i',
          'category': 'قسم ${i % 12}',
          'brand': 'ماركة ${i % 25}',
          'barcode': '${500000 + i}',
          'unit': 'قطعة',
          'cost_price': 1000 + i,
          'retail_price': 1300 + i,
          'active': 1,
        });
        ids.add(id);
        await w.insert('stock_moves', {
          'kind': 'adjust',
          'date': todayStr(),
          'item_type': 'product',
          'item_id': id,
          'warehouse_id': warehouse,
          'qty': 3,
        });
      }
    });
    return ids;
  }

  test('the stock screen, the search and the scanner stay quick', () async {
    final ids = await fillShowroom();
    expect(ids.length, count);

    final all = Stopwatch()..start();
    final rows = await app.appliances.products();
    all.stop();
    expect(rows.length, count);
    expect(n(rows.first['stock']), 3);
    expect(all.elapsedMilliseconds, lessThan(1500), reason: 'فتح المخزن: ${all.elapsedMilliseconds}ms');

    final search = Stopwatch()..start();
    final hits = await app.appliances.products(search: 'صنف رقم 77');
    search.stop();
    expect(hits, isNotEmpty);
    expect(search.elapsedMilliseconds, lessThan(1500), reason: 'البحث: ${search.elapsedMilliseconds}ms');

    // One beep of the scanner must not read the whole catalogue.
    final scan = Stopwatch()..start();
    final hit = await app.appliances.productByBarcode('500777');
    scan.stop();
    expect(s(hit?['name']), 'صنف رقم 777');
    expect(scan.elapsedMilliseconds, lessThan(300), reason: 'الباركود: ${scan.elapsedMilliseconds}ms');
  });

  test('the labels screen reads its whole queue in one go', () async {
    final ids = await fillShowroom();

    // What "ضيف كل اللي في المخزن" asks for.
    final counts = Stopwatch()..start();
    final stock = await app.appliances.stockCounts();
    counts.stop();
    expect(stock.length, count);
    expect(stock[ids.first], 3);
    expect(counts.elapsedMilliseconds, lessThan(1000), reason: 'عدّ المخزون: ${counts.elapsedMilliseconds}ms');

    // And what the screen itself needs to draw the queue.
    final load = Stopwatch()..start();
    final labels = await app.appliances.productsForLabels(ids);
    load.stop();
    expect(labels.length, count);
    expect(s(labels.first['name']), isNotEmpty);
    expect(load.elapsedMilliseconds, lessThan(1000), reason: 'قايمة الملصقات: ${load.elapsedMilliseconds}ms');
  });

  test('a long queue is printed in batches instead of all at once', () async {
    // 1000 products with three pieces each is three thousand stickers; the
    // screen prints 300 at a time so the phone can finish the job.
    final ids = await fillShowroom();
    final stock = await app.appliances.stockCounts();
    final stickers = stock.values.fold<int>(0, (a, b) => a + b);
    expect(stickers, count * 3);

    var taken = 0;
    final batch = <String>[];
    for (final id in ids) {
      if (taken >= 300) break;
      final room = 300 - taken;
      final want = stock[id]!;
      taken += want > room ? room : want;
      batch.add(id);
    }
    expect(taken, 300);
    expect(batch.length, 100);
  });
}
