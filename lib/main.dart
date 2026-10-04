import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/app_state.dart';
import 'core/platform.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On a phone sqflite talks to the system SQLite through the platform; on a
  // laptop it needs the bundled engine instead.
  if (isDesktop) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  app = AppState();
  runApp(const TradeErpApp());
  await app.init();
}
