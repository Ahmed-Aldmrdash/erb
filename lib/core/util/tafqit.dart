/// تفقيط: an amount written in Arabic words for invoices and receipts,
/// e.g. 3500.25 → "فقط ثلاثة آلاف وخمسمائة جنيه وخمسة وعشرون قرشاً لا غير".
String amountInWords(num amount) {
  final cents = (amount.abs() * 100).round();
  final pounds = cents ~/ 100;
  final piasters = cents % 100;
  final parts = <String>[];
  if (pounds > 0 || piasters == 0) parts.add('${numberInWords(pounds)} جنيه');
  if (piasters > 0) parts.add('${numberInWords(piasters)} قرشاً');
  return 'فقط ${parts.join(' و')} لا غير';
}

const _ones = [
  '', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة', //
  'عشرة', 'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر', 'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر',
];
const _tens = ['', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
const _hundreds = ['', 'مائة', 'مائتان', 'ثلاثمائة', 'أربعمائة', 'خمسمائة', 'ستمائة', 'سبعمائة', 'ثمانمائة', 'تسعمائة'];

/// (one, two, 3-10, 11+) forms of thousand, million and billion.
const _scales = [
  ['ألف', 'ألفان', 'آلاف', 'ألف'],
  ['مليون', 'مليونان', 'ملايين', 'مليون'],
  ['مليار', 'ملياران', 'مليارات', 'مليار'],
];

String _below1000(int n) {
  final parts = <String>[];
  final h = n ~/ 100, r = n % 100;
  if (h > 0) parts.add(_hundreds[h]);
  if (r > 0 && r < 20) {
    parts.add(_ones[r]);
  } else if (r >= 20) {
    parts.add(r % 10 == 0 ? _tens[r ~/ 10] : '${_ones[r % 10]} و${_tens[r ~/ 10]}');
  }
  return parts.join(' و');
}

/// A whole number in Arabic words ("ثلاثة آلاف وخمسمائة").
String numberInWords(int n) {
  if (n == 0) return 'صفر';
  final groups = <int>[];
  for (var x = n; x > 0; x ~/= 1000) {
    groups.add(x % 1000);
  }
  final parts = <String>[];
  for (var i = groups.length - 1; i >= 0; i--) {
    final g = groups[i];
    if (g == 0) continue;
    if (i == 0) {
      parts.add(_below1000(g));
      continue;
    }
    final names = _scales[(i - 1).clamp(0, _scales.length - 1)];
    final last2 = g % 100;
    if (g == 1) {
      parts.add(names[0]);
    } else if (g == 2) {
      parts.add(names[1]);
    } else if (last2 >= 3 && last2 <= 10) {
      parts.add('${_below1000(g)} ${names[2]}');
    } else {
      parts.add('${_below1000(g)} ${names[3]}');
    }
  }
  return parts.join(' و');
}
