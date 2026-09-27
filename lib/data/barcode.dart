import 'dart:math';

import '../core/util/format.dart';

/// كود الصنف والملصق.
///
/// Every product gets a number of its own that never changes ([newCode]): four
/// random digits, so all the numbers are the same length and nobody can guess
/// how many products the showroom has.
///
/// What gets printed as a barcode is that number **followed by the price**
/// ([labelBarcode]): `4821` + `04500` = `482104500`. Whoever is standing in
/// the showroom reads the price off the end of the number, and the scanner
/// still finds the product by the part in front, even after the price changed
/// and the label on the box became old ([priceOnLabel]).
class ProductCode {
  /// Digits of the product's own number.
  static const digits = 4;

  /// Digits the price takes on the label (up to 99,999 pounds).
  static const priceDigits = 5;

  /// Longest number we treat as one of ours. Anything longer is the barcode
  /// printed on the box by the factory: it goes on the label as it is.
  static const maxOwnCode = 6;

  static final _random = Random();

  /// A number for a new product. [taken] are the numbers already in use.
  static String newCode(Set<String> taken) {
    final first = pow(10, digits - 1).toInt(); // 1000
    final count = first * 9; // 1000..9999
    for (var i = 0; i < 400; i++) {
      final code = '${first + _random.nextInt(count)}';
      if (!taken.contains(code)) return code;
    }
    // A showroom never gets here (9,000 numbers), but a number must come out.
    var code = first;
    while (taken.contains('$code')) {
      code++;
    }
    return '$code';
  }

  /// What the barcode on the label carries: the product number, then the
  /// price in pounds. A price too big for [priceDigits] (or none yet) leaves
  /// the number alone.
  static String labelBarcode(String code, num price) {
    final pounds = price.round();
    if (code.isEmpty || pounds <= 0 || code.length > maxOwnCode) return code;
    final text = '$pounds';
    if (text.length > priceDigits + 1) return code;
    return code + text.padLeft(max(priceDigits, text.length), '0');
  }

  /// How the number reads on the label: "4821 04500".
  static String spaced(String code, num price) {
    final full = labelBarcode(code, price);
    return full.length > code.length ? '$code ${full.substring(code.length)}' : full;
  }

  /// The price written at the end of a scanned label, or null when the code
  /// was scanned on its own (or is a factory barcode).
  static double? priceOnLabel(String scanned, String code) {
    final tail = normalizeDigits(scanned.trim());
    if (code.length > maxOwnCode || !tail.startsWith(code) || tail.length <= code.length) return null;
    final rest = tail.substring(code.length);
    if (rest.length < 2 || rest.length > priceDigits + 1) return null;
    final value = double.tryParse(rest);
    return value == null || value <= 0 ? null : value;
  }
}
