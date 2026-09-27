// Builds demo databases (local mode) for trying the app and taking
// screenshots:
//   flutter test tool/demo_db_test.dart
// Output: build/demo/erp_crops.db, erp_appliances.db and erp_prefs.db
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trade_erp/core/db/app_db.dart';
import 'package:trade_erp/core/db/prefs.dart';
import 'package:trade_erp/core/db/schema.dart';
import 'package:trade_erp/core/seed.dart';
import 'package:trade_erp/core/util/format.dart';
import 'package:trade_erp/data/accounts_repo.dart';
import 'package:trade_erp/data/appliances_repo.dart';
import 'package:trade_erp/data/calc.dart';
import 'package:trade_erp/data/crops_repo.dart';
import 'package:trade_erp/data/notes_repo.dart';

const wheat = '5eed0000-0000-4000-8000-000000000001';
const maize = '5eed0000-0000-4000-8000-000000000002';
const shona = '5eed0000-0000-4000-8000-000000000101';
const showroom = '5eed0000-0000-4000-8000-000000000102';
const cropsBox = '5eed0000-0000-4000-8000-000000000201';
const appliancesBox = '5eed0000-0000-4000-8000-000000000202';

String daysAgo(int d) => dateStr(DateTime.now().subtract(Duration(days: d)));
String daysAhead(int d) => dateStr(DateTime.now().add(Duration(days: d)));

