import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trade_erp/core/db/app_db.dart';
import 'package:trade_erp/core/db/schema.dart';
import 'package:trade_erp/core/sync/sync_engine.dart';
import 'package:trade_erp/core/util/uuid.dart';

bool _ffiReady = false;

/// A fresh database file of one division for one simulated phone.
Future<AppDb> openTestDb({String division = Division.crops}) async {
  if (!_ffiReady) {
    sqfliteFfiInit();
    _ffiReady = true;
  }
  final dir = Directory.systemTemp.createTempSync('erp_test_');
  return AppDb.open(
    division: division,
    path: '${dir.path}${Platform.pathSeparator}${newId()}.db',
    factory: databaseFactoryFfi,
  );
}

/// In-memory stand-in for Supabase that follows the same rules as the
/// triggers in supabase/schema.sql: every accepted write gets the next
/// sequence number, and an update older than the stored row is ignored but
/// still re-announced so the sender downloads the winner.
class FakeServer {
  int seq = 0;

  /// Changed by [wipe], like supabase/reset_data.sql.
  String resetId = 'r1';
  DateTime now = DateTime.utc(2026, 1, 1, 12);
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};

  void advance(Duration d) => now = now.add(d);

  void wipe() {
    tables.clear();
    resetId = 'r${seq + 2}';
  }

  void upsert(String table, List<Map<String, Object?>> rows) {
    final t = tables.putIfAbsent(table, () => {});
    for (final r in rows) {
      final id = r['id'] as String;
      final old = t[id];
      if (old != null) {
        final incoming = DateTime.tryParse('${r['updated_at']}');
        final stored = DateTime.tryParse('${old['updated_at']}');
        if (incoming != null && stored != null && incoming.isBefore(stored)) {
          old['sync_seq'] = ++seq;
          old['server_updated_at'] = now.toIso8601String();
          continue;
        }
      }
      t[id] = {...r, 'sync_seq': ++seq, 'server_updated_at': now.toIso8601String()};
    }
  }

  List<Map<String, dynamic>> pull(String table, int after, int limit, [List<String>? divisions]) {
    final rows = (tables[table]?.values ?? const <Map<String, dynamic>>[])
        .where((r) => (r['sync_seq'] as int) > after)
        .where((r) => divisions == null || divisions.contains(r['division']))
        .toList()
      ..sort((a, b) => (a['sync_seq'] as int).compareTo(b['sync_seq'] as int));
    return [for (final r in rows.take(limit)) Map<String, dynamic>.from(r)];
  }
}

class FakeRemote implements SyncRemote {
  FakeRemote(this.server);

  final FakeServer server;
  bool offline = false;

  void _check() {
    if (offline) throw const SocketException('offline');
  }

  @override
  Future<DateTime> serverNow() async {
    _check();
    return server.now;
  }

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows) async {
    _check();
    server.upsert(table, rows);
  }

  @override
  Future<List<Map<String, dynamic>>> pull(String table, int afterSeq, int limit, List<String> divisions) async {
    _check();
    return server.pull(table, afterSeq, limit, divisions);
  }

  @override
  Future<String?> resetId() async {
    _check();
    return server.resetId;
  }
}
