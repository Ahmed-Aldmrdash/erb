import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trade_erp/core/app_state.dart';
import 'package:trade_erp/core/db/prefs.dart';
import 'package:trade_erp/core/db/schema.dart';
import 'package:trade_erp/core/util/format.dart';
import 'package:trade_erp/features/pos/pos_cart.dart';

/// The cashier's basket is written down on the phone, so a sale being rung up
/// survives leaving the screen, going into the installment invoice, and even
/// closing the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('cart_test');
    await databaseFactoryFfi.setDatabasesPath(dir.path);
    app = AppState();
    app.prefs = await Prefs.open(path: '${dir.path}${Platform.pathSeparator}prefs.db', factory: databaseFactoryFfi);
    await app.prefs.set('mode', 'local');
    await app.prefs.set('person', 'أحمد');
    await app.openDivision(Division.appliances);
    PosCart.instance.clear();
  });

  tearDown(() async {
    PosCart.instance.clear();
    await app.db.close();
    await app.prefs.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<String> addProduct({String name = 'ثلاجة', double retail = 13000, double stock = 5}) async {
    final id = await app.appliances.saveProduct({
      'name': name,
      'barcode': await app.appliances.nextProductCode(),
      'cost_price': 10000,
      'retail_price': retail,
    });
    if (stock > 0) {
      await app.crops.saveStockMove({
        'kind': 'adjust',
        'date': todayStr(),
        'item_type': 'product',
        'item_id': id,
        'warehouse_id': (await app.crops.warehouses()).first['id'],
        'qty': stock,
      });
    }
    return id;
  }

  test('a basket being rung up comes back after the app is closed', () async {
    final fridge = await addProduct();
    final fan = await addProduct(name: 'مروحة', retail: 1450);
    final customer = await app.accounts.saveParty({'name': 'أم أحمد', 'kind': 'customer'});

    final cart = PosCart.instance;
    cart.add((await app.appliances.product(fridge))!, 2);
    cart.add((await app.appliances.product(fan))!);
    cart.setPrice(cart.lines.first, 12500);
    cart.setDiscount(500);
    cart.setCustomer(await app.accounts.party(customer));
    expect(cart.total, 12500 * 2 + 1450 - 500);

    // The app is closed and opened again: same phone, same prefs file.
    final kept = app.prefs.get('pos_cart');
    expect(kept, isNotEmpty);
    cart.lines.clear();
    cart.customer = null;
    cart.discount = 0;
    await app.prefs.set('pos_cart', kept);

    await cart.restore();
    expect(cart.lines.length, 2);
    expect(cart.lines.first.qty, 2);
    // The price typed for this sale is kept, not the price list one.
    expect(cart.lines.first.price, 12500);
    expect(cart.discount, 500);
    expect(s(cart.customer!['name']), 'أم أحمد');
    expect(cart.total, 12500 * 2 + 1450 - 500);
  });

  test('a finished sale leaves nothing behind', () async {
    final id = await addProduct();
    final cart = PosCart.instance;
    cart.add((await app.appliances.product(id))!);
    expect(app.prefs.get('pos_cart'), isNotEmpty);

    cart.clear();
    await cart.restore();
    expect(cart.isEmpty, isTrue);
    expect(cart.customer, isNull);
    expect(cart.discount, 0);
  });

  test('a product deleted meanwhile drops out instead of breaking the cashier', () async {
    final id = await addProduct(stock: 0);
    final cart = PosCart.instance;
    cart.add((await app.appliances.product(id))!);
    final kept = app.prefs.get('pos_cart');

    await app.appliances.deleteProduct(id);
    cart.lines.clear();
    await app.prefs.set('pos_cart', kept);
    await cart.restore();
    expect(cart.isEmpty, isTrue);
  });
}
