import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/app_state.dart';
import '../features/auth/gate_screens.dart';
import '../features/home/home_shell.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class TradeErpApp extends StatelessWidget {
  const TradeErpApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        // Rebuilt when the open division changes, so the colors follow it.
        listenable: app,
        builder: (context, _) => MaterialApp(
          title: 'الدمرداش',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(AppColors.palette),
          locale: const Locale('ar', 'EG'),
          supportedLocales: const [Locale('ar', 'EG'), Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.25)),
              child: child!,
            );
          },
          home: const AppGate(),
        ),
      );
}

/// Shows setup, login, division choice or the app itself depending on
/// [AppState.gate].
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  Gate? _last;

  @override
  void initState() {
    super.initState();
    app.addListener(_onApp);
  }

  @override
  void dispose() {
    app.removeListener(_onApp);
    super.dispose();
  }

  void _onApp() {
    // Leaving the app (sign out, switching division): close open screens.
    if (_last == Gate.ready && app.gate != Gate.ready) {
      navigatorKey.currentState?.popUntil((r) => r.isFirst);
    }
    _last = app.gate;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (app.startupError != null) return StartupErrorScreen(error: app.startupError!);
    return switch (app.gate) {
      Gate.loading => const SplashScreen(),
      Gate.setupServer => const SetupServerScreen(),
      Gate.setupAccounts => const SetupAccountsScreen(),
      Gate.login => const LoginScreen(),
      Gate.pickDivision => const PickDivisionScreen(),
      Gate.syncing => const InitialSyncScreen(),
      Gate.ready => HomeShell(key: ValueKey(app.division)),
    };
  }
}
