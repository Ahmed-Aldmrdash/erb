import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trade_erp/core/app_state.dart';
import 'package:trade_erp/core/db/prefs.dart';
import 'package:trade_erp/core/db/schema.dart';
import 'package:trade_erp/core/label_queue.dart';

/// The list of products waiting for a price sticker. A product added anywhere
/// in the showroom lands here by itself, so nobody has to remember to ask for
/// its label.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('labels_test');
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

  test('products pile up in the list with a sticker for every piece', () async {
    final fridge = await app.appliances.saveProduct({'name': 'ثلاجة'});
    final fan = await app.appliances.saveProduct({'name': 'مروحة'});

    // Five pieces came in, so five stickers.
    await LabelQueue.add(fridge, 5);
    await LabelQueue.add(fan, 1);
    expect(LabelQueue.items(), {fridge: 5, fan: 1});
    expect(LabelQueue.total, 6);

    // The same product again adds to what is already waiting.
    await LabelQueue.add(fridge, 2);
    expect(LabelQueue.items()[fridge], 7);

    // Asking for a different number replaces it; zero takes it off the list.
    await LabelQueue.setCount(fridge, 3);
    expect(LabelQueue.items()[fridge], 3);
    await LabelQueue.setCount(fridge, 0);
    expect(LabelQueue.items().containsKey(fridge), isFalse);
    expect(LabelQueue.total, 1);
  });

  test('the list is kept on the phone and comes back after it is closed', () async {
    final id = await app.appliances.saveProduct({'name': 'غسالة'});
    await LabelQueue.add(id, 4);

    // The app is opened again: the same prefs file, a fresh read.
    final kept = app.prefs.get('label_queue');
    expect(kept, isNotEmpty);
    expect(LabelQueue.items(), {id: 4});

    await LabelQueue.clear();
    expect(LabelQueue.total, 0);
    expect(LabelQueue.items(), isEmpty);
  });

  test('nonsense in the list does not stop the printing screen', () async {
    await app.prefs.set('label_queue', 'not json at all');
    expect(LabelQueue.items(), isEmpty);
    await app.prefs.set('label_queue', '{"": 3, "x": 0, "ok": 2}');
    expect(LabelQueue.items(), {'ok': 2});
  });

  test('goods that were on the shelves before all go in at once', () async {
    final fridge = await app.appliances.saveProduct({'name': 'ثلاجة'});
    final fan = await app.appliances.saveProduct({'name': 'مروحة'});
    final oven = await app.appliances.saveProduct({'name': 'فرن'});

    // The fan was already waiting with a number somebody typed by hand.
    await LabelQueue.add(fan, 9);

    // Now the whole showroom goes in: a sticker for every piece on the shelf.
    final added = await LabelQueue.setAll({fridge: 4, fan: 2, oven: 1});
    expect(added, 3);
    expect(LabelQueue.items(), {fan: 2, fridge: 4, oven: 1});

    // Asking a second time gives the same list, not double.
    await LabelQueue.setAll({fridge: 4, fan: 2, oven: 1});
    expect(LabelQueue.total, 7);

    // A product that came in later keeps its place next to the old ones.
    final heater = await app.appliances.saveProduct({'name': 'دفاية'});
    await LabelQueue.add(heater, 3);
    expect(LabelQueue.items()[heater], 3);
    expect(LabelQueue.total, 10);
  });
}
