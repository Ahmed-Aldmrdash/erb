import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trade_erp/core/app_state.dart';
import 'package:trade_erp/core/db/prefs.dart';
import 'package:trade_erp/core/db/schema.dart';
import 'package:trade_erp/core/label_queue.dart';

/// "ظبط العدد للكل": one number for the whole label list, either added on top
/// of what each product already has, or the number they should all reach —
/// and a product that is already past that number is the owner's call, not
/// the app's.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('label_counts_test');
    await databaseFactoryFfi.setDatabasesPath(dir.path);
    app = AppState();
    app.prefs = await Prefs.open(path: '${dir.path}${Platform.pathSeparator}prefs.db', factory: databaseFactoryFfi);
    await app.prefs.set('mode', 'local');
    await app.prefs.set('person', 'أحمد');
    await app.openDivision(Division.appliances);
    await LabelQueue.clear();
  });

  tearDown(() async {
    await app.db.close();
    await app.prefs.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Three products in the list with 6, 1 and 25 stickers waiting.
  Future<(String, String, String)> queue() async {
    final a = await app.appliances.saveProduct({'name': 'ثلاجة'});
    final b = await app.appliances.saveProduct({'name': 'مروحة'});
    final c = await app.appliances.saveProduct({'name': 'كوباية'});
    await LabelQueue.add(a, 6);
    await LabelQueue.add(b, 1);
    await LabelQueue.add(c, 25);
    return (a, b, c);
  }

  test('ten more stickers for everything in the list', () async {
    final (a, b, c) = await queue();
    await LabelQueue.addToEach(10);
    expect(LabelQueue.items(), {a: 16, b: 11, c: 35});
    expect(LabelQueue.total, 62);
  });

  test('the ones already past the number are named, not changed quietly', () async {
    final (_, _, c) = await queue();
    // 25 is the only one past twenty, so it is the one he is asked about.
    expect(LabelQueue.above(20), {c: 25});
    expect(LabelQueue.above(30), isEmpty);
  });

  test('bringing the whole list up to one number leaves the big ones alone', () async {
    final (a, b, c) = await queue();
    await LabelQueue.raiseAllTo(20);
    expect(LabelQueue.items(), {a: 20, b: 20, c: 25});

    // Asking again changes nothing.
    await LabelQueue.raiseAllTo(20);
    expect(LabelQueue.items(), {a: 20, b: 20, c: 25});
  });

  test('or brings them down with the rest when he says so', () async {
    final (a, b, c) = await queue();
    await LabelQueue.raiseAllTo(20, lowerTheOnesAbove: true);
    expect(LabelQueue.items(), {a: 20, b: 20, c: 20});
    expect(LabelQueue.total, 60);
  });

  test('a number of zero or less is ignored instead of emptying the list', () async {
    final (a, b, c) = await queue();
    await LabelQueue.addToEach(0);
    await LabelQueue.raiseAllTo(-5);
    expect(LabelQueue.items(), {a: 6, b: 1, c: 25});
  });

  test('the numbers survive the app being closed', () async {
    final (a, b, c) = await queue();
    await LabelQueue.raiseAllTo(12);
    // reset() stands for the app starting again and reading the file.
    LabelQueue.reset();
    expect(LabelQueue.items(), {a: 12, b: 12, c: 25});
  });
}
