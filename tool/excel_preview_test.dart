// Builds the Excel exports from the demo databases for a check in Excel:
//   flutter test tool/demo_db_test.dart
//   flutter test tool/excel_preview_test.dart
// Output: build/excel_preview/*.xlsx
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trade_erp/core/app_state.dart';
import 'package:trade_erp/core/db/prefs.dart';
import 'package:trade_erp/core/db/schema.dart';
import 'package:trade_erp/features/common/excel_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('sample workbooks', () async {
    final dbDir = await databaseFactoryFfi.getDatabasesPath();
    Directory(dbDir).createSync(recursive: true);
    for (final f in ['erp_crops.db', 'erp_appliances.db']) {
      File('build/demo/$f').copySync('$dbDir${Platform.pathSeparator}$f');
    }
    app = AppState();
    app.prefs = await Prefs.open(path: '$dbDir${Platform.pathSeparator}erp_prefs_preview.db', factory: databaseFactoryFfi);
    await app.prefs.set('mode', 'local');
    await app.prefs.set('person', 'أحمد');
    final out = Directory('build/excel_preview')..createSync(recursive: true);
    void save(String name, List<XSheet> sheets) =>
        File('${out.path}${Platform.pathSeparator}$name.xlsx').writeAsBytesSync(ExcelExport.encode(sheets));

    await app.openDivision(Division.appliances);
    save('products', [await ExcelExport.products()]);
    save('appliances_all', await ExcelExport.everything());

    await app.openDivision(Division.crops);
    save('crops', [await ExcelExport.crops()]);
    save('crops_all', await ExcelExport.everything());
  });
}
