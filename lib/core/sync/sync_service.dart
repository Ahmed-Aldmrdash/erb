import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:supabase/supabase.dart';

import '../db/app_db.dart';
import 'supabase_remote.dart';
import 'sync_engine.dart';

enum SyncPhase { idle, running, offline, error }

/// Decides when to sync: shortly after local edits, every 45 seconds, when the
/// app comes back to the foreground, and right after another phone announces
/// a change over a Supabase realtime broadcast.
class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  SyncService(this.db, this.client, {this.onSessionLost, this.onServerReset})
      : engine = SyncEngine(db, SupabaseRemote(client));

  final AppDb db;
  final SupabaseClient client;
  final SyncEngine engine;

  /// Called when the server refuses the session (password changed, signed
  /// out from the manager's phone...).
  final void Function()? onSessionLost;

  /// Called when the server data was wiped (supabase/reset_data.sql): the
  /// phone must drop its old copy instead of uploading it again.
  final void Function(String resetId)? onServerReset;

  SyncPhase phase = SyncPhase.idle;
  String? error;
  DateTime? lastSync;
  int pending = 0;

  Timer? _timer;
  Timer? _debounce;
  RealtimeChannel? _channel;
  bool _running = false;
  bool _again = false;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    db.onLocalWrite = () {
      refreshPending();
      schedule();
    };
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => syncNow());
    _channel = client.channel('erp-sync')
      ..onBroadcast(
        event: 'changed',
        callback: (_) => schedule(const Duration(milliseconds: 800)),
      )
      ..subscribe();
    refreshPending();
    syncNow();
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    db.onLocalWrite = null;
    _timer?.cancel();
    _debounce?.cancel();
    final ch = _channel;
    _channel = null;
    if (ch != null) await client.removeChannel(ch);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncNow();
  }

  void schedule([Duration delay = const Duration(seconds: 2)]) {
    if (!_started) return;
    _debounce?.cancel();
    _debounce = Timer(delay, syncNow);
  }

  Future<void> refreshPending() async {
    pending = await db.pendingCount();
    notifyListeners();
  }

  Future<void> syncNow() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    phase = SyncPhase.running;
    notifyListeners();
    String? resetTo;
    try {
      final r = await engine.run();
      lastSync = DateTime.now();
      phase = SyncPhase.idle;
      error = null;
      if (r.pushed > 0) {
        unawaited(_channel?.sendBroadcastMessage(event: 'changed', payload: {'device': db.deviceCode}));
      }
    } on ServerResetException catch (e) {
      resetTo = e.resetId;
    } catch (e) {
      final offline = isOfflineError(e);
      phase = offline ? SyncPhase.offline : SyncPhase.error;
      error = offline ? 'مش قادر يوصل للسيرفر' : '$e';
      if (e is PostgrestException && e.code == '42501') onSessionLost?.call();
    } finally {
      _running = false;
      if (resetTo == null) {
        await refreshPending();
        if (_again) {
          _again = false;
          schedule(const Duration(milliseconds: 300));
        }
      }
    }
    // The app closes this database and opens a fresh one.
    if (resetTo != null) onServerReset?.call(resetTo);
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

bool isOfflineError(Object e) {
  if (e is SocketException || e is TimeoutException || e is HandshakeException) return true;
  final t = e.toString();
  return t.contains('SocketException') ||
      t.contains('ClientException') ||
      t.contains('Failed host lookup') ||
      t.contains('Connection refused') ||
      t.contains('Network is unreachable');
}
