import 'dart:convert';

import 'app_state.dart';
import 'util/format.dart';

/// Products waiting for a price label to be printed, kept on this phone only.
///
/// Only the product and how many stickers it needs are stored: the name, the
/// code and the price are read from the database when the sheet is printed,
/// so a label never carries a price that was changed in the meantime.
class LabelQueue {
  static const _key = 'label_queue';

  /// {productId: how many stickers}, in the order they were added.
  static Map<String, int> items() {
    try {
      final raw = jsonDecode(app.prefs.get(_key, '{}'));
      if (raw is! Map) return {};
      return {
        for (final e in raw.entries)
          if (s(e.key).isNotEmpty && ni(e.value) > 0) s(e.key): ni(e.value),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save(Map<String, int> items) => app.prefs.set(_key, jsonEncode(items));

  static Future<void> add(String productId, int count) async {
    if (productId.isEmpty || count <= 0) return;
    final all = items();
    all[productId] = (all[productId] ?? 0) + count;
    await _save(all);
  }

  static Future<void> setCount(String productId, int count) async {
    final all = items();
    if (count <= 0) {
      all.remove(productId);
    } else {
      all[productId] = count;
    }
    await _save(all);
  }

  static Future<void> remove(String productId) => setCount(productId, 0);

  /// Puts a whole set of products in the list at once, each with the number
  /// of stickers it needs. Asking twice gives the same list, not double.
  static Future<int> setAll(Map<String, int> counts) async {
    final all = items();
    var touched = 0;
    for (final e in counts.entries) {
      if (e.key.isEmpty || e.value <= 0) continue;
      all[e.key] = e.value;
      touched++;
    }
    await _save(all);
    return touched;
  }

  static Future<void> clear() => _save({});

  static int get total => items().values.fold(0, (a, b) => a + b);
}
