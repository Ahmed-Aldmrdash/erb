import 'dart:convert';
import 'dart:math';

import '../core/util/format.dart';

/// Weight, price and expense arithmetic of one crop weighing.
///
/// On the weighbridge (باسكول): the loaded truck (القائم) minus the empty
/// truck (الفارغ). By the sack: [grossKg] is the total of the sack weights
/// and [tareKg] stays 0. Empty sacks, moisture and impurities are deducted
/// in kilos.
class CropCalc {
  const CropCalc({
    required this.isSale,
    this.grossKg = 0,
    this.tareKg = 0,
    this.bagsCount = 0,
    this.bagWeightKg = 0,
    this.moistureKg = 0,
    this.impuritiesKg = 0,
    this.moisturePct = 0,
    this.impuritiesPct = 0,
    this.otherDeductionKg = 0,
    this.kgPerUnit = 1000,
    this.pricePerUnit = 0,
    this.freight = 0,
    this.loading = 0,
    this.otherExpenses = 0,
    this.expensesOnParty = false,
    this.paid = 0,
  });

  final bool isSale;
  final double grossKg;
  final double tareKg;
  final double bagsCount;
  final double bagWeightKg;
  final double moistureKg;
  final double impuritiesKg;

  /// Old weighings stored the quality deductions as percentages.
  final double moisturePct;
  final double impuritiesPct;
  final double otherDeductionKg;
  final double kgPerUnit;
  final double pricePerUnit;
  final double freight;
  final double loading;
  final double otherExpenses;
  final bool expensesOnParty;
  final double paid;

  /// The saved calculation of a crop_trades row.
  factory CropCalc.fromRow(Map<String, Object?> t) => CropCalc(
        isSale: t['kind'] == 'sale',
        grossKg: n(t['gross_kg']),
        tareKg: n(t['tare_kg']),
        bagsCount: n(t['bags_count']),
        bagWeightKg: n(t['bag_weight_kg']),
        moistureKg: n(t['moisture_kg']),
        impuritiesKg: n(t['impurities_kg']),
        moisturePct: n(t['moisture_pct']),
        impuritiesPct: n(t['impurities_pct']),
        otherDeductionKg: n(t['other_deduction_kg']),
        kgPerUnit: n(t['kg_per_unit']),
        pricePerUnit: n(t['price_per_unit']),
        freight: n(t['freight']),
        loading: n(t['loading']),
        otherExpenses: n(t['other_expenses']),
        expensesOnParty: n(t['expenses_on_party']) == 1,
        paid: n(t['paid_amount']),
      );

  /// What the scale shows without the empty truck.
  double get loadKg => round3(max(0, grossKg - tareKg));

  double get bagsKg => round3(bagsCount * bagWeightKg);

  /// Crop weight without the truck and the empty sacks.
  double get baseKg => round3(max(0, loadKg - bagsKg));

  double get moistureDeductionKg => round3(moistureKg + baseKg * moisturePct / 100);

  double get impuritiesDeductionKg => round3(impuritiesKg + baseKg * impuritiesPct / 100);

  double get qualityDeductionKg => round3(moistureDeductionKg + impuritiesDeductionKg);

  /// Weight that is paid for.
  double get netKg => round3(max(0, baseKg - qualityDeductionKg - otherDeductionKg));

  double get units => kgPerUnit > 0 ? netKg / kgPerUnit : 0;

  double get subtotal => roundMoney(units * pricePerUnit);

  double get expenses => roundMoney(freight + loading + otherExpenses);

  /// Amount posted to the farmer / trader account. Expenses charged to the
  /// party lower what we owe a farmer and raise what a trader owes us.
  double get partyTotal {
    if (!expensesOnParty) return subtotal;
    return roundMoney(isSale ? subtotal + expenses : subtotal - expenses);
  }

  /// A purchase adds the paid-for weight to stock. A sale removes everything
  /// that physically left, even what the buyer deducted for quality.
  double get stockKg => isSale ? baseKg : netKg;

  double get remaining => roundMoney(partyTotal - paid);

  /// Purchase: what the goods really cost us.
  double get cost => roundMoney(partyTotal + expenses);

  double get costPerKg => stockKg > 0 ? cost / stockKg : 0;

  /// Sale: what we keep after expenses.
  double get netRevenue => roundMoney(partyTotal - expenses);
}

/// Rounds [v] up to the nearest multiple of [step] (5 by default).
/// e.g. ceilToStep(4523) => 4525, ceilToStep(4520) => 4520.
double ceilToStep(double v, [double step = 5]) {
  if (v <= 0 || step <= 0) return v;
  return roundMoney((v / step).ceil() * step);
}

/// The steps the showroom rounds selling prices to. The chosen one is kept in
/// the settings as `price_round`.
const priceRoundSteps = [1.0, 5.0, 10.0, 20.0, 25.0, 50.0];

