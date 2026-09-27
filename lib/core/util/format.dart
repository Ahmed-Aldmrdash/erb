import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0.##', 'en');
final _qty = NumberFormat('#,##0.###', 'en');
final _int = NumberFormat('#,##0', 'en');

const currency = 'ج.م';

double roundMoney(num v) => (v * 100).roundToDouble() / 100;
double round3(num v) => (v * 1000).roundToDouble() / 1000;

/// Reads a numeric column value coming from SQLite (int, double or null).
double n(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int ni(Object? v) => n(v).round();

/// Reads a yes/no value whatever it came as: a real bool from the server's
/// JSON, 0/1 from SQLite, or "true"/"false" text. [orElse] is the answer for
/// a value that is missing altogether.
bool flag(Object? v, {bool orElse = false}) {
  if (v == null) return orElse;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final text = v.toString().trim().toLowerCase();
  if (text.isEmpty) return orElse;
  return text == 'true' || text == '1' || text == 'yes';
}

String s(Object? v) => v?.toString() ?? '';

/// A left-to-right mark keeps a leading minus sign on the left inside RTL text.
String _signed(String formatted, num v) => v < 0 ? '\u200E$formatted' : formatted;

String money(num? v) {
  final x = roundMoney(v ?? 0);
  return _signed(_money.format(x == 0 ? 0 : x), x);
}

String egp(num? v) => '${money(v)} $currency';

String qty(num? v) {
  final x = round3(v ?? 0);
  return _signed(_qty.format(x == 0 ? 0 : x), x);
}

String intf(num? v) => _int.format(v ?? 0);

/// Weight in kilograms plus the crop unit, e.g. "7,500 كجم • 50 أردب".
/// (No brackets: they get mirrored wrongly when RTL text wraps.)
String kgWithUnits(num kg, String? unitName, num kgPerUnit) {
  final base = '${qty(kg)} كجم';
  if (unitName == null || unitName.isEmpty || kgPerUnit <= 0 || kgPerUnit == 1) {
    return base;
  }
  return '$base • ${qty(kg / kgPerUnit)} $unitName';
}

String unitsOf(num kg, String? unitName, num kgPerUnit) {
  if (kgPerUnit <= 0) return '${qty(kg)} كجم';
  return '${qty(kg / kgPerUnit)} ${unitName ?? ''}'.trim();
}

// ---------------------------------------------------------------- numbers in

const _easternDigits = '٠١٢٣٤٥٦٧٨٩';
const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

/// Converts Arabic-Indic / Persian digits and separators so that numbers typed
/// on an Arabic keyboard parse correctly.
String normalizeDigits(String input) {
  final b = StringBuffer();
  for (final ch in input.split('')) {
    var i = _easternDigits.indexOf(ch);
    if (i < 0) i = _persianDigits.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (ch == '٫') {
      b.write('.');
    } else if (ch == '٬' || ch == ',' || ch == '،') {
      // thousands separators are ignored
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

double parseNum(String? text) {
  if (text == null) return 0;
  final t = normalizeDigits(text.trim());
  if (t.isEmpty) return 0;
  return double.tryParse(t) ?? 0;
}

/// Formats a number for an input field (no thousands separators).
String numText(num? v) {
  if (v == null || v == 0) return '';
  final x = round3(v);
  if (x == x.roundToDouble()) return x.toInt().toString();
  return x.toString();
}

// ---------------------------------------------------------------- dates

String dateStr(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String todayStr() => dateStr(DateTime.now());

DateTime? parseDate(Object? v) {
  final t = s(v);
  if (t.isEmpty) return null;
  return DateTime.tryParse(t.length >= 10 ? t.substring(0, 10) : t);
}

const arMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', //
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

const arWeekdays = [
  'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد', //
];

/// 21/9/2026
String showDate(Object? v) {
  final d = parseDate(v);
  if (d == null) return '';
  return '${d.day}/${d.month}/${d.year}';
}

/// الأحد 21 سبتمبر 2026
String longDate(DateTime d) =>
    '${arWeekdays[d.weekday - 1]} ${d.day} ${arMonths[d.month - 1]} ${d.year}';

String monthName(DateTime d) => '${arMonths[d.month - 1]} ${d.year}';

String nowIso() => DateTime.now().toUtc().toIso8601String();

DateTime addMonths(DateTime d, int months) {
  final total = d.month - 1 + months;
  final y = d.year + (total >= 0 ? total ~/ 12 : (total - 11) ~/ 12);
  final m = total % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > lastDay ? lastDay : d.day);
}

String firstOfMonth([DateTime? d]) {
  final x = d ?? DateTime.now();
  return dateStr(DateTime(x.year, x.month, 1));
}

String lastOfMonth([DateTime? d]) {
  final x = d ?? DateTime.now();
  return dateStr(DateTime(x.year, x.month + 1, 0));
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'الآن';
  if (d.inMinutes < 60) return 'من ${d.inMinutes} دقيقة';
  if (d.inHours < 24) return 'من ${d.inHours} ساعة';
  return showDate(dateStr(t.toLocal()));
}

// ---------------------------------------------------------------- arabic text

/// Folds letter variants so "احمد" finds "أحمد" and "مكرونه" finds "مكرونة".
String arFold(String input) => input
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp('[\u064B-\u0652\u0640]'), '')
    .toLowerCase()
    .trim();

/// SQL expression applying the same folding to a column.
String arFoldSql(String column) {
  var e = 'LOWER(IFNULL($column, \'\'))';
  for (final pair in const [
    ['أ', 'ا'], ['إ', 'ا'], ['آ', 'ا'], ['ٱ', 'ا'], //
    ['ة', 'ه'], ['ى', 'ي'], ['ـ', ''],
  ]) {
    e = "REPLACE($e, '${pair[0]}', '${pair[1]}')";
  }
  return e;
}

// ---------------------------------------------------------------- phones

/// Egyptian mobile numbers in international form for wa.me links.
String? waPhone(String? phone) {
  if (phone == null) return null;
  var p = normalizeDigits(phone).replaceAll(RegExp(r'[^0-9+]'), '');
  if (p.isEmpty) return null;
  if (p.startsWith('+')) return p.substring(1);
  if (p.startsWith('00')) return p.substring(2);
  if (p.startsWith('0')) return '20${p.substring(1)}';
  return p;
}
