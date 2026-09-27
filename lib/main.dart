import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  app = AppState();
  runApp(const TradeErpApp());
  await app.init();
}