Future<AppDb> _fresh(String division) async {
  final out = File('build/demo/erp_$division.db');
  out.parent.createSync(recursive: true);
  if (out.existsSync()) out.deleteSync();
  final db = await AppDb.open(division: division, path: out.absolute.path, factory: databaseFactoryFfi);
  db.person = 'أحمد';
  await seedDefaults(db);
  return db;
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('prefs', () async {
    final f = File('build/demo/erp_prefs.db');
    f.parent.createSync(recursive: true);
    if (f.existsSync()) f.deleteSync();
    final prefs = await Prefs.open(path: f.absolute.path, factory: databaseFactoryFfi);
    await prefs.set('mode', 'local');
    await prefs.set('division', Division.appliances);
    await prefs.set('person', 'أحمد');
    await prefs.set('recent_persons', jsonEncode(['أحمد', 'محمود', 'محمد', 'مصطفى']));
    await prefs.set('device_id', '9d3c63c4-5f7e-4f7e-9a51-6e1f7b9d0a11');
    await prefs.close();
  });

  test('trade (crops) database', () async {
    final db = await _fresh(Division.crops);
    final accounts = AccountsRepo(db);
    final crops = CropsRepo(db);
    final notes = NotesRepo(db);

    await accounts.saveSettings({
      'company_name': defaultCompanyName,
      'company_phone': '01000000000',
      'company_address': 'المنصورة - الدقهلية',
      'invoice_footer': 'شكراً لتعاملكم معنا',
      'default_bag_weight': '0.5',
    });
    await accounts.saveCashBox({'opening_balance': 250000}, id: cropsBox);
    await crops.saveCropPrices(wheat, 2150, 2350);
    await crops.saveCropPrices(maize, 1680, 1800);

    Future<String> party(String name, String kind, String phone, [double opening = 0]) =>
        accounts.saveParty({'name': name, 'kind': kind, 'phone': phone, 'opening_balance': opening});

    final f1 = await party('الحاج محمود عبد الله', 'farmer', '01011111111');
    final f2 = await party('سيد عبد العزيز', 'farmer', '01022222222', 3000);
    final f3 = await party('عبد الرحمن فتحي', 'farmer', '01033333333');
    final t1 = await party('مطحن الدلتا', 'trader', '01044444444');
    final t2 = await party('شركة المحاصيل المتحدة', 'trader', '01055555555');

    await accounts.saveVoucher({
      'kind': 'advance',
      'date': daysAgo(40),
      'party_id': f1,
      'cash_box_id': cropsBox,
      'amount': 15000,
      'handled_by': 'محمود',
      'notes': 'سلفة قبل الحصاد',
    });
    db.person = 'محمود';
    await accounts.saveVoucher({'kind': 'advance', 'date': daysAgo(35), 'party_id': f3, 'cash_box_id': cropsBox, 'amount': 8000, 'handled_by': 'محمود'});

    Future<void> trade(String kind, String partyId, String crop, int ago, CropCalc c,
            {String ticket = '', String mode = 'scale', List<double> sacks = const []}) =>
        crops.saveTrade({
          'kind': kind,
          'date': daysAgo(ago),
          'party_id': partyId,
          'crop_id': crop,
          'warehouse_id': shona,
          'cash_box_id': cropsBox,
          'unit_name': 'أردب',
          'kg_per_unit': c.kgPerUnit,
          'weigh_mode': mode,
          'gross_kg': c.grossKg,
          'tare_kg': c.tareKg,
          'sack_weights': sacks.isEmpty ? null : sackWeightsJson(sacks),
          'bags_count': c.bagsCount,
          'bag_weight_kg': c.bagWeightKg,
          'moisture_kg': c.moistureKg,
          'impurities_kg': c.impuritiesKg,
          'other_deduction_kg': c.otherDeductionKg,
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
          'ticket_no': ticket,
        });

    // Sack by sack: 60 sacks of about 150 kg.
    final sackList = [for (var i = 0; i < 60; i++) 148.0 + (i * 7 % 11) * 0.5];
    final sackTotal = sackList.fold<double>(0, (a, w) => a + w);

    db.person = 'أحمد';
    await trade('purchase', f1, wheat, 20, const CropCalc(isSale: false, grossKg: 21330, tareKg: 6100, bagsCount: 100, bagWeightKg: 0.5, moistureKg: 150, kgPerUnit: 150, pricePerUnit: 2150, freight: 1200, loading: 500, paid: 50000), ticket: '4512');
    await trade('purchase', f2, wheat, 15, CropCalc(isSale: false, grossKg: sackTotal, bagsCount: 60, bagWeightKg: 0.5, impuritiesKg: 20, kgPerUnit: 150, pricePerUnit: 2100, loading: 300, expensesOnParty: true, paid: 60000), ticket: '4530', mode: 'sacks', sacks: sackList);
    db.person = 'مصطفى';
    await trade('purchase', f3, maize, 12, const CropCalc(isSale: false, grossKg: 16450, tareKg: 5200, moistureKg: 225, impuritiesKg: 56, kgPerUnit: 140, pricePerUnit: 1650, freight: 900, paid: 70000), ticket: '4551');
    await trade('sale', t1, wheat, 6, const CropCalc(isSale: true, grossKg: 18200, tareKg: 6150, bagsCount: 80, bagWeightKg: 0.5, moistureKg: 60, kgPerUnit: 150, pricePerUnit: 2350, freight: 1500, paid: 150000), ticket: '7710');
    db.person = 'أحمد';
    await trade('sale', t2, maize, 3, const CropCalc(isSale: true, grossKg: 13220, tareKg: 6200, bagsCount: 40, bagWeightKg: 0.5, kgPerUnit: 140, pricePerUnit: 1800, freight: 800, expensesOnParty: true, paid: 50000), ticket: '7725');
    await trade('purchase', f1, maize, 0, const CropCalc(isSale: false, grossKg: 5640, bagsCount: 40, bagWeightKg: 0.5, moistureKg: 84, kgPerUnit: 140, pricePerUnit: 1680, loading: 200, paid: 30000), ticket: '4598', mode: 'sacks');

    await accounts.saveVoucher({
      'kind': 'payment',
      'date': daysAgo(5),
      'party_id': f2,
      'cash_box_id': cropsBox,
      'amount': 20000,
      'handled_by': 'محمد',
      'notes': 'دفعة من حساب القمح',
    });
    await accounts.saveVoucher({
      'kind': 'receipt',
      'date': daysAgo(1),
      'party_id': t2,
      'cash_box_id': cropsBox,
      'amount': 25000,
      'handled_by': 'محمد',
      'notes': 'استلمها محمد وسلمها لأحمد',
    });
    await accounts.setCollectDate(t1, daysAgo(0));
    await accounts.setCollectDate(t2, daysAhead(3));

    await accounts.saveVoucher({'kind': 'expense', 'date': daysAgo(12), 'category': 'عتالة', 'cash_box_id': cropsBox, 'amount': 1800, 'handled_by': 'محمود'});
    await accounts.saveVoucher({'kind': 'expense', 'date': daysAgo(1), 'category': 'بنزين وسولار', 'cash_box_id': cropsBox, 'amount': 650});
    await accounts.saveVoucher({'kind': 'expense', 'date': daysAgo(0), 'category': 'نقل ونولون', 'cash_box_id': cropsBox, 'amount': 900, 'handled_by': 'مصطفى'});

    await crops.saveStockMove({'kind': 'adjust', 'date': daysAgo(2), 'item_type': 'crop', 'item_id': wheat, 'warehouse_id': shona, 'qty': -45, 'notes': 'هالك / جفاف'});

    db.person = 'محمد';
    await notes.save({
      'kind': 'money',
      'body': 'الحاج سيد ساب 3000 جنيه مع محمد علشان تتسلم لأحمد',
      'amount': 3000,
      'person': 'أحمد',
      'due_date': daysAgo(0),
      'pinned': true,
    });
    db.person = 'أحمد';
    await notes.save({'kind': 'task', 'body': 'نكلم مطحن الدلتا على باقي حساب القمح', 'due_date': daysAhead(1)});
    await notes.save({'kind': 'note', 'body': 'الشونة محتاجة مشمعات قبل الشتا', 'division': Division.all});

    await db.close();
  });

  test('showroom (appliances) database', () async {
    final db = await _fresh(Division.appliances);
    final accounts = AccountsRepo(db);
    final app = AppliancesRepo(db);
    final notes = NotesRepo(db);

    await accounts.saveSettings({
      'company_name': defaultCompanyName,
      'company_phone': '01000000000',
      'company_address': 'المنصورة - شارع الجمهورية',
      'invoice_footer': 'البضاعة المباعة ترد خلال 14 يوم بحالتها',
      'default_markup_pct': '15',
    });
    await accounts.saveCashBox({'opening_balance': 200000}, id: appliancesBox);

    Future<String> party(String name, String kind, String phone, [double opening = 0]) =>
        accounts.saveParty({'name': name, 'kind': kind, 'phone': phone, 'opening_balance': opening});

    final c1 = await party('أم أحمد', 'customer', '01066666666');
    final c2 = await party('محمد السيد', 'customer', '01077777777');
    final c3 = await party('هاني جمال', 'customer', '01088888888', 1500);
    final s1 = await party('توكيل الأجهزة الحديثة', 'supplier', '01099999999');

    Future<String> product(String name, String cat, String brand, String model, double cost, double retail, double wholesale, double min,
            String barcode) =>
        app.saveProduct({
          'name': name,
          'category': cat,
          'brand': brand,
          'model': model,
          'cost_price': cost,
          'retail_price': retail,
          'wholesale_price': wholesale,
          'min_qty': min,
          'barcode': barcode,
        });

    // Our own short numbers, except the iron, which keeps the barcode printed
    // on its box: both kinds are read by the same scanner.
    final fridge = await product('ثلاجة 16 قدم نوفروست', 'ثلاجات', 'شارب', 'SJ-48', 21000, 24500, 23300, 2, '4821');
    final washer = await product('غسالة أوتوماتيك 7 كيلو', 'غسالات', 'توشيبا', 'TW-7', 14500, 17200, 16300, 2, '5307');
    final stove = await product('بوتاجاز 5 شعلة', 'بوتاجازات', 'يونيفرسال', 'U-5', 8200, 9800, 9200, 3, '6142');
    final tv = await product('شاشة 43 بوصة سمارت', 'شاشات', 'سامسونج', 'UA43', 11800, 13900, 13200, 3, '7038');
    final fan = await product('مروحة ستاند 18 بوصة', 'مراوح', 'فريش', 'F-18', 1150, 1450, 1350, 5, '8290');
    final blender = await product('خلاط 1.5 لتر', 'أجهزة صغيرة', 'مولينكس', 'LM2', 1700, 2150, 2000, 4, '3417');
    final kettle = await product('غلاية كهربا 1.7 لتر', 'أجهزة صغيرة', 'تورنيدو', 'K17', 650, 850, 780, 5, '2965');
    final iron = await product('مكواة بخار', 'أجهزة صغيرة', 'فيليبس', 'GC1', 900, 1150, 1080, 3, '6221000000080');

    Future<String> invoice(String kind, int ago, String? partyId, String payment, List<InvoiceLineDraft> lines,
        {double discount = 0, double paid = 0, double markupPct = 0, int months = 0, String source = 'form'}) {
      final subtotal = lines.fold<double>(0, (a, l) => a + l.total);
      final total = subtotal - discount;
      InstallmentPlan? plan;
      if (payment == 'installment') {
        plan = InstallmentPlan(
          total: total,
          downPayment: paid,
          markupPct: markupPct,
          months: months,
          firstDue: DateTime.now().subtract(Duration(days: ago)).add(const Duration(days: 30)),
        );
      }
      final grand = plan?.grandTotal ?? total;
      return app.saveInvoice(
        header: {
          'kind': kind,
          'date': daysAgo(ago),
          'party_id': partyId,
          'customer_name': partyId == null ? 'زبون' : null,
          'warehouse_id': showroom,
          'cash_box_id': appliancesBox,
          'price_level': 'retail',
          'payment_type': payment,
          'subtotal': subtotal,
          'discount': discount,
          'total': total,
          'markup_pct': markupPct,
          'markup_amount': plan?.markup ?? 0,
          'grand_total': grand,
          'paid_amount': payment == 'cash' ? grand : paid,
          'inst_months': months,
          'inst_first_due': plan == null ? null : dateStr(plan.firstDue),
          'source': source,
        },
        lines: lines,
        schedule: plan?.schedule ?? const [],
      );
    }

    InvoiceLineDraft l(String id, double q, double p) => InvoiceLineDraft(productId: id, name: '', qty: q, price: p);

    await invoice('purchase', 60, s1, 'credit', [
      l(fridge, 6, 21000),
      l(washer, 6, 14500),
      l(stove, 8, 8200),
      l(tv, 5, 11800),
      l(fan, 20, 1150),
      l(blender, 10, 1700),
      l(kettle, 12, 650),
      l(iron, 3, 900),
    ], discount: 5000, paid: 150000);
    final inst1 = await invoice('sale', 95, c1, 'installment', [l(fridge, 1, 24500), l(stove, 1, 9800)], paid: 6000, markupPct: 15, months: 10);
    db.person = 'محمد';
    final inst2 = await invoice('sale', 40, c2, 'installment', [l(washer, 1, 17200)], paid: 3000, markupPct: 15, months: 8);
    await invoice('sale', 18, c3, 'credit', [l(tv, 1, 13900), l(fan, 2, 1450)], paid: 5000);
    await invoice('sale', 5, null, 'cash', [l(fan, 3, 1450), l(blender, 2, 2150)], source: 'pos');
    await invoice('sale', 3, null, 'cash', [l(kettle, 2, 850)], source: 'pos');
    db.person = 'أحمد';
    await invoice('sale', 1, null, 'cash', [l(iron, 1, 1150), l(kettle, 1, 850)], source: 'pos');
    await invoice('sale', 0, null, 'cash', [l(tv, 1, 13900)], discount: 400, source: 'pos');
    await invoice('sale', 0, c1, 'cash', [l(blender, 1, 2150)], source: 'pos');
    await invoice('sale', 0, null, 'cash', [l(kettle, 3, 850), l(fan, 1, 1450)], source: 'pos');

    await accounts.saveVoucher({'kind': 'receipt', 'date': daysAgo(64), 'party_id': c1, 'cash_box_id': appliancesBox, 'amount': 3320, 'invoice_id': inst1, 'notes': 'قسط 1', 'handled_by': 'أحمد'});
    await accounts.saveVoucher({'kind': 'receipt', 'date': daysAgo(33), 'party_id': c1, 'cash_box_id': appliancesBox, 'amount': 3320, 'invoice_id': inst1, 'notes': 'قسط 2', 'handled_by': 'محمد'});
    await accounts.saveVoucher({'kind': 'receipt', 'date': daysAgo(9), 'party_id': c2, 'cash_box_id': appliancesBox, 'amount': 2000, 'invoice_id': inst2, 'notes': 'قسط 1', 'handled_by': 'محمد'});
    await accounts.saveVoucher({'kind': 'payment', 'date': daysAgo(10), 'party_id': s1, 'cash_box_id': appliancesBox, 'amount': 40000, 'handled_by': 'أحمد'});
    await accounts.setCollectDate(c3, daysAgo(2));

    await accounts.saveVoucher({'kind': 'expense', 'date': daysAgo(8), 'category': 'إيجار', 'cash_box_id': appliancesBox, 'amount': 6000});
    await accounts.saveVoucher({'kind': 'expense', 'date': daysAgo(4), 'category': 'مرتبات', 'cash_box_id': appliancesBox, 'amount': 9000});
    await accounts.saveVoucher({'kind': 'expense', 'date': daysAgo(0), 'category': 'كهرباء ومياه', 'cash_box_id': appliancesBox, 'amount': 750});

    db.person = 'محمد';
    await notes.save({
      'kind': 'money',
      'body': 'هاني جمال ساب 2000 جنيه لأحمد من حساب الشاشة',
      'amount': 2000,
      'person': 'أحمد',
      'due_date': daysAgo(0),
      'pinned': true,
    });
    db.person = 'أحمد';
    await notes.save({'kind': 'task', 'body': 'طلبية مراوح وغلايات من التوكيل قبل الصيف', 'due_date': daysAhead(2)});

    await db.close();
  });
}
