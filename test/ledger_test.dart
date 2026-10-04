import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trade_erp/core/db/app_db.dart';
import 'package:trade_erp/core/db/schema.dart';
import 'package:trade_erp/core/db/v1_import.dart';
import 'package:trade_erp/core/seed.dart';
import 'package:trade_erp/core/util/format.dart';
import 'package:trade_erp/data/accounts_repo.dart';
import 'package:trade_erp/data/activity_repo.dart';
import 'package:trade_erp/data/appliances_repo.dart';
import 'package:trade_erp/data/calc.dart';
import 'package:trade_erp/data/crops_repo.dart';
import 'package:trade_erp/data/notes_repo.dart';
import 'package:trade_erp/data/reports_repo.dart';

import 'test_utils.dart';

// Seeded rows (lib/core/seed.dart).
const wheat = '5eed0000-0000-4000-8000-000000000001';
const shona = '5eed0000-0000-4000-8000-000000000101';
const showroom = '5eed0000-0000-4000-8000-000000000102';
const cropsBox = '5eed0000-0000-4000-8000-000000000201';
const appliancesBox = '5eed0000-0000-4000-8000-000000000202';

/// One division's database with its repositories, like one phone.
class Phone {
  Phone(this.db)
      : accounts = AccountsRepo(db),
        crops = CropsRepo(db),
        appliances = AppliancesRepo(db),
        notes = NotesRepo(db),
        activity = ActivityRepo(db) {
    reports = ReportsRepo(db, crops, appliances);
  }

  final AppDb db;
  final AccountsRepo accounts;
  final CropsRepo crops;
  final AppliancesRepo appliances;
  final NotesRepo notes;
  final ActivityRepo activity;
  late final ReportsRepo reports;

  static Future<Phone> open(String division, {String person = 'أحمد'}) async {
    final db = await openTestDb(division: division);
    db.person = person;
    await seedDefaults(db);
    return Phone(db);
  }
}

Map<String, Object?> tradeValues(String kind, String partyId, CropCalc c, {String date = '2026-03-10'}) => {
      'kind': kind,
      'date': date,
      'party_id': partyId,
      'crop_id': wheat,
      'warehouse_id': shona,
      'cash_box_id': cropsBox,
      'unit_name': 'أردب',
      'kg_per_unit': c.kgPerUnit,
      'weigh_mode': 'scale',
      'gross_kg': c.grossKg,
      'tare_kg': c.tareKg,
      'bags_count': c.bagsCount,
      'bag_weight_kg': c.bagWeightKg,
      'moisture_kg': c.moistureKg,
      'impurities_kg': c.impuritiesKg,
      'moisture_pct': c.moisturePct,
      'impurities_pct': c.impuritiesPct,
      'net_kg': c.netKg,
      'stock_kg': c.stockKg,
      'price_per_unit': c.pricePerUnit,
      'subtotal': c.subtotal,
      'freight': c.freight,
      'loading': c.loading,
      'other_expenses': c.otherExpenses,
      'expenses_on_party': c.expensesOnParty,
      'party_total': c.partyTotal,
      'paid_amount': c.paid,
    };

