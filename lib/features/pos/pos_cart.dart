import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';

class CartLine {
  CartLine(this.product, this.qty, this.price);

  final DbRow product;
  double qty;
  double price;

  String get productId => s(product['id']);
  double get total => roundMoney(qty * price);
  double get stock => n(product['stock']);
}

/// The cashier's basket. It is kept on the phone, not only in memory: leaving
/// the cashier, going into the installment invoice, or even closing the app
/// never loses a sale that was being rung up.
class PosCart extends ChangeNotifier {
  PosCart._();

  static final instance = PosCart._();

  static const _key = 'pos_cart';

  final List<CartLine> lines = [];
  String priceLevel = 'retail';
  double discount = 0;
  DbRow? customer;

  bool get isEmpty => lines.isEmpty;
  double get count => lines.fold(0, (a, l) => a + l.qty);
  double get subtotal => roundMoney(lines.fold(0, (a, l) => a + l.total));
  double get total => roundMoney((subtotal - discount).clamp(0, double.infinity));

  double priceOf(DbRow product) =>
      n(product[priceLevel == 'wholesale' ? 'wholesale_price' : 'retail_price']);

  double qtyOf(String productId) => lines.where((l) => l.productId == productId).fold(0, (a, l) => a + l.qty);

  void add(DbRow product, [double qty = 1]) {
    final existing = lines.where((l) => l.productId == product['id']).firstOrNull;
    if (existing != null) {
      existing.qty += qty;
    } else {
      lines.add(CartLine(product, qty, priceOf(product)));
    }
    _changed();
  }

  void setQty(CartLine line, double qty) {
    if (qty <= 0) {
      lines.remove(line);
    } else {
      line.qty = qty;
    }
    _changed();
  }

  void setPrice(CartLine line, double price) {
    line.price = price;
    _changed();
  }

  void remove(CartLine line) {
    lines.remove(line);
    _changed();
  }

  void setLevel(String level) {
    priceLevel = level;
    for (final l in lines) {
      l.price = priceOf(l.product);
    }
    _changed();
  }

  void setDiscount(double v) {
    discount = v < 0 ? 0 : v;
    _changed();
  }

  void setCustomer(DbRow? c) {
    customer = c;
    _changed();
  }

  void clear() {
    lines.clear();
    discount = 0;
    customer = null;
    _changed();
  }

  void _changed() {
    notifyListeners();
    unawaited(_keep());
  }

  /// Latest prices and stock from the database, for a basket that was left
  /// open while somebody else was selling.
  Future<void> refresh() async {
    for (final l in [...lines]) {
      final p = await app.appliances.product(l.productId);
      if (p == null || n(p['deleted']) == 1) {
        lines.remove(l);
        continue;
      }
      lines[lines.indexOf(l)] = CartLine(p, l.qty, l.price);
    }
    notifyListeners();
  }

  Future<void> _keep() async {
    try {
      await app.prefs.set(
        _key,
        jsonEncode({
          'level': priceLevel,
          'discount': discount,
          'customer': customer?['id'],
          'lines': [
            for (final l in lines) {'id': l.productId, 'qty': l.qty, 'price': l.price},
          ],
        }),
      );
    } catch (_) {
      // A basket that could not be written down is not worth an error on the
      // cashier's screen; it still works for this session.
    }
  }

  /// Brings back the basket the phone was left with.
  Future<void> restore() async {
    if (lines.isNotEmpty) return;
    try {
      final raw = app.prefs.get(_key);
      if (raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      priceLevel = s(data['level']).isEmpty ? 'retail' : s(data['level']);
      discount = n(data['discount']);
      for (final item in (data['lines'] as List? ?? const [])) {
        if (item is! Map) continue;
        final p = await app.appliances.product(s(item['id']));
        if (p == null || n(p['deleted']) == 1) continue;
        lines.add(CartLine(p, n(item['qty']), n(item['price'])));
      }
      final customerId = s(data['customer']);
      if (customerId.isNotEmpty) customer = await app.accounts.party(customerId);
      notifyListeners();
    } catch (_) {
      // Rather an empty basket than a cashier that will not open.
    }
  }
}
