import 'package:flutter_test/flutter_test.dart';
import 'package:trade_erp/core/db/schema.dart';
import 'package:trade_erp/core/util/format.dart';
import 'package:trade_erp/data/labels.dart';

import 'ledger_test.dart' show Phone;

/// النواقص: what the shop ran out of. It shares the reminders table but is a
/// list of its own, and a line leaves it the moment the goods arrive.
void main() {
  late Phone shop;

  setUp(() async => shop = await Phone.open(Division.appliances));
  tearDown(() => shop.db.close());

  test('the missing list and the reminder board stay apart', () async {
    await shop.notes.save({'kind': needKind, 'body': '5 مراوح فريش', 'person': 'توكيل فريش'});
    await shop.notes.save({'kind': needKind, 'body': 'غلايات تورنيدو'});
    await shop.notes.save({'kind': 'task', 'body': 'نكلم المحاسب'});

    final needs = await shop.notes.list(done: false, kinds: const [needKind]);
    expect(needs.length, 2);
    expect(s(needs.first['body']), isNotEmpty);
    expect(await shop.notes.openCount(kinds: const [needKind]), 2);

    // The reminder board shows the task only.
    final board = await shop.notes.list(done: false, exceptKinds: const [needKind]);
    expect(board.length, 1);
    expect(s(board.single['body']), 'نكلم المحاسب');
    expect(await shop.notes.openCount(exceptKinds: const [needKind]), 1);
  });

  test('a line leaves the list when the goods arrive, and can come back', () async {
    await shop.notes.save({'kind': needKind, 'body': '5 مراوح فريش'});
    final need = (await shop.notes.list(done: false, kinds: const [needKind])).single;

    await shop.notes.setDone(s(need['id']), true);
    expect(await shop.notes.list(done: false, kinds: const [needKind]), isEmpty);

    final arrived = (await shop.notes.list(done: true, kinds: const [needKind])).single;
    expect(s(arrived['body']), '5 مراوح فريش');
    // Who said it arrived, and when.
    expect(s(arrived['done_by']), 'أحمد');
    expect(s(arrived['done_at']), isNotEmpty);

    // Said by mistake: it goes back to the missing list.
    await shop.notes.setDone(s(need['id']), false);
    expect((await shop.notes.list(done: false, kinds: const [needKind])).length, 1);
    expect(await shop.notes.list(done: true, kinds: const [needKind]), isEmpty);
  });

  test('searching finds a line by what it is or who brings it', () async {
    await shop.notes.save({'kind': needKind, 'body': '5 مراوح فريش', 'person': 'توكيل الأجهزة'});
    expect((await shop.notes.list(done: false, kinds: const [needKind], search: 'مراوح')).length, 1);
    expect((await shop.notes.list(done: false, kinds: const [needKind], search: 'توكيل')).length, 1);
    expect(await shop.notes.list(done: false, kinds: const [needKind], search: 'ثلاجة'), isEmpty);
  });
}
