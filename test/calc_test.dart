import 'package:flutter_test/flutter_test.dart';
import 'package:trade_erp/core/util/format.dart';
import 'package:trade_erp/core/util/tafqit.dart';
import 'package:trade_erp/data/calc.dart';

void main() {
  group('CropCalc', () {
    test('weighbridge: gross minus the empty truck, deductions in kilos', () {
      const c = CropCalc(
        isSale: false,
        grossKg: 21330,
        tareKg: 6100,
        bagsCount: 100,
        bagWeightKg: 0.5,
        moistureKg: 150,
        impuritiesKg: 30,
        otherDeductionKg: 20,
        kgPerUnit: 150,
        pricePerUnit: 2150,
      );
      expect(c.loadKg, 15230);
      expect(c.bagsKg, 50);
      expect(c.baseKg, 15180);
      expect(c.moistureDeductionKg, 150);
      expect(c.impuritiesDeductionKg, 30);
      expect(c.qualityDeductionKg, 180);
      expect(c.netKg, 14980);
      expect(c.subtotal, roundMoney(14980 / 150 * 2150));
    });

    test('sacks: the total of the weights, minus the empty sacks', () {
      final weights = <double>[150, 149.5, 151, 148.5];
      final c = CropCalc(
        isSale: false,
        grossKg: weights.fold<double>(0, (a, w) => a + w),
        bagsCount: weights.length.toDouble(),
        bagWeightKg: 0.5,
        impuritiesKg: 4,
        kgPerUnit: 150,
        pricePerUnit: 2000,
      );
      expect(c.grossKg, 599);
      expect(c.baseKg, 597);
      expect(c.netKg, 593);
      expect(sackWeightsOf(sackWeightsJson(weights)), weights);
      expect(sackWeightsOf(''), isEmpty);
      expect(sackWeightsOf('not json'), isEmpty);
    });

    test('a saved row gives back the same calculation', () {
      final c = CropCalc.fromRow({
        'kind': 'sale',
        'gross_kg': 18200,
        'tare_kg': 6150,
        'bags_count': 80,
        'bag_weight_kg': 0.5,
        'moisture_kg': 60,
        'kg_per_unit': 150,
        'price_per_unit': 2350,
        'paid_amount': 1000,
      });
      expect(c.isSale, isTrue);
      expect(c.baseKg, 12010);
      expect(c.netKg, 11950);
      expect(c.stockKg, 12010);
      expect(c.paid, 1000);
    });

    test('old weighings with percentages still compute', () {
      const c = CropCalc(
        isSale: false,
        grossKg: 7600,
        bagsCount: 100,
        bagWeightKg: 1,
        moisturePct: 1.5,
        impuritiesPct: 0.5,
        kgPerUnit: 150,
        pricePerUnit: 2000,
        freight: 300,
        loading: 200,
      );
      expect(c.bagsKg, 100);
      expect(c.baseKg, 7500);
      expect(c.qualityDeductionKg, 150);
      expect(c.netKg, 7350);
      expect(c.units, closeTo(49, 1e-9));
      expect(c.subtotal, 98000);
      expect(c.expenses, 500);
      // Expenses on us: the farmer gets the full value.
      expect(c.partyTotal, 98000);
      expect(c.cost, 98500);
      expect(c.stockKg, 7350);
    });

    test('expenses charged to the farmer are deducted from his account', () {
      const c = CropCalc(isSale: false, grossKg: 1500, kgPerUnit: 150, pricePerUnit: 2000, freight: 400, expensesOnParty: true);
      expect(c.subtotal, 20000);
      expect(c.partyTotal, 19600);
      // We paid the driver and deducted it: the goods cost us the subtotal.
      expect(c.cost, 20000);
    });

    test('sale removes the physical weight but is paid on the net weight', () {
      const c = CropCalc(
        isSale: true,
        grossKg: 10100,
        bagsCount: 200,
        bagWeightKg: 0.5,
        moisturePct: 2,
        kgPerUnit: 1000,
        pricePerUnit: 15000,
        freight: 1000,
        expensesOnParty: true,
        paid: 100000,
      );
      expect(c.baseKg, 10000);
      expect(c.netKg, 9800);
      expect(c.stockKg, 10000);
      expect(c.subtotal, 147000);
      // Buyer pays the freight on top.
      expect(c.partyTotal, 148000);
      expect(c.netRevenue, 147000);
      expect(c.remaining, 48000);
    });
  });

  group('InstallmentPlan', () {
    test('markup, rounding and monthly due dates', () {
      final p = InstallmentPlan(
        total: 12000,
        downPayment: 2000,
        markupPct: 20,
        months: 12,
        firstDue: DateTime(2026, 1, 31),
      );
      expect(p.financed, 10000);
      expect(p.markup, 2000);
      expect(p.toCollect, 12000);
      expect(p.grandTotal, 14000);
      final s = p.schedule;
      expect(s.length, 12);
      expect(s.first.amount, 1000);
      expect(s.fold<double>(0, (a, x) => a + x.amount), 12000);
      // End of month is kept inside shorter months.
      expect(dateStr(s[1].dueDate), '2026-02-28');
      expect(dateStr(s[2].dueDate), '2026-03-31');
    });

    test('remainder goes to the last installment', () {
      final p = InstallmentPlan(total: 10000, downPayment: 0, markupPct: 0, months: 3, firstDue: DateTime(2026, 5, 1));
      final amounts = p.schedule.map((x) => x.amount).toList();
      expect(amounts, [3333, 3333, 3334]);
    });
  });

  test('collections are spread oldest first', () {
    final items = [
      (id: 'a', seq: 1, dueDate: '2026-01-01', amount: 1000.0),
      (id: 'b', seq: 2, dueDate: '2026-02-01', amount: 1000.0),
      (id: 'c', seq: 3, dueDate: '2026-03-01', amount: 1000.0),
    ];
    final st = allocateInstallments(items, 1500);
    expect(st.map((x) => x.paid).toList(), [1000, 500, 0]);
    expect(st[0].stateOn('2026-02-15'), InstallmentState.paid);
    expect(st[1].stateOn('2026-02-15'), InstallmentState.overdue);
    expect(st[1].stateOn('2026-01-15'), InstallmentState.partial);
    expect(st[2].stateOn('2026-02-15'), InstallmentState.due);
  });

  group('yes/no values', () {
    test('read the same whatever they came as', () {
      // The server answers with real booleans, SQLite with 0 and 1, and an
      // older phone could send text. Reading a "true" as a number used to
      // turn every working user account into a stopped one.
      expect(flag(true), isTrue);
      expect(flag(false), isFalse);
      expect(flag(1), isTrue);
      expect(flag(0), isFalse);
      expect(flag('true'), isTrue);
      expect(flag('1'), isTrue);
      expect(flag('false'), isFalse);
      // Missing means whatever the caller says it means.
      expect(flag(null), isFalse);
      expect(flag(null, orElse: true), isTrue);
      expect(flag('', orElse: true), isTrue);
    });
  });

  group('input helpers', () {
    test('arabic digits and separators', () {
      expect(parseNum('١٢٣٫٥'), 123.5);
      expect(parseNum('1,250.75'), 1250.75);
      expect(parseNum('۴۵'), 45);
      expect(parseNum(''), 0);
    });

    test('egyptian phone for whatsapp', () {
      expect(waPhone('01012345678'), '201012345678');
      expect(waPhone('+201012345678'), '201012345678');
      expect(waPhone('٠١٠١٢٣٤٥٦٧٨'), '201012345678');
      expect(waPhone(''), isNull);
    });

    test('arabic search folding', () {
      expect(arFold('أحمد'), arFold('احمد'));
      expect(arFold('مدرسة'), arFold('مدرسه'));
    });
  });

  group('weights from text', () {
    test('Arabic and Western digits, decimals and separators', () {
      expect(parseWeights('50 49.5 51'), [50, 49.5, 51]);
      expect(parseWeights('٥٠ ٤٩٫٥'), [50, 49.5]);
      expect(parseWeights('49,5'), [49.5]);
      expect(parseWeights('1,250 kg'), [1250]);
      expect(parseWeights('شكارة 1: 150\nشكارة 2: 151.5'), [1, 150, 2, 151.5]);
      expect(parseWeights('مفيش أرقام'), isEmpty);
    });
  });

  group('amount in words', () {
    test('Egyptian invoice style', () {
      expect(numberInWords(0), 'صفر');
      expect(numberInWords(15), 'خمسة عشر');
      expect(numberInWords(25), 'خمسة وعشرون');
      expect(numberInWords(100), 'مائة');
      expect(numberInWords(1000), 'ألف');
      expect(numberInWords(2000), 'ألفان');
      expect(numberInWords(3500), 'ثلاثة آلاف وخمسمائة');
      expect(numberInWords(11000), 'أحد عشر ألف');
      expect(numberInWords(38545), 'ثمانية وثلاثون ألف وخمسمائة وخمسة وأربعون');
      expect(numberInWords(1250000), 'مليون ومائتان وخمسون ألف');
      expect(amountInWords(3500.25), 'فقط ثلاثة آلاف وخمسمائة جنيه وخمسة وعشرون قرشاً لا غير');
      expect(amountInWords(0.5), 'فقط خمسون قرشاً لا غير');
    });
  });
}
