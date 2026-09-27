import 'package:flutter_test/flutter_test.dart';
import 'package:trade_erp/core/db/app_db.dart';
import 'package:trade_erp/core/db/schema.dart';
import 'package:trade_erp/core/sync/sync_engine.dart';
import 'package:trade_erp/core/util/format.dart';
import 'package:trade_erp/data/accounts_repo.dart';
import 'package:trade_erp/data/appliances_repo.dart';
import 'package:trade_erp/data/notes_repo.dart';

import 'test_utils.dart';

/// Two phones sharing one fake server.
class Phone {
  Phone(this.db, this.remote) : engine = SyncEngine(db, remote);

  final AppDb db;
  final FakeRemote remote;
  final SyncEngine engine;

  AccountsRepo get accounts => AccountsRepo(db);
  AppliancesRepo get appliances => AppliancesRepo(db);
  NotesRepo get notes => NotesRepo(db);

  Future<SyncResult> sync() => engine.run();
}

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  late FakeServer server;
  late Phone a;
  late Phone b;

  setUp(() async {
    server = FakeServer();
    a = Phone(await openTestDb(), FakeRemote(server));
    b = Phone(await openTestDb(), FakeRemote(server));
  });

  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });

  test('records created on one phone reach the other', () async {
    final id = await a.accounts.saveParty({'name': 'عميل', 'opening_balance': 500});
    expect(await a.db.pendingCount(), 1);
    final r = await a.sync();
    expect(r.pushed, 1);
    expect(await a.db.pendingCount(), 0);

    await b.sync();
    final p = await b.accounts.party(id);
    expect(p?['name'], 'عميل');
    expect(n(p?['balance']), 500);
    // Pulled rows are clean: nothing to push back.
    expect(await b.db.pendingCount(), 0);
  });

  test('offline edits: the newest edit wins on every phone', () async {
    final id = await a.accounts.saveParty({'name': 'قديم'});
    await a.sync();
    await b.sync();

    a.remote.offline = true;
    b.remote.offline = true;
    await a.accounts.saveParty({'name': 'تعديل أ'}, id: id);
    await tick();
    await b.accounts.saveParty({'name': 'تعديل ب'}, id: id);

    // The newer edit (b) reaches the server first, the older one after it.
    b.remote.offline = false;
    await b.sync();
    a.remote.offline = false;
    await a.sync();
    await b.sync();

    expect((await a.accounts.party(id))?['name'], 'تعديل ب');
    expect((await b.accounts.party(id))?['name'], 'تعديل ب');
  });

  test('an unsent local edit is not overwritten by a pull', () async {
    final id = await a.accounts.saveParty({'name': 'اسم'});
    await a.sync();
    await b.sync();

    await b.accounts.saveParty({'name': 'من ب'}, id: id);
    await b.engine.pull();
    expect((await b.accounts.party(id))?['name'], 'من ب');
    expect(await b.db.pendingCount(), 1);
  });

  test('two phones editing one invoice never mix their lines', () async {
    final product = await a.appliances.saveProduct({'name': 'غسالة'});
    final other = await a.appliances.saveProduct({'name': 'شاشة'});
    // Both phones must have the goods before they can sell them.
    for (final id in [product, other]) {
      await a.db.write((w) => w.insert('stock_moves', {
            'kind': 'adjust',
            'date': '2026-01-01',
            'item_type': 'product',
            'item_id': id,
            'qty': 10,
          }));
    }
    Map<String, Object?> header(double qty) => {
          'kind': 'sale',
          'date': '2026-01-01',
          'payment_type': 'cash',
          'subtotal': qty * 100,
          'total': qty * 100,
          'grand_total': qty * 100,
          'paid_amount': qty * 100,
        };
    final inv = await a.appliances.saveInvoice(
      header: header(1),
      lines: [InvoiceLineDraft(productId: product, name: 'غسالة', qty: 1, price: 100)],
    );
    await a.sync();
    await b.sync();

    await a.appliances.saveInvoice(
      id: inv,
      header: header(2),
      lines: [InvoiceLineDraft(productId: product, name: 'غسالة', qty: 2, price: 100)],
    );
    await tick();
    await b.appliances.saveInvoice(
      id: inv,
      header: header(3),
      lines: [
        InvoiceLineDraft(productId: product, name: 'غسالة', qty: 1, price: 100),
        InvoiceLineDraft(productId: other, name: 'شاشة', qty: 2, price: 100),
      ],
    );
    await a.sync();
    await b.sync();
    await a.sync();

    for (final phone in [a, b]) {
      final lines = await phone.appliances.invoiceLines(inv);
      expect(lines.length, 2, reason: 'only the lines of the winning edit count');
      expect(lines.fold<double>(0, (s, l) => s + n(l['qty'])), 3);
      expect(n((await phone.appliances.product(product))!['stock']), 9);
      expect(n((await phone.appliances.product(other))!['stock']), 8);
    }
  });

  test('deletes propagate', () async {
    final v = await a.accounts.saveVoucher({'kind': 'deposit', 'date': '2026-01-01', 'amount': 100});
    await a.sync();
    await b.sync();
    expect(await b.accounts.voucher(v), isNotNull);
    await b.accounts.deleteVoucher(v);
    await b.sync();
    await a.sync();
    expect(n((await a.accounts.voucher(v))!['deleted']), 1);
    expect(await a.accounts.vouchers(), isEmpty);
  });

  test('recent changes are downloaded again until they are old enough', () async {
    await a.accounts.saveParty({'name': 'س'});
    await a.sync();
    await b.sync();
    // Written less than a minute ago on the server clock: position not saved.
    expect(await b.db.getMeta('seq:parties'), isNull);

    server.advance(const Duration(minutes: 2));
    await b.sync();
    expect(await b.db.getMeta('seq:parties'), '${server.seq}');
  });

  test('each division downloads only its own data, shared notes reach both', () async {
    final shop = Phone(await openTestDb(division: Division.appliances), FakeRemote(server));
    addTearDown(shop.db.close);
    final party = await a.accounts.saveParty({'name': 'فلاح'});
    final shared = await a.notes.save({'body': 'اجتماع بالليل', 'division': Division.all});
    final private = await a.notes.save({'body': 'للتجارة بس'});
    await a.sync();
    await shop.sync();
    expect(await shop.accounts.party(party), isNull);
    expect(await shop.notes.note(private), isNull);
    expect((await shop.notes.note(shared))?['body'], 'اجتماع بالليل');

    // Finishing a shared note on the showroom phone reaches the trade phone.
    shop.db.person = 'محمد';
    await tick();
    await shop.notes.setDone(shared, true);
    await shop.sync();
    await a.sync();
    final done = (await a.notes.note(shared))!;
    expect(n(done['done']), 1);
    expect(done['done_by'], 'محمد');
    expect(done['division'], Division.all);
  });

  test('after the server is wiped, an old copy is never uploaded again', () async {
    await a.accounts.saveParty({'name': 'تجربة'});
    await a.sync();
    expect(await a.db.getMeta('server_reset_id'), 'r1');

    server.wipe();
    await a.accounts.saveParty({'name': 'تجربة تانية'});
    await expectLater(a.sync(), throwsA(isA<ServerResetException>()));
    expect(server.tables['parties'] ?? const {}, isEmpty);

    // The app then opens a fresh database, which syncs normally.
    final fresh = Phone(await openTestDb(), FakeRemote(server));
    addTearDown(fresh.db.close);
    await fresh.accounts.saveParty({'name': 'حقيقي'});
    await fresh.sync();
    expect(server.tables['parties']!.length, 1);
    expect(await fresh.db.getMeta('server_reset_id'), server.resetId);
  });

  test('sync fails cleanly when offline and keeps the pending changes', () async {
    await a.accounts.saveParty({'name': 'بدون نت'});
    a.remote.offline = true;
    await expectLater(a.sync(), throwsA(anything));
    expect(await a.db.pendingCount(), 1);
    a.remote.offline = false;
    await a.sync();
    expect(await a.db.pendingCount(), 0);
  });
}