void main() {
  late Phone trade;

  setUp(() async => trade = await Phone.open(Division.crops));
  tearDown(() => trade.db.close());

  test('each division seeds only its own starter data', () async {
    final showroomPhone = await Phone.open(Division.appliances);
    addTearDown(showroomPhone.db.close);
    expect((await trade.crops.crops()).length, 6);
    expect((await trade.crops.warehouses()).map((w) => w['id']), [shona]);
    expect((await trade.accounts.cashBoxes()).map((b) => b['id']), [cropsBox]);
    expect(await showroomPhone.crops.crops(), isEmpty);
    expect((await showroomPhone.crops.warehouses()).map((w) => w['id']), [showroom]);
    expect((await showroomPhone.accounts.cashBoxes()).map((b) => b['id']), [appliancesBox]);
    // Every row is stamped with the division of its database.
    final party = await showroomPhone.accounts.saveParty({'name': 'عميل'});
    expect((await showroomPhone.db.byId('parties', party))!['division'], Division.appliances);
    // Settings are per division.
    expect((await trade.accounts.settings())['company_name'], defaultCompanyName);
    await showroomPhone.accounts.saveSettings({'company_name': 'معرض الدمرداش'});
    expect((await showroomPhone.accounts.settings())['company_name'], 'معرض الدمرداش');
    expect((await showroomPhone.db.byId('app_settings', 'appliances:company_name'))!['value'], 'معرض الدمرداش');
  });

  test('crops: purchase, advance, sale, stock, cash and profit', () async {
    final accounts = trade.accounts, crops = trade.crops;
    await accounts.saveCashBox({'opening_balance': 50000}, id: cropsBox);
    final farmer = await accounts.saveParty({'name': 'الحاج محمود', 'kind': 'farmer'});
    final trader = await accounts.saveParty({'name': 'مطحن النصر', 'kind': 'trader', 'opening_balance': 1000});

    // Advance before harvest: the farmer owes us 5,000.
    await accounts.saveVoucher({'kind': 'advance', 'date': '2026-02-01', 'party_id': farmer, 'cash_box_id': cropsBox, 'amount': 5000});
    expect(await accounts.partyBalance(farmer), 5000);

    // 50 ardeb at 2,000, we pay 20,000 now and 500 freight.
    const buy = CropCalc(isSale: false, grossKg: 7550, bagsCount: 100, bagWeightKg: 0.5, kgPerUnit: 150, pricePerUnit: 2000, freight: 500, paid: 20000);
    expect(buy.netKg, 7500);
    final buyId = await crops.saveTrade(tradeValues('purchase', farmer, buy));
    // 100,000 due to the farmer - 5,000 advance - 20,000 paid = we owe 75,000.
    expect(await accounts.partyBalance(farmer), -75000);
    expect(await crops.stockAt(wheat, shona), 7500);
    expect(await crops.costPerKg(wheat), closeTo(100500 / 7500, 1e-9));

    // Sell 30 ardeb (+ 10 kg bags) at 2,500; the trader pays 50,000.
    const sell = CropCalc(isSale: true, grossKg: 4510, bagsCount: 20, bagWeightKg: 0.5, kgPerUnit: 150, pricePerUnit: 2500, paid: 50000);
    expect(sell.netKg, 4500);
    await crops.saveTrade(tradeValues('sale', trader, sell));
    expect(await crops.stockAt(wheat, shona), 3000);
    // Opening 1,000 + 75,000 sale - 50,000 received.
    expect(await accounts.partyBalance(trader), 26000);

    // Cash: 50,000 - 5,000 advance - 20,000 - 500 freight + 50,000.
    final box = await accounts.cashBox(cropsBox);
    expect(n(box!['balance']), 74500);

    final profit = await trade.reports.cropsProfit('2026-01-01', '2026-12-31');
    expect(profit.revenue, 75000);
    expect(profit.cogs, closeTo(4500 * 100500 / 7500, 0.01));
    expect(profit.net, closeTo(75000 - 60300, 0.01));

    // Statement has a running balance ending at the current balance.
    final ledger = await accounts.partyLedger(farmer);
    expect(ledger.length, 2);
    expect(n(ledger.last['balance']), -75000);

    // Deleting the purchase removes its effect everywhere.
    await crops.deleteTrade(buyId);
    expect(await accounts.partyBalance(farmer), 5000);
    expect(await crops.stockAt(wheat, shona), -4500);
  });

  test('today\'s crop prices are kept per crop', () async {
    await trade.crops.saveCropPrices(wheat, 1900, 2100);
    final w = (await trade.crops.crops()).firstWhere((c) => c['id'] == wheat);
    expect(n(w['buy_price']), 1900);
    expect(n(w['sell_price']), 2100);
  });

  test('appliances: purchase with discount, installment sale, collections, return', () async {
    final shop = await Phone.open(Division.appliances);
    addTearDown(shop.db.close);
    final accounts = shop.accounts, appliances = shop.appliances;
    final supplier = await accounts.saveParty({'name': 'توكيل الأجهزة', 'kind': 'supplier'});
    final customer = await accounts.saveParty({'name': 'أم أحمد', 'kind': 'customer', 'phone': '01012345678'});
    final fridge = await appliances.saveProduct({
      'name': 'ثلاجة 16 قدم',
      'retail_price': 15000,
      'cost_price': 12000,
      'barcode': '6221234567890',
    });
    expect((await appliances.productByBarcode('6221234567890'))!['id'], fridge);
    expect(await appliances.productByBarcode('000'), isNull);

    // 10 fridges at 10,000 with 1,000 discount, paid 40,000, rest on account.
    await appliances.saveInvoice(
      header: {
        'kind': 'purchase',
        'date': '2026-03-01',
        'party_id': supplier,
        'warehouse_id': showroom,
        'cash_box_id': appliancesBox,
        'payment_type': 'credit',
        'subtotal': 100000,
        'discount': 1000,
        'total': 99000,
        'grand_total': 99000,
        'paid_amount': 40000,
      },
      lines: [InvoiceLineDraft(productId: fridge, name: 'ثلاجة', qty: 10, price: 10000)],
    );
    expect(await accounts.partyBalance(supplier), -59000);
    final purchase = (await appliances.invoices(kinds: ['purchase'])).single;
    expect(AppliancesRepo.remainingOf(purchase), 59000);
    // A general payment on the account (not linked to the invoice) still
    // reduces what is shown as open on the invoice.
    await accounts.saveVoucher({'kind': 'payment', 'date': '2026-03-02', 'party_id': supplier, 'cash_box_id': appliancesBox, 'amount': 20000});
    expect(AppliancesRepo.remainingOf((await appliances.invoice(s(purchase['id'])))!), 39000);
    final p = await appliances.product(fridge);
    expect(n(p!['stock']), 10);
    expect(n(p['unit_cost']), 9900);

    // Installment sale: 2 fridges, 4,000 down, 10% markup over 10 months.
    final plan = InstallmentPlan(total: 30000, downPayment: 4000, markupPct: 10, months: 10, firstDue: DateTime(2026, 4, 1));
    final saleId = await appliances.saveInvoice(
      header: {
        'kind': 'sale',
        'date': '2026-03-05',
        'party_id': customer,
        'warehouse_id': showroom,
        'cash_box_id': appliancesBox,
        'payment_type': 'installment',
        'subtotal': 30000,
        'total': 30000,
        'markup_pct': 10,
        'markup_amount': plan.markup,
        'grand_total': plan.grandTotal,
        'paid_amount': 4000,
        'inst_months': 10,
      },
      lines: [InvoiceLineDraft(productId: fridge, name: 'ثلاجة', qty: 2, price: 15000)],
      schedule: plan.schedule,
    );
    expect(plan.grandTotal, 32600);
    expect(await accounts.partyBalance(customer), 28600);
    expect(n((await appliances.product(fridge))!['stock']), 8);

    // Collect 3,500: first installment (2,860) fully, the second partly.
    await accounts.saveVoucher({
      'kind': 'receipt',
      'date': '2026-04-02',
      'party_id': customer,
      'cash_box_id': appliancesBox,
      'amount': 3500,
      'invoice_id': saleId,
    });
    final inst = await appliances.invoiceInstallments(saleId);
    expect(inst.length, 10);
    expect(inst[0].paid, 2860);
    expect(inst[1].paid, 640);
    expect(await accounts.partyBalance(customer), 25100);
    final open = await appliances.openInstallments(until: '2026-05-31');
    expect(open.length, 1);
    expect(open.first.status.remaining, 2220);

    // Editing the invoice replaces its lines and schedule (new revision).
    await appliances.saveInvoice(
      id: saleId,
      header: {
        'kind': 'sale',
        'date': '2026-03-05',
        'party_id': customer,
        'warehouse_id': showroom,
        'cash_box_id': appliancesBox,
        'payment_type': 'installment',
        'subtotal': 15000,
        'total': 15000,
        'grand_total': 15000,
        'paid_amount': 3000,
        'inst_months': 2,
      },
      lines: [InvoiceLineDraft(productId: fridge, name: 'ثلاجة', qty: 1, price: 15000)],
      schedule: InstallmentPlan(total: 15000, downPayment: 3000, markupPct: 0, months: 2, firstDue: DateTime(2026, 4, 1)).schedule,
    );
    expect(n((await appliances.product(fridge))!['stock']), 9);
    expect((await appliances.invoiceLines(saleId)).length, 1);
    final after = await appliances.invoiceInstallments(saleId);
    expect(after.map((x) => x.paid).toList(), [3500, 0]);

    // Return one fridge into stock, credited to the customer.
    await appliances.saveInvoice(
      header: {
        'kind': 'sale_return',
        'date': '2026-04-10',
        'party_id': customer,
        'warehouse_id': showroom,
        'payment_type': 'credit',
        'subtotal': 15000,
        'total': 15000,
        'grand_total': 15000,
      },
      lines: [InvoiceLineDraft(productId: fridge, name: 'ثلاجة', qty: 1, price: 15000)],
    );
    expect(n((await appliances.product(fridge))!['stock']), 10);
    // 15,000 - 3,000 down - 3,500 collected - 15,000 returned.
    expect(await accounts.partyBalance(customer), -6500);

    final summary = await appliances.salesSummary('2026-03-01', '2026-04-30');
    expect(n(summary['sales']), 15000);
    expect(n(summary['returns']), 15000);
    expect(n(summary['cogs']), 0);
  });

  test('cashier sale takes the goods out of stock and the money into the box', () async {
    final shop = await Phone.open(Division.appliances, person: 'محمد');
    addTearDown(shop.db.close);
    final kettle = await shop.appliances.saveProduct({'name': 'كاتل', 'retail_price': 800, 'cost_price': 600});
    await shop.crops.saveStockMove({
      'kind': 'adjust',
      'date': '2026-05-01',
      'item_type': 'product',
      'item_id': kettle,
      'warehouse_id': showroom,
      'qty': 5,
    });
    final id = await shop.appliances.saveInvoice(
      header: {
        'kind': 'sale',
        'date': '2026-05-02',
        'customer_name': 'زبون',
        'warehouse_id': showroom,
        'cash_box_id': appliancesBox,
        'payment_type': 'cash',
        'subtotal': 1600,
        'discount': 100,
        'total': 1500,
        'grand_total': 1500,
        'paid_amount': 1500,
        'source': 'pos',
      },
      lines: [InvoiceLineDraft(productId: kettle, name: 'كاتل', qty: 2, price: 800)],
    );
    expect(n((await shop.appliances.product(kettle))!['stock']), 3);
    expect(n((await shop.accounts.cashBox(appliancesBox))!['balance']), 1500);
    final inv = (await shop.appliances.invoice(id))!;
    expect(inv['source'], 'pos');
    expect(inv['created_by_name'], 'محمد');
    final day = await shop.accounts.cashDay('2026-05-02');
    expect(n(day.boxes.single['amount_in']), 1500);
    expect(n(day.boxes.single['closing']), 1500);
  });

  test('stocktake turns every difference into an adjustment', () async {
    final shop = await Phone.open(Division.appliances);
    addTearDown(shop.db.close);
    final a = await shop.appliances.saveProduct({'name': 'مروحة'});
    final b = await shop.appliances.saveProduct({'name': 'مكواة'});
    await shop.crops.saveStockMove({'kind': 'adjust', 'date': '2026-05-01', 'item_type': 'product', 'item_id': a, 'warehouse_id': showroom, 'qty': 10});
    await shop.crops.saveStockMove({'kind': 'adjust', 'date': '2026-05-01', 'item_type': 'product', 'item_id': b, 'warehouse_id': showroom, 'qty': 4});
    final atShowroom = await shop.appliances.productsAtWarehouse(showroom);
    expect({for (final r in atShowroom) r['id']: n(r['stock'])}, {a: 10, b: 4});
    final adjusted = await shop.crops.saveStocktake(
      itemType: 'product',
      warehouseId: showroom,
      date: '2026-05-03',
      lines: [(itemId: a, system: 10, counted: 8), (itemId: b, system: 4, counted: 4)],
    );
    expect(adjusted, 1);
    expect(n((await shop.appliances.product(a))!['stock']), 8);
    expect(n((await shop.appliances.product(b))!['stock']), 4);
  });

  test('account page for a period starts with the carried balance', () async {
    final accounts = trade.accounts;
    final farmer = await accounts.saveParty({'name': 'فلاح', 'kind': 'farmer'});
    await accounts.saveVoucher({'kind': 'advance', 'date': '2026-01-10', 'party_id': farmer, 'cash_box_id': cropsBox, 'amount': 1000});
    await accounts.saveVoucher({
      'kind': 'receipt',
      'date': '2026-02-10',
      'party_id': farmer,
      'cash_box_id': cropsBox,
      'amount': 400,
      'handled_by': 'محمود',
      'notes': 'اداها لأخوه الصغير',
    });
    await accounts.saveVoucher({'kind': 'advance', 'date': '2026-03-10', 'party_id': farmer, 'cash_box_id': cropsBox, 'amount': 200});
    final rows = await accounts.partyLedger(farmer, from: '2026-02-01', to: '2026-02-28');
    expect(rows.length, 2);
    expect(rows.first['doc_type'], 'carried');
    expect(n(rows.first['debit']), 1000);
    expect(rows.last['handled_by'], 'محمود');
    expect(rows.last['notes'], 'اداها لأخوه الصغير');
    expect(rows.last['by_name'], 'أحمد');
    expect(n(rows.last['balance']), 600);
    expect(await accounts.partyBalance(farmer), 800);
  });

  test('promised collection dates show up when due', () async {
    final accounts = trade.accounts;
    final trader = await accounts.saveParty({'name': 'تاجر', 'kind': 'trader', 'opening_balance': 3000});
    final paidUp = await accounts.saveParty({'name': 'خالص', 'kind': 'trader'});
    await accounts.setCollectDate(trader, '2026-06-01');
    await accounts.setCollectDate(paidUp, '2026-06-01');
    expect(await accounts.dueCollections('2026-05-31'), isEmpty);
    final due = await accounts.dueCollections('2026-06-01');
    expect(due.map((r) => r['id']), [trader]);
    expect(n(due.single['balance']), 3000);
  });

  test('notes: reminders with who wrote and who finished them', () async {
    final notes = trade.notes;
    final id = await notes.save({
      'kind': 'money',
      'body': 'الحاج علي ساب 5000 لمحمود',
      'amount': 5000,
      'person': 'محمود',
      'due_date': '2026-06-01',
    });
    await notes.save({'body': 'للقسمين', 'division': Division.all});
    expect(await notes.openCount(), 2);
    final n1 = (await notes.note(id))!;
    expect(n1['created_by_name'], 'أحمد');
    expect(n1['division'], Division.crops);
    expect((await notes.list(done: false, search: 'محمود')).length, 1);

    trade.db.person = 'محمود';
    await notes.setDone(id, true);
    final done = (await notes.note(id))!;
    expect(n(done['done']), 1);
    expect(done['done_by'], 'محمود');
    expect(done['updated_by_name'], 'محمود');
    expect(await notes.openCount(), 1);
    expect((await notes.list(done: true)).single['id'], id);
  });

  test('activity log tells who added, edited and deleted', () async {
    final accounts = trade.accounts;
    final v = await accounts.saveVoucher({'kind': 'expense', 'date': '2026-05-01', 'cash_box_id': cropsBox, 'amount': 50, 'category': 'نثريات'});
    trade.db.person = 'محمود';
    // A later change needs a later timestamp than the insert.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await accounts.saveVoucher({'amount': 60}, id: v);
    final log = await trade.activity.recent();
    final row = log.firstWhere((r) => r['doc_id'] == v);
    expect(row['action'], 'edited');
    expect(row['who'], 'محمود');
    expect(row['created_by_name'], 'أحمد');
    expect((await trade.activity.recent(person: 'محمود')).map((r) => r['doc_id']), contains(v));
    expect(await trade.activity.people(), containsAll(['أحمد', 'محمود']));

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await accounts.deleteVoucher(v);
    final deleted = (await trade.activity.recent()).firstWhere((r) => r['doc_id'] == v);
    expect(deleted['action'], 'deleted');
  });

  test('daily cash book: opening, in, out and closing of the day', () async {
    final accounts = trade.accounts;
    final second = await accounts.saveCashBox({'name': 'خزنة الشونة'});
    await accounts.saveVoucher({'kind': 'deposit', 'date': '2026-05-01', 'cash_box_id': cropsBox, 'amount': 1000});
    await accounts.saveVoucher({'kind': 'expense', 'date': '2026-05-02', 'cash_box_id': cropsBox, 'amount': 150, 'category': 'عتالة'});
    await accounts.saveVoucher({'kind': 'transfer', 'date': '2026-05-02', 'cash_box_id': cropsBox, 'to_cash_box_id': second, 'amount': 300});
    final day = await accounts.cashDay('2026-05-02');
    final main = day.boxes.firstWhere((b) => b['id'] == cropsBox);
    expect(n(main['opening']), 1000);
    expect(n(main['amount_out']), 450);
    expect(n(main['closing']), 550);
    final other = day.boxes.firstWhere((b) => b['id'] == second);
    expect(n(other['amount_in']), 300);
    expect(day.rows.length, 3);
    expect(await trade.reports.expensesTotal('2026-05-01', '2026-05-31'), 150);
  });

  test('document numbers per phone and kind', () async {
    final accounts = trade.accounts, db = trade.db;
    db.deviceCode = '3';
    final a = await accounts.saveVoucher({'kind': 'receipt', 'date': todayStr(), 'cash_box_id': cropsBox, 'amount': 1});
    final b = await accounts.saveVoucher({'kind': 'receipt', 'date': todayStr(), 'cash_box_id': cropsBox, 'amount': 1});
    final c = await accounts.saveVoucher({'kind': 'expense', 'date': todayStr(), 'cash_box_id': cropsBox, 'amount': 1});
    expect((await accounts.voucher(a))!['number'], '3-1');
    expect((await accounts.voucher(b))!['number'], '3-2');
    expect((await accounts.voucher(c))!['number'], '3-1');

    // After a reinstall the counter continues from the synced documents.
    await db.raw.rawDelete("DELETE FROM meta WHERE key LIKE 'num:%'");
    final d = await accounts.saveVoucher({'kind': 'receipt', 'date': todayStr(), 'cash_box_id': cropsBox, 'amount': 1});
    expect((await accounts.voucher(d))!['number'], '3-3');
  });

  test('plain numbers before the phone is registered, prefixed afterwards', () async {
    final accounts = trade.accounts, db = trade.db;
    final a = await accounts.saveVoucher({'kind': 'receipt', 'date': todayStr(), 'cash_box_id': cropsBox, 'amount': 1});
    final b = await accounts.saveVoucher({'kind': 'receipt', 'date': todayStr(), 'cash_box_id': cropsBox, 'amount': 1});
    expect((await accounts.voucher(a))!['number'], '1');
    expect((await accounts.voucher(b))!['number'], '2');

    await db.prefixLocalNumbers('4');
    db.deviceCode = '4';
    expect((await accounts.voucher(a))!['number'], '4-1');
    final c = await accounts.saveVoucher({'kind': 'receipt', 'date': todayStr(), 'cash_box_id': cropsBox, 'amount': 1});
    expect((await accounts.voucher(c))!['number'], '4-3');
  });

  test('parties with documents cannot be deleted', () async {
    final accounts = trade.accounts;
    final p = await accounts.saveParty({'name': 'عميل'});
    await accounts.saveVoucher({'kind': 'receipt', 'date': todayStr(), 'party_id': p, 'cash_box_id': cropsBox, 'amount': 10});
    expect(await accounts.deleteParty(p), isNotNull);
    final q = await accounts.saveParty({'name': 'عميل جديد'});
    expect(await accounts.deleteParty(q), isNull);
    expect((await accounts.parties()).map((r) => r['id']), isNot(contains(q)));
  });

  test('arabic search ignores alef and ta marbuta variants', () async {
    final accounts = trade.accounts;
    await accounts.saveParty({'name': 'أحمد عبد الله', 'phone': '01000000001'});
    await accounts.saveParty({'name': 'مؤسسة النور'});
    expect((await accounts.parties(search: 'احمد')).length, 1);
    expect((await accounts.parties(search: 'مؤسسه')).length, 1);
    expect((await accounts.parties(search: '٠١٠٠٠٠٠٠٠٠١')).length, 1);
  });

  test('adding to / taking from an account moves no cash', () async {
    final accounts = trade.accounts;
    final trader = await accounts.saveParty({'name': 'تاجر', 'kind': 'trader', 'opening_balance': 1000});
    await accounts.saveVoucher({'kind': 'debit_adj', 'date': '2026-05-01', 'party_id': trader, 'amount': 300, 'notes': 'حساب قديم'});
    await accounts.saveVoucher({'kind': 'credit_adj', 'date': '2026-05-02', 'party_id': trader, 'amount': 100, 'notes': 'خصم'});
    expect(await accounts.partyBalance(trader), 1200);
    final totals = await accounts.partyTotals(trader);
    expect(totals.gave, 1300);
    expect(totals.took, 100);
    expect(n((await accounts.cashBox(cropsBox))!['balance']), 0);
    final ledger = await accounts.partyLedger(trader);
    expect(ledger.map((r) => r['title']), ['رصيد سابق', 'زيادة على حسابه', 'خصم من حسابه']);
    expect((await accounts.cashDay('2026-05-01')).rows, isEmpty);
  });

  test('the old balance always opens the account page', () async {
    final accounts = trade.accounts;
    // Created today with an old balance, but the payment is dated earlier.
    final farmer = await accounts.saveParty({'name': 'فلاح', 'kind': 'farmer', 'opening_balance': -500});
    await accounts.saveVoucher({'kind': 'payment', 'date': '2026-01-05', 'party_id': farmer, 'cash_box_id': cropsBox, 'amount': 200});
    final ledger = await accounts.partyLedger(farmer);
    expect(ledger.first['doc_type'], 'opening');
    expect(n(ledger.first['balance']), -500);
    expect(n(ledger.last['balance']), -300);
    expect(ledger.last['title'], 'خد فلوس');
  });

  test('records of the first version move into their division', () async {
    final dir = Directory.systemTemp.createTempSync('erp_v1_');
    final path = '${dir.path}${Platform.pathSeparator}trade_erp.db';
    final old = await databaseFactoryFfi.openDatabase(path);
    await old.execute('CREATE TABLE parties (id TEXT PRIMARY KEY, name TEXT, kind TEXT, opening_balance REAL, created_at TEXT, updated_at TEXT, deleted INTEGER, dirty INTEGER)');
    await old.execute('CREATE TABLE cash_boxes (id TEXT PRIMARY KEY, name TEXT, division TEXT, opening_balance REAL, deleted INTEGER, dirty INTEGER)');
    await old.execute('CREATE TABLE crop_trades (id TEXT PRIMARY KEY, kind TEXT, date TEXT, party_id TEXT, crop_id TEXT, net_kg REAL, party_total REAL, paid_amount REAL, deleted INTEGER, dirty INTEGER)');
    await old.execute('CREATE TABLE vouchers (id TEXT PRIMARY KEY, kind TEXT, date TEXT, division TEXT, party_id TEXT, cash_box_id TEXT, amount REAL, notes TEXT, deleted INTEGER, dirty INTEGER)');
    await old.execute('CREATE TABLE profiles (id TEXT PRIMARY KEY, name TEXT)');
    await old.insert('parties', {'id': 'p-farmer', 'name': 'فلاح قديم', 'kind': 'farmer', 'opening_balance': 0, 'deleted': 0, 'dirty': 1});
    await old.insert('parties', {'id': 'p-customer', 'name': 'زبون قديم', 'kind': 'customer', 'opening_balance': 250, 'deleted': 0, 'dirty': 1});
    await old.insert('cash_boxes', {'id': 'box-general', 'name': 'فودافون كاش', 'division': 'general', 'opening_balance': 100, 'deleted': 0, 'dirty': 1});
    await old.insert('crop_trades', {
      'id': 't1',
      'kind': 'purchase',
      'date': '2026-09-01',
      'party_id': 'p-farmer',
      'crop_id': wheat,
      'net_kg': 1500,
      'party_total': 20000,
      'paid_amount': 5000,
      'deleted': 0,
      'dirty': 1,
    });
    await old.insert('vouchers', {'id': 'v-crops', 'kind': 'advance', 'date': '2026-08-01', 'division': 'crops', 'party_id': 'p-farmer', 'cash_box_id': cropsBox, 'amount': 1000, 'deleted': 0, 'dirty': 1});
    await old.insert('vouchers', {'id': 'v-general', 'kind': 'expense', 'date': '2026-08-02', 'division': 'general', 'cash_box_id': 'box-general', 'amount': 40, 'deleted': 0, 'dirty': 1});
    await old.insert('profiles', {'id': 'me', 'name': 'أحمد'});
    await old.close();

    // Two parties, a weighing and two vouchers were typed; the seeds don't count.
    expect(await V1Import.countOldData(v1Path: path, factory: databaseFactoryFfi), 5);

    final shop = await Phone.open(Division.appliances);
    addTearDown(shop.db.close);
    expect(await V1Import.run(trade.db, v1Path: path, factory: databaseFactoryFfi), 3);
    expect(await V1Import.run(shop.db, v1Path: path, factory: databaseFactoryFfi), 3);
    // Only once.
    expect(await V1Import.run(trade.db, v1Path: path, factory: databaseFactoryFfi), 0);

    // The farmer, his purchase and his advance are in the trade.
    expect(n((await trade.accounts.party('p-farmer'))!['balance']), -14000);
    expect((await trade.db.byId('crop_trades', 't1'))!['division'], Division.crops);
    expect(await trade.accounts.party('p-customer'), isNull);
    // The customer, the general box and its expense are in the showroom.
    expect(n((await shop.accounts.party('p-customer'))!['balance']), 250);
    expect((await shop.db.byId('cash_boxes', 'box-general'))!['division'], Division.appliances);
    expect((await shop.db.byId('vouchers', 'v-general'))!['division'], Division.appliances);
    // Everything waits to be sent to the server.
    expect(await shop.db.pendingCount(), greaterThanOrEqualTo(3));

    // Or it was only a trial: the old file goes.
    await V1Import.deleteOldFile(v1Path: path, factory: databaseFactoryFfi);
    expect(await V1Import.countOldData(v1Path: path, factory: databaseFactoryFfi), 0);
  });

  test('season report: per crop, per farmer and trader, deductions', () async {
    final accounts = trade.accounts, crops = trade.crops;
    final farmer = await accounts.saveParty({'name': 'فلاح', 'kind': 'farmer'});
    final trader = await accounts.saveParty({'name': 'مطحن', 'kind': 'trader'});
    const buy = CropCalc(
      isSale: false,
      grossKg: 21330,
      tareKg: 6100,
      bagsCount: 100,
      bagWeightKg: 0.5,
      moistureKg: 150,
      kgPerUnit: 150,
      pricePerUnit: 2000,
      freight: 500,
      paid: 10000,
    );
    await crops.saveTrade(tradeValues('purchase', farmer, buy, date: '2026-05-10'));
    await accounts.saveVoucher({'kind': 'advance', 'date': '2026-04-20', 'party_id': farmer, 'cash_box_id': cropsBox, 'amount': 3000});
    const sell = CropCalc(isSale: true, grossKg: 12110, tareKg: 6100, kgPerUnit: 150, pricePerUnit: 2500, paid: 20000);
    await crops.saveTrade(tradeValues('sale', trader, sell, date: '2026-06-01'));
    // Outside the season.
    await crops.saveTrade(tradeValues('purchase', farmer, buy, date: '2026-09-01'));

    final r = await trade.reports.season('2026-04-01', '2026-07-31');
    expect(r.tripsIn, 1);
    expect(r.tripsOut, 1);
    expect(r.boughtKg, buy.netKg);
    expect(r.soldKg, sell.netKg);
    expect(r.deductedKg, 200);
    expect(r.advancesTotal, 3000);
    expect(r.farmers.single['name'], 'فلاح');
    expect(r.traders.single['name'], 'مطحن');
    expect(r.purchases.single['name'], 'قمح');
    expect(r.grossProfit, greaterThan(0));
    // Only wheat.
    final wheatOnly = await trade.reports.season('2026-04-01', '2026-07-31', cropId: wheat);
    expect(wheatOnly.boughtKg, buy.netKg);
  });
}
