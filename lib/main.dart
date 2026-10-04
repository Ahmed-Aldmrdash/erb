import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/app_state.dart';
import 'core/platform.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktop) {
    // On a phone sqflite talks to the system SQLite through the platform; on
    // a laptop it needs the bundled engine, and it has to be told where to
    // keep the files — otherwise they land next to wherever the program was
    // started from, and the same laptop ends up with two sets of books.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await getApplicationSupportDirectory();
    await databaseFactory.setDatabasesPath(dir.path);
  }
  app = AppState();
  runApp(const TradeErpApp());
  await app.init();
}
