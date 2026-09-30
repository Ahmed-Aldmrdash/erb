import 'package:flutter_test/flutter_test.dart';
import 'package:trade_erp/core/db/schema.dart';
import 'package:trade_erp/core/util/format.dart';
import 'package:trade_erp/data/appliances_repo.dart';
import 'package:trade_erp/data/backup.dart';
import 'package:trade_erp/data/barcode.dart';
import 'package:trade_erp/data/calc.dart';

import 'ledger_test.dart' show Phone, showroom, appliancesBox;
import 'test_utils.dart';

void main() {
  late Phone shop;

  setUp(() async => shop = await Phone.open(Division.appliances));
  tearDown(() => shop.db.close());

  Future<String> addProduct({
    String name = 'ثلاجة 16 قدم',
    double cost = 10000,
    double retail = 13000,
    double wholesale = 12000,
    double stock = 0,
  }) async {
    final id = await shop.appliances.saveProduct({
      'name': name,
      'barcode': await shop.appliances.nextProductCode(),
      'cost_price': cost,
      'retail_price': retail,
      'wholesale_price': wholesale,
    });
    if (stock > 0) {
      await shop.crops.saveStockMove({
        'kind': 'adjust',
        'date': todayStr(),
        'item_type': 'product',
        'item_id': id,
        'warehouse_id': showroom,
        'qty': stock,
      });
    }
    return id;
  }

  Future<String> sell(String productId, double qty, {double price = 13000}) => shop.appliances.saveInvoice(
        header: {
          'kind': 'sale',
          'date': todayStr(),
          'warehouse_id': showroom,
          'cash_box_id': appliancesBox,
          'payment_type': 'cash',
          'subtotal': qty * price,
          'total': qty * price,
          'grand_total': qty * price,
          'paid_amount': qty * price,
        },
        lines: [InvoiceLineDraft(productId: productId, name: 'صنف', qty: qty, price: price)],
      );

  // ---------------------------------------------------------------- codes

  test('every product gets its own number, all the same length', () async {
    final first = await addProduct(name: 'تلاجة');
    final second = await addProduct(name: 'غسالة');
    final a = s((await shop.appliances.product(first))!['barcode']);
    final b = s((await shop.appliances.product(second))!['barcode']);
    expect(a.length, ProductCode.digits);
    expect(b.length, ProductCode.digits);
    expect(a, isNot(b));

    // A deleted product keeps its number out of circulation: its printed
    // label must never point at another product.
    await shop.appliances.deleteProduct(second);
    final taken = <String>{a, b};
    for (var i = 0; i < 20; i++) {
      expect(taken.contains(await shop.appliances.nextProductCode()), isFalse);
    }

    // A factory barcode scanned from a box lives next to our own numbers.
    await shop.appliances.saveProduct({'name': 'مكواة', 'barcode': '6221000000011'});
    expect((await shop.appliances.productByBarcode('6221000000011'))!['name'], 'مكواة');

    // Products from before this version get numbered in one go.
    await shop.appliances.saveProduct({'name': 'مروحة'});
    expect((await shop.appliances.productCodeState()).missing, 1);
    expect(await shop.appliances.codeAllProducts(), 1);
    final fan = (await shop.appliances.products()).firstWhere((p) => p['name'] == 'مروحة');
    expect(s(fan['barcode']).length, ProductCode.digits);
    expect(await shop.appliances.codeAllProducts(), 0);
  });

  test('short numbers from an older version can be brought to the same length', () async {
    final id = await shop.appliances.saveProduct({'name': 'شاشة', 'barcode': '101'});
    expect((await shop.appliances.productCodeState()).short, 1);
    // Only when asked: renumbering makes the labels already printed useless.
    expect(await shop.appliances.codeAllProducts(), 0);
    expect(s((await shop.appliances.product(id))!['barcode']), '101');

    expect(await shop.appliances.codeAllProducts(unify: true), 1);
    expect(s((await shop.appliances.product(id))!['barcode']).length, ProductCode.digits);
    expect((await shop.appliances.productCodeState()).short, 0);
  });

  test('the label carries the price at the end of the number', () async {
    // Eleven digits like an ordinary shop barcode: six for the product,
    // five for the price, printed as one piece.
    expect(ProductCode.labelBarcode('482137', 4500), '48213704500');
    expect(ProductCode.labelBarcode('482137', 850), '48213700850');
    expect(ProductCode.labelBarcode('482137', 26840), '48213726840');
    expect(ProductCode.printed('482137', 4500).length, 11);
    expect(ProductCode.printed('482137', 4500), contains('04500'));
    // No price yet, or one too big to fit: the number goes out on its own.
    expect(ProductCode.labelBarcode('482137', 0), '482137');
    expect(ProductCode.labelBarcode('482137', 1200000), '482137');

    expect(ProductCode.priceOnLabel('48213704500', '482137'), 4500);
    expect(ProductCode.priceOnLabel('482137', '482137'), isNull);
    expect(ProductCode.priceOnLabel('6221000000011', '6221000000011'), isNull);
    // The barcode the factory printed on the box goes out untouched.
    expect(ProductCode.labelBarcode('6221000000011', 1150), '6221000000011');
    expect(ProductCode.priceOnLabel('622100000001101150', '6221000000011'), isNull);
  });

  test('scanning a whole label finds the product and reads its old price', () async {
    final id = await addProduct(retail: 4500);
    final code = s((await shop.appliances.product(id))!['barcode']);

    // The number on its own (typed by hand, or scanned before a price was set).
    final plain = await shop.appliances.productByScan(code);
    expect(plain!.product['id'], id);
    expect(plain.labelPrice, isNull);

    // The label: number + price.
    final label = await shop.appliances.productByScan('${code}04500');
    expect(label!.product['id'], id);
    expect(label.labelPrice, 4500);

    // The price went up; the old label still finds the product and says what
    // it was printed with, so the showroom knows to print a new one.
    await shop.appliances.setPrices(id, retail: 5200);
    final old = await shop.appliances.productByScan('${code}04500');
    expect(old!.product['id'], id);
    expect(old.labelPrice, 4500);
    expect(n(old.product['retail_price']), 5200);

    // Something that belongs to nobody.
    expect(await shop.appliances.productByScan('999900001'), isNull);
  });

  test('a number typed with Arabic digits is the same number', () async {
    final id = await addProduct();
    final code = s((await shop.appliances.product(id))!['barcode']);
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    final arabic = code.split('').map((d) => eastern[int.parse(d)]).join();
    expect((await shop.appliances.productByBarcode(arabic))!['id'], id);
    expect((await shop.appliances.productByScan(arabic))!.product['id'], id);
  });

  // ---------------------------------------------------------------- prices

  test('a purchase at a new price lifts the selling prices by the same ratio', () async {
    final id = await addProduct(cost: 10000, retail: 13000, wholesale: 12000);
    // Bought 10% dearer: 13,000 -> 14,300 rounded up to the next 10.
    final updates = await shop.appliances.suggestPriceUpdates(
      [InvoiceLineDraft(productId: id, name: 'ثلاجة', qty: 2, price: 11000)],
      step: 10,
    );
    expect(updates.single.cost, 11000);
    expect(updates.single.retail, 14300);
    expect(updates.single.wholesale, 13200);

    // Nothing moves until the invoice is saved with the confirmed prices.
    expect(n((await shop.appliances.product(id))!['retail_price']), 13000);
    await shop.appliances.saveInvoice(
      header: {
        'kind': 'purchase',
        'date': todayStr(),
        'warehouse_id': showroom,
        'cash_box_id': appliancesBox,
        'payment_type': 'cash',
        'subtotal': 22000,
        'total': 22000,
        'grand_total': 22000,
        'paid_amount': 22000,
      },
      lines: [InvoiceLineDraft(productId: id, name: 'ثلاجة', qty: 2, price: 11000)],
      priceUpdates: updates,
    );
    final p = (await shop.appliances.product(id))!;
    expect(n(p['cost_price']), 11000);
    expect(n(p['retail_price']), 14300);
    expect(n(p['wholesale_price']), 13200);
  });

  test('a price that no longer covers the cost is rebuilt from the margin', () async {
    final id = await addProduct(cost: 1000, retail: 1200, wholesale: 0);
    final updates = await shop.appliances.suggestPriceUpdates(
      [InvoiceLineDraft(productId: id, name: 'مروحة', qty: 1, price: 1500)],
      step: 10,
      marginPct: 20,
    );
    // 1,200 would be a loss, so the margin decides: 1,500 + 20% = 1,800.
    expect(updates.single.retail, 1800);
    // A product with no wholesale price does not suddenly get one.
    expect(updates.single.wholesale, 0);
  });

  test('goods with no purchase price on record take the price we type', () async {
    // On the shelf since before anybody wrote down what it cost: a selling
    // price, no purchase price, so there is no old margin to follow.
    final id = await shop.appliances.saveProduct({'name': 'ترموس عادي', 'retail_price': 120});

    // Nothing typed: the cost is learned, the selling price is left alone.
    var updates = await shop.appliances.suggestPriceUpdates(
      [InvoiceLineDraft(productId: id, name: 'ترموس', qty: 10, price: 90)],
      step: 10,
    );
    expect(updates.single.cost, 90);
    expect(updates.single.retail, 120);

    // A selling price typed on the invoice is the one that counts.
    updates = await shop.appliances.suggestPriceUpdates(
      [InvoiceLineDraft(productId: id, name: 'ترموس', qty: 10, price: 90, sellPrice: 135)],
      step: 10,
    );
    expect(updates.single.retail, 135);
    expect(updates.single.cost, 90);

    await shop.appliances.saveInvoice(
      header: {
        'kind': 'purchase',
        'date': todayStr(),
        'warehouse_id': showroom,
        'cash_box_id': appliancesBox,
        'payment_type': 'cash',
        'subtotal': 900,
        'total': 900,
        'grand_total': 900,
        'paid_amount': 900,
      },
      lines: [InvoiceLineDraft(productId: id, name: 'ترموس', qty: 10, price: 90, sellPrice: 135)],
      priceUpdates: updates,
    );
    final p = (await shop.appliances.product(id))!;
    expect(n(p['cost_price']), 90);
    expect(n(p['retail_price']), 135);
  });

  test('a typed selling price wins over the margin it would have worked out', () async {
    final id = await addProduct(cost: 10000, retail: 13000);
    final updates = await shop.appliances.suggestPriceUpdates(
      [InvoiceLineDraft(productId: id, name: 'ثلاجة', qty: 1, price: 11000, sellPrice: 15000)],
      step: 10,
    );
    // 14,300 is what the ratio gives; the showroom said 15,000.
    expect(updates.single.retail, 15000);
  });

  test('a purchase at the same price suggests nothing', () async {
    final id = await addProduct(cost: 10000, retail: 13000);
    final updates = await shop.appliances.suggestPriceUpdates(
      [InvoiceLineDraft(productId: id, name: 'ثلاجة', qty: 1, price: 10000)],
    );
    expect(updates, isEmpty);
  });

  test('the quick price sheet changes prices only', () async {
    final id = await addProduct(stock: 3);
    await shop.appliances.setPrices(id, retail: 15500);
    final p = (await shop.appliances.product(id))!;
    expect(n(p['retail_price']), 15500);
    expect(n(p['cost_price']), 10000);
    expect(n(p['stock']), 3);
  });

  // ---------------------------------------------------------------- stock

  test('a product that is finished cannot be sold', () async {
    final id = await addProduct(stock: 2);
    await sell(id, 2);
    expect(n((await shop.appliances.product(id))!['stock']), 0);

    await expectLater(sell(id, 1), throwsA(isA<OutOfStock>()));
    // Nothing of the refused sale was written.
    expect((await shop.appliances.invoices()).length, 1);
    expect(n((await shop.appliances.product(id))!['stock']), 0);
  });

  test('selling more than the shelf has is refused, selling what it has works', () async {
    final id = await addProduct(stock: 3);
    await expectLater(sell(id, 4), throwsA(isA<OutOfStock>()));
    await sell(id, 3);
    expect(n((await shop.appliances.product(id))!['stock']), 0);
  });

  test('editing a sale down does not count its own pieces as missing', () async {
    final id = await addProduct(stock: 5);
    final invoiceId = await sell(id, 5);
    // The same invoice re-saved with fewer pieces: its own 5 are free again.
    await shop.appliances.saveInvoice(
      header: {
        'kind': 'sale',
        'date': todayStr(),
        'warehouse_id': showroom,
        'cash_box_id': appliancesBox,
        'payment_type': 'cash',
        'subtotal': 26000,
        'total': 26000,
        'grand_total': 26000,
        'paid_amount': 26000,
      },
      lines: [InvoiceLineDraft(productId: id, name: 'صنف', qty: 2, price: 13000)],
      id: invoiceId,
    );
    expect(n((await shop.appliances.product(id))!['stock']), 3);
  });

  // ---------------------------------------------------------------- backup

  test('a backup carries everything back, and stays queued for the server', () async {
    final id = await addProduct(name: 'شاشة 43 بوصة', stock: 4);
    await shop.accounts.saveParty({'name': 'أم أحمد', 'kind': 'customer', 'phone': '01066666666'});
    await shop.accounts.saveSettings({'company_name': 'مؤسسة الدمرداش', 'price_round': '10'});
    final file = await Backup.create(shop.db, company: 'مؤسسة الدمرداش');

    final info = Backup.read(file);
    expect(info.division, Division.appliances);
    expect(info.tables['products']!.length, 1);
    expect(info.highlights['الأصناف'], 1);

    // A second, empty phone gets everything from the file.
    final fresh = Phone(await openTestDb(division: Division.appliances));
    addTearDown(fresh.db.close);
    expect(await Backup.restore(fresh.db, info), info.rows);
    final p = (await fresh.appliances.product(id))!;
    expect(s(p['name']), 'شاشة 43 بوصة');
    expect(n(p['stock']), 4);
    expect((await fresh.accounts.parties()).single['name'], 'أم أحمد');
    expect((await fresh.accounts.settings())['company_name'], 'مؤسسة الدمرداش');
    // Everything that came back waits to be uploaded, stamped now so the
    // restored values also win on the other phones.
    expect(await fresh.db.pendingCount(), info.rows);
    final restored = (await fresh.db.q("SELECT updated_at FROM products WHERE id = ?", [id])).single;
    expect(s(restored['updated_at']).compareTo(info.createdAt), greaterThan(0));
  });

  test('a file that is not a backup says so instead of breaking', () async {
    expect(() => Backup.read('{"hello": 1}'), throwsA(isA<FormatException>()));
    expect(() => Backup.read('not json at all'), throwsA(isA<Exception>()));
  });

  // ---------------------------------------------------------------- rounding

  test('prices are rounded up to the step the showroom picked', () {
    expect(ceilToStep(1243.7, 10), 1250);
    expect(ceilToStep(1250, 10), 1250);
    expect(ceilToStep(1243.7, 25), 1250);
    expect(ceilToStep(1251, 50), 1300);
    expect(ceilToStep(0, 10), 0);
    expect(
      priceFollowingCost(oldCost: 1000, newCost: 1100, oldPrice: 1300, step: 20),
      1440,
    );
    // No cost before: the price is left alone.
    expect(priceFollowingCost(oldCost: 0, newCost: 1100, oldPrice: 1300, step: 10), 1300);
    // No price before, no margin to work with: nothing is invented.
    expect(priceFollowingCost(oldCost: 1000, newCost: 1100, oldPrice: 0, step: 10), 0);
  });
}
