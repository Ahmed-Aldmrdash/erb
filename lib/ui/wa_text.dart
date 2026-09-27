import '../core/app_state.dart';
import '../core/db/app_db.dart';
import '../core/util/format.dart';
import '../data/calc.dart';
import '../data/labels.dart';
import 'widgets.dart';

/// WhatsApp texts: a greeting, one fact per line with the important numbers
/// in *bold*, then who we are. Balances are told from the customer's side
/// ("عليك لينا" / "ليك عندنا").
class WaText {
  static String _hello(String name) => name.trim().isEmpty ? 'السلام عليكم' : 'السلام عليكم يا ${name.trim()}';

  static String get signature {
    final phone = app.settings['company_phone'] ?? '';
    return [
      '*${app.companyName}* - ${app.divisionName}',
      if (phone.isNotEmpty) 'للتواصل: $phone',
    ].join('\n');
  }

  static String _lines(List<String> lines) => lines.join('\n');

  /// Reminder of the account balance.
  static String account({required String name, required double balance, String collectOn = '', String? lastMove}) =>
      _lines([
        _hello(name),
        'رصيد حسابك معانا لحد النهارده:',
        '*${balanceForParty(balance)}*',
        if (balance > 0.009 && collectOn.isNotEmpty) 'ميعاد السداد المتفق عليه: ${showDate(collectOn)}',
        if (lastMove != null && lastMove.isNotEmpty) 'آخر حركة: $lastMove',
        '',
        balance > 0.009 ? 'نرجو السداد في أقرب وقت، وشكراً لحضرتك 🌷' : 'شكراً لتعاملك معانا 🌷',
        signature,
      ]);

  /// Money received, paid, an advance or an adjustment of the account.
  static String voucher(DbRow v, double balanceAfter) {
    final amount = '*${egp(n(v['amount']))}*';
    final date = showDate(v['date']);
    final what = switch (s(v['kind'])) {
      'receipt' => '✅ استلمنا منك $amount يوم $date',
      'payment' => '✅ دفعنالك $amount يوم $date',
      'advance' => '✅ سلفة ليك $amount يوم $date',
      'debit_adj' => 'اتضاف على حسابك $amount يوم $date',
      'credit_adj' => 'اتخصم من حسابك $amount يوم $date',
      _ => '${voucherKinds[v['kind']] ?? ''} $amount يوم $date',
    };
    return _lines([
      _hello(s(v['party_name'])),
      what,
      if (s(v['notes']).isNotEmpty) 'البيان: ${s(v['notes'])}',
      if (s(v['invoice_number']).isNotEmpty) 'عن فاتورة رقم ${s(v['invoice_number'])}',
      'رصيد حسابك بعد كده: *${balanceForParty(balanceAfter)}*',
      '',
      'شكراً لحضرتك 🌷',
      signature,
    ]);
  }

  /// An invoice: totals, what is left, and the next installment.
  static String invoice(DbRow inv, {required double remaining, InstallmentStatus? nextDue}) {
    final isInstallment = inv['payment_type'] == 'installment';
    final name = s(inv['party_name']).isNotEmpty ? s(inv['party_name']) : s(inv['customer_name']);
    return _lines([
      _hello(name),
      '🧾 *${invoiceKinds[inv['kind']] ?? 'فاتورة'}* رقم ${s(inv['number'])} - ${showDate(inv['date'])}',
      if (n(inv['discount']) > 0) '• الخصم: ${egp(n(inv['discount']))}',
      '• الإجمالي: *${egp(n(inv['grand_total']))}*${isInstallment ? ' (بالتقسيط)' : ''}',
      '• المدفوع: ${egp(n(inv['grand_total']) - remaining)}',
      if (remaining > 0.009) '• الباقي: *${egp(remaining)}*',
      if (nextDue != null) '• القسط الجاي: رقم ${nextDue.seq} بـ *${egp(nextDue.remaining)}* يوم ${showDate(nextDue.dueDate)}',
      '',
      'شكراً لتعاملك معانا 🌷',
      signature,
    ]);
  }

  /// Reminder of a due installment.
  static String installment(DbRow inv, InstallmentStatus due, double remaining) {
    final late = due.dueDate.compareTo(todayStr()) < 0;
    return _lines([
      _hello(s(inv['party_name'])),
      '📅 نفكّرك بالقسط رقم ${due.seq} من فاتورة ${s(inv['number'])}',
      '• قيمته: *${egp(due.remaining)}*',
      late ? '• كان مستحق يوم ${showDate(due.dueDate)}' : '• مستحق يوم ${showDate(due.dueDate)}',
      '• الباقي على الفاتورة كلها: ${egp(remaining)}',
      '',
      'نرجو السداد في الميعاد، وشكراً لحضرتك 🌷',
      signature,
    ]);
  }

  /// A crop weighing with every step of the weight.
  static String cropTrade(DbRow t, CropCalc c, double balance) {
    final isSale = t['kind'] == 'sale';
    final unit = s(t['unit_name']);
    final kpu = n(t['kg_per_unit']);
    final sacks = s(t['weigh_mode']) == 'sacks';
    return _lines([
      _hello(s(t['party_name'])),
      '🌾 *${isSale ? 'بيع' : 'توريد'} ${s(t['crop_name'])}* رقم ${s(t['number'])} - ${showDate(t['date'])}',
      if (sacks)
        '• الشكاير: ${qty(c.bagsCount)} شكارة وزنها ${qty(c.grossKg)} كجم'
      else if (c.tareKg > 0)
        '• الميزان: القائم ${qty(c.grossKg)} - الفارغ ${qty(c.tareKg)} = ${qty(c.loadKg)} كجم'
      else
        '• الوزن: ${qty(c.grossKg)} كجم',
      if (c.bagsKg > 0 && !sacks) '• خصم الشكاير (${qty(c.bagsCount)} × ${qty(c.bagWeightKg)}): ${qty(c.bagsKg)} كجم',
      if (c.bagsKg > 0 && sacks) '• خصم وزن الشكاير الفاضية: ${qty(c.bagsKg)} كجم',
      if (c.moistureDeductionKg > 0) '• خصم الرطوبة: ${qty(c.moistureDeductionKg)} كجم',
      if (c.impuritiesDeductionKg > 0) '• خصم الشوائب: ${qty(c.impuritiesDeductionKg)} كجم',
      if (c.otherDeductionKg > 0) '• خصم تاني: ${qty(c.otherDeductionKg)} كجم',
      '• الصافي: *${qty(c.netKg)} كجم${kpu > 1 ? ' = ${unitsOf(c.netKg, unit, kpu)}' : ''}*',
      '• السعر: ${egp(c.pricePerUnit)} لل$unit',
      '• القيمة: *${egp(c.subtotal)}*',
      if (c.expensesOnParty && c.expenses > 0) '• مصاريف عليك (نولون وعتالة): ${egp(c.expenses)}',
      if (c.paid > 0) '• ${isSale ? 'المدفوع منك' : 'المدفوع ليك'}: ${egp(c.paid)}',
      'رصيد حسابك: *${balanceForParty(balance)}*',
      '',
      'شكراً لتعاملك معانا 🌷',
      signature,
    ]);
  }
}