/// A selling price after the purchase price changed: the old margin is kept
/// (the price moves by the same ratio as the cost) and the result is rounded
/// **up** so prices stay neat numbers.
///
/// [marginPct] is only used for a product that has no selling price yet, or
/// whose old price is below the new cost.
///
/// [fillEmpty] is false for a price the showroom never set (a product sold
/// retail only keeps its empty wholesale price).
double priceFollowingCost({
  required double oldCost,
  required double newCost,
  required double oldPrice,
  double step = 10,
  double marginPct = 0,
  bool fillEmpty = true,
}) {
  if (newCost <= 0) return oldPrice;
  double fromMargin() => marginPct > 0 ? ceilToStep(newCost * (1 + marginPct / 100), step) : 0;
  if (oldPrice <= 0) return fillEmpty ? fromMargin() : 0;
  // A price that no longer covers the cost is rebuilt from the margin.
  if (oldPrice <= newCost) {
    final m = fromMargin();
    return m > 0 ? m : ceilToStep(newCost, step);
  }
  if (oldCost <= 0) return oldPrice;
  if ((oldCost - newCost).abs() < 0.01) return oldPrice;
  return ceilToStep(oldPrice * newCost / oldCost, step);
}

class PlannedInstallment {
  const PlannedInstallment(this.seq, this.dueDate, this.amount);

  final int seq;
  final DateTime dueDate;
  final double amount;
}

class InstallmentPlan {
  InstallmentPlan({
    required this.total,
    required this.downPayment,
    required this.markupPct,
    required this.months,
    required this.firstDue,
  });

  final double total;
  final double downPayment;
  final double markupPct;
  final int months;
  final DateTime firstDue;

  double get financed => roundMoney(max(0, total - downPayment));

  double get markup => roundMoney(financed * markupPct / 100);

  double get toCollect => roundMoney(financed + markup);

  double get grandTotal => roundMoney(total + markup);

  /// Monthly installments rounded down to whole pounds; the last one takes
  /// the remainder.
  List<PlannedInstallment> get schedule {
    if (months <= 0 || toCollect <= 0) return const [];
    var each = (toCollect / months).floorToDouble();
    if (each <= 0) each = roundMoney(toCollect / months);
    final list = <PlannedInstallment>[];
    for (var i = 0; i < months; i++) {
      final isLast = i == months - 1;
      final amount = isLast ? roundMoney(toCollect - each * (months - 1)) : each;
      list.add(PlannedInstallment(i + 1, addMonths(firstDue, i), amount));
    }
    return list;
  }
}

enum InstallmentState { paid, partial, due, overdue }

class InstallmentStatus {
  InstallmentStatus({
    required this.id,
    required this.seq,
    required this.dueDate,
    required this.amount,
    required this.paid,
  });

  final String id;
  final int seq;
  final String dueDate;
  final double amount;
  final double paid;

  double get remaining => roundMoney(max(0, amount - paid));

  InstallmentState stateOn(String today) {
    if (remaining <= 0.009) return InstallmentState.paid;
    if (dueDate.compareTo(today) < 0) return InstallmentState.overdue;
    return paid > 0.009 ? InstallmentState.partial : InstallmentState.due;
  }
}

/// Spreads everything collected on an invoice over its installments, oldest
/// first. Partial payments and overpayments are handled naturally.
List<InstallmentStatus> allocateInstallments(
  List<({String id, int seq, String dueDate, double amount})> items,
  double collected,
) {
  final sorted = [...items]..sort((a, b) => a.seq.compareTo(b.seq));
  var left = collected;
  return [
    for (final it in sorted)
      () {
        final paid = roundMoney(max(0.0, min(it.amount, left)));
        left -= paid;
        return InstallmentStatus(
          id: it.id,
          seq: it.seq,
          dueDate: it.dueDate,
          amount: it.amount,
          paid: paid,
        );
      }(),
  ];
}

class InvoiceTotals {
  const InvoiceTotals({required this.subtotal, required this.discount});

  final double subtotal;
  final double discount;

  double get total => roundMoney(max(0, subtotal - discount));
}

/// Sack weights saved as a JSON list.
List<double> sackWeightsOf(Object? json) {
  final text = s(json);
  if (text.isEmpty) return const [];
  try {
    return [for (final v in jsonDecode(text) as List) n(v)];
  } catch (_) {
    return const [];
  }
}

String sackWeightsJson(List<double> weights) => jsonEncode([for (final w in weights) round3(w)]);

/// Numbers written in a notebook line or read from a photo: Arabic or
/// Western digits, "49.5" / "49,5" / "٤٩٫٥". Thousands separators ("1,250")
/// are understood too.
List<double> parseWeights(String text) {
  const eastern = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in text.split('')) {
    var i = eastern.indexOf(ch);
    if (i < 0) i = persian.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else {
      b.write(switch (ch) { '٫' => '.', '٬' => ',', '،' => ' ', _ => ch });
    }
  }
  final t = b.toString();
  final out = <double>[];
  for (final m in RegExp(r'\d+(?:[.,]\d+)*').allMatches(t)) {
    var v = m.group(0)!;
    final parts = v.split(RegExp('[.,]'));
    if (parts.length == 2 && parts[1].length != 3) {
      v = '${parts[0]}.${parts[1]}';
    } else if (parts.length > 1 && parts.skip(1).every((p) => p.length == 3)) {
      v = parts.join();
    } else if (parts.length > 2) {
      // "49.5.3": keep the first number only.
      v = '${parts[0]}.${parts[1]}';
    }
    final d = double.tryParse(v);
    if (d != null && d > 0) out.add(d);
  }
  return out;
}
