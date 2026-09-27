import 'package:sqflite/sqflite.dart';

import '../db/app_db.dart';
import '../db/schema.dart';
import '../util/format.dart';

/// What the sync engine needs from the server. Implemented with Supabase in
/// production and with an in-memory fake in tests.
abstract class SyncRemote {
  Future<DateTime> serverNow();

  /// Insert or update rows by id. The server keeps whichever version has the
  /// newest updated_at and gives every accepted change a new sync_seq.
  Future<void> upsert(String table, List<Map<String, Object?>> rows);

  /// Rows of [divisions] with sync_seq > [afterSeq], ordered by sync_seq.
  Future<List<Map<String, dynamic>>> pull(String table, int afterSeq, int limit, List<String> divisions);

  /// Changes every time the server data is wiped (supabase/reset_data.sql);
  /// null when the server does not know it.
  Future<String?> resetId();
}

/// The server data was wiped: what this phone keeps belongs to the old data
/// and must not be uploaded again.
class ServerResetException implements Exception {
  const ServerResetException(this.resetId);

  final String resetId;

  @override
  String toString() => 'ServerResetException($resetId)';
}

class SyncResult {
  const SyncResult(this.pushed, this.pulled);

  final int pushed;
  final int pulled;
}

/// Offline-first sync: every change is saved on the phone first (dirty = 1),
/// pushed when there is a connection, and other phones pull everything newer
/// than the last sequence number they saw.
class SyncEngine {
  SyncEngine(
    this.db,
    this.remote, {
    this.lag = const Duration(seconds: 60),
    this.pushBatch = 200,
    this.pullBatch = 500,
  });

  final AppDb db;
  final SyncRemote remote;

  /// A change becomes visible to readers only when its transaction commits,
  /// which can be slightly after it got its sequence number. The last-seen
  /// position is therefore only advanced past rows older than [lag]; newer
  /// rows are downloaded again next time, which is harmless.
  final Duration lag;
  final int pushBatch;
  final int pullBatch;

  Future<SyncResult> run({void Function(String message)? onProgress}) async {
    await checkReset();
    final pushed = await push(onProgress: onProgress);
    final pulled = await pull(onProgress: onProgress);
    return SyncResult(pushed, pulled);
  }

  /// Throws [ServerResetException] when the server was wiped since this
  /// database last synced. A new database remembers the current mark.
  Future<void> checkReset() async {
    final rid = await remote.resetId();
    if (rid == null || rid.isEmpty) return;
    final mine = await db.getMeta('server_reset_id');
    if (mine == null || mine.isEmpty) {
      await db.setMeta('server_reset_id', rid);
    } else if (mine != rid) {
      throw ServerResetException(rid);
    }
  }

  Future<int> push({void Function(String message)? onProgress}) async {
    var total = 0;
    for (final t in syncedTables) {
      while (true) {
        final rows = await db.raw.query(t.name, where: 'dirty = 1', limit: pushBatch);
        if (rows.isEmpty) break;
        onProgress?.call('رفع البيانات (${total + rows.length})');
        await remote.upsert(t.name, [for (final r in rows) rowToRemote(t, r)]);
        final batch = db.raw.batch();
        for (final r in rows) {
          // A row edited again while it was being uploaded stays dirty.
          batch.rawUpdate(
            'UPDATE ${t.name} SET dirty = 0 WHERE id = ? AND updated_at IS ?',
            [r['id'], r['updated_at']],
          );
        }
        await batch.commit(noResult: true);
        total += rows.length;
        if (rows.length < pushBatch) break;
      }
    }
    return total;
  }

  Future<int> pull({void Function(String message)? onProgress}) async {
    final safeBefore = (await remote.serverNow()).subtract(lag);
    var total = 0;
    final touched = <String>{};
    for (final t in allTables) {
      final key = 'seq:${t.name}';
      final saved = int.tryParse(await db.getMeta(key) ?? '') ?? 0;
      var after = saved;
      var keep = saved;
      var contiguousSafe = true;
      while (true) {
        final rows = await remote.pull(t.name, after, pullBatch, [db.division, Division.all]);
        if (rows.isEmpty) break;
        final changed = await _apply(t, rows);
        if (changed > 0) touched.add(t.name);
        total += changed;
        for (final r in rows) {
          final seq = (r['sync_seq'] as num).toInt();
          final at = DateTime.tryParse(s(r['server_updated_at']));
          if (contiguousSafe && at != null && !at.isAfter(safeBefore)) {
            keep = seq;
          } else {
            contiguousSafe = false;
          }
          after = seq;
        }
        if (total > 0) onProgress?.call('تحميل البيانات ($total)');
        if (rows.length < pullBatch) break;
      }
      if (keep != saved) await db.setMeta(key, '$keep');
    }
    if (touched.isNotEmpty) db.notify(touched, local: false);
    return total;
  }

  /// Writes server rows locally; returns how many actually changed.
  Future<int> _apply(TableDef t, List<Map<String, dynamic>> rows) async {
    var changed = 0;
    await db.raw.transaction((txn) async {
      for (final r in rows) {
        final cur = await txn.rawQuery(
          'SELECT dirty, updated_at, deleted FROM ${t.name} WHERE id = ?',
          [r['id']],
        );
        if (cur.isNotEmpty) {
          // Local edits that were not uploaded yet win until they are pushed;
          // the server then decides by updated_at.
          if (ni(cur.first['dirty']) == 1) continue;
          final a = DateTime.tryParse(s(cur.first['updated_at']));
          final b = DateTime.tryParse(s(r['updated_at']));
          final sameDeleted = ni(cur.first['deleted']) == (r['deleted'] == true ? 1 : 0);
          if (a != null && b != null && a.isAtSameMomentAs(b) && sameDeleted) continue;
        }
        final local = rowFromRemote(t, r)..['dirty'] = 0;
        await txn.insert(t.name, local, conflictAlgorithm: ConflictAlgorithm.replace);
        changed++;
      }
    });
    return changed;
  }
}
