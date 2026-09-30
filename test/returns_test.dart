import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trade_erp/core/app_state.dart';
import 'package:trade_erp/core/db/prefs.dart';
import 'package:trade_erp/core/db/schema.dart';
import 'package:trade_erp/core/util/format.dart';
import 'package:trade_erp/data/appliances_repo.dart';

/// المرتجعات: a customer brings goods back, and the pieces, the money and the
/// sales figures all have to move together without anybody fixing them by
/// hand.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('returns_test');
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

  Future<String> warehouse() async => s((await app.crops.warehouses()).first['id']);

  Future<String> addProduct({String name = 'ثلاجة', double retail = 13000, double stock = 5}) async {
    final id = await app.appliances.saveProduct({
      'name': name,
      'cost_price': 10000,
      'retail_price': retail,
    });
    await app.crops.saveStockMove({
      'kind': 'adjust',
      'date': todayStr(),
      'item_type': 'product',
      'item_id': id,
      'warehouse_id': await warehouse(),
      'qty': stock,
    });
    return id;
  }

  Future<String> sell(
    String productId,
    String partyId, {
    double qty = 3,
    double price = 13000,
    double discount = 0,
  }) async =>
      app.appliances.saveInvoice(
        header: {
          'kind': 'sale',
          'date': todayStr(),
          'party_id': partyId,
          'warehouse_id': await warehouse(),
          'payment_type': 'credit',
          'subtotal': qty * price,
          'discount': discount,
          'total': qty * price - discount,
          'grand_total': qty * price - discount,
          'paid_amount': 0,
        },
        lines: [InvoiceLineDraft(productId: productId, name: 'ثلاجة', qty: qty, price: price)],
      );

  Future<String> giveBack(
    String saleId,
    String productId,
    String partyId, {
    required double qty,
    required double price,
  }) async =>
      app.appliances.saveInvoice(
        header: {
          'kind': 'sale_return',
          'date': todayStr(),
          'party_id': partyId,
          'warehouse_id': await warehouse(),
          'payment_type': 'credit',
          'subtotal': qty * price,
          'total': qty * price,
          'grand_total': qty * price,
          'paid_amount': 0,
          'ref_invoice_id': saleId,
        },
        lines: [InvoiceLineDraft(productId: productId, name: 'ثلاجة', qty: qty, price: price)],
      );

  test('the goods come back to the shelf and come off the customer', () async {
    final product = await addProduct(stock: 5);
    final customer = await app.accounts.saveParty({'name': 'أم أحمد', 'kind': 'customer'});
    final sale = await sell(product, customer, qty: 3);

    expect(await app.appliances.stockAt(product, null), 2);
    expect(n((await app.accounts.party(customer))!['balance']), 39000);

    // What the returns screen offers: everything that went out, nothing back yet.
    var lines = await app.appliances.returnableLines(sale);
    expect(lines.length, 1);
    expect(n(lines.first['qty']), 3);
    expect(n(lines.first['returned_qty']), 0);
    expect(n(lines.first['price']), 13000);

    // One piece comes back.
    await giveBack(sale, product, customer, qty: 1, price: 13000);

    expect(await app.appliances.stockAt(product, null), 3);
    expect(n((await app.accounts.party(customer))!['balance']), 26000);

    // The screen now knows that piece is already back.
    lines = await app.appliances.returnableLines(sale);
    expect(n(lines.first['returned_qty']), 1);
    expect(n(lines.first['qty']) - n(lines.first['returned_qty']), 2);

    // And the sale is netted down in the figures the owner reads.
    final sales = await app.appliances.salesSummary(todayStr(), todayStr());
    expect(n(sales['returns']), 13000);
  });

  test('nothing can come back twice', () async {
    final product = await addProduct(stock: 5);
    final customer = await app.accounts.saveParty({'name': 'أم أحمد', 'kind': 'customer'});
    final sale = await sell(product, customer, qty: 2);

    await giveBack(sale, product, customer, qty: 2, price: 13000);
    final lines = await app.appliances.returnableLines(sale);
    // The screen has nothing left to offer, so it cannot be returned again.
    expect(n(lines.first['qty']) - n(lines.first['returned_qty']), 0);
    expect(await app.appliances.stockAt(product, null), 5);
  });

  test('a discounted invoice gives back what the customer really paid', () async {
    final product = await addProduct(stock: 5);
    final customer = await app.accounts.saveParty({'name': 'أم أحمد', 'kind': 'customer'});
    // Sold at 13,000 each but the invoice was rounded down by 3,000.
    final sale = await sell(product, customer, qty: 3, discount: 3000);

    final lines = await app.appliances.returnableLines(sale);
    expect(n(lines.first['price']), closeTo(12000, 0.01));
  });

  test('a return is listed on the invoice it came out of', () async {
    final product = await addProduct(stock: 5);
    final customer = await app.accounts.saveParty({'name': 'أم أحمد', 'kind': 'customer'});
    final sale = await sell(product, customer, qty: 3);
    final ret = await giveBack(sale, product, customer, qty: 1, price: 13000);

    final returns = await app.appliances.returnsOf(sale);
    expect(returns.length, 1);
    expect(s(returns.first['id']), ret);
    expect(n(returns.first['grand_total']), 13000);
    expect(await app.appliances.returnsOf(ret), isEmpty);
  });
}
