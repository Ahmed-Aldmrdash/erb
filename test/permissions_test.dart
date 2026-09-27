import 'package:flutter_test/flutter_test.dart';
import 'package:trade_erp/data/permissions.dart';

/// What each login is allowed to open. An empty list means no limits, which
/// is what the accounts of the business itself carry, so nothing is taken
/// away from a phone that was working before this feature existed.
void main() {
  test('an empty list means no limits', () {
    expect(Perm.parse(''), isEmpty);
    expect(Perm.parse(null), isEmpty);
    expect(Perm.describe(''), 'كل الصلاحيات');
  });

  test('a list is read and written back the same way', () {
    expect(Perm.parse('pos,stock'), {Perm.pos, Perm.stock});
    // Spaces and empty pieces from an older phone do not break it.
    expect(Perm.parse(' pos , , stock '), {Perm.pos, Perm.stock});
    expect(Perm.write({Perm.stock, Perm.pos}), 'pos,stock');
    // Always in the same order, whatever order they were ticked in.
    expect(Perm.write({Perm.settings, Perm.pos, Perm.money}), 'pos,money,settings');
  });

  test('a cashier reads as the sections he works in', () {
    expect(Perm.describe('pos,stock'), 'الكاشير • المخزن والأصناف');
  });

  test('every section has a name and a line saying what it is for', () {
    for (final p in Perm.all) {
      expect(Perm.names[p], isNotNull, reason: p);
      expect(Perm.details[p], isNotNull, reason: p);
    }
    // The cashier sells and nothing else: no purchases, no money, no
    // touching invoices that are not his.
    expect(Perm.cashierPreset, [Perm.pos]);
    expect(Perm.cashierPreset.contains(Perm.sales), isFalse);
    expect(Perm.cashierPreset.contains(Perm.money), isFalse);
    expect(Perm.cashierPreset.every(Perm.all.contains), isTrue);
    expect(Perm.managerPreset.every(Perm.all.contains), isTrue);
    // The shop manager runs the business but does not touch the settings.
    expect(Perm.managerPreset.contains(Perm.settings), isFalse);
  });
}
