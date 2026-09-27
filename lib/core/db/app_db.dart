import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../util/format.dart';
import '../util/uuid.dart';
import 'local_sql.dart';
import 'schema.dart';

typedef DbRow = Map<String, Object?>;

/// Local SQLite database of one division (المعرض or التجارة). Every screen
/// reads from here, so the app works the same with or without internet; the
/// sync engine moves rows to and from the server in the background.
///
/// Each division has its own file, so the two businesses never mix.
class AppDb {
  AppDb._(this.raw, this.division);

  final Database raw;

  /// crops | appliances: written into every new row.
  final String division;

  /// Name of whoever is using the phone; saved on every row they write.
  String person = '';

  /// Prefix of document numbers created on this phone, e.g. "3" gives "3-17".
  /// Empty until the phone is registered on the server (plain numbers).
  String deviceCode = '';

  /// Called after every change made by the user (not by sync).
  void Function()? onLocalWrite;

  final _changes = StreamController<Set<String>>.broadcast();

  /// Emits the names of tables that changed, from local writes and from sync.
  Stream<Set<String>> get changes => _changes.stream;

  static Future<AppDb> open({required String division, String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'erp_$division.db');
    final db = await f.openDatabase(dbPath, options: OpenDatabaseOptions(version: 1));
    final appDb = AppDb._(db, division);
    await appDb._migrate();
    return appDb;
  }

  /// Deletes a division database file (signing in to another department).
  static Future<void> deleteFile(String division, {DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final path = p.join(await f.getDatabasesPath(), 'erp_$division.db');
    await f.deleteDatabase(path);
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  Future<void> close() async {
    await _changes.close();
    await raw.close();
  }

  /// Creates missing tables and columns; recreates views.
  Future<void> _migrate() async {
    await raw.execute('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY NOT NULL, value TEXT)');
    for (final t in allTables) {
      await raw.execute(createLocalTableSql(t));
      final info = await raw.rawQuery('PRAGMA table_info(${t.name})');
      final existing = info.map((r) => r['name'] as String).toSet();
      for (final c in t.allCols) {
        if (!existing.contains(c.name)) {
          await raw.execute('ALTER TABLE ${t.name} ADD COLUMN ${localColumnSql(c)}');
        }
      }
      await raw.execute('CREATE INDEX IF NOT EXISTS ix_${t.name}_dirty ON ${t.name}(dirty)');
    }
    for (final sql in localIndexSql) {
      await raw.execute(sql);
    }
    for (final name in localViews.keys.toList().reversed) {
      await raw.execute('DROP VIEW IF EXISTS $name');
    }
    for (final e in localViews.entries) {
      await raw.execute('CREATE VIEW ${e.key} AS ${e.value}');
    }
  }

  void notify(Set<String> tables, {bool local = true}) {
    if (tables.isEmpty || _changes.isClosed) return;
    _changes.add(tables);
    if (local) onLocalWrite?.call();
  }

  // ---------------------------------------------------------------- reads

  Future<List<DbRow>> q(String sql, [List<Object?> args = const []]) => raw.rawQuery(sql, args);

  Future<DbRow?> q1(String sql, [List<Object?> args = const []]) async {
    final r = await raw.rawQuery(sql, args);
    return r.isEmpty ? null : r.first;
  }

  Future<double> val(String sql, [List<Object?> args = const []]) async {
    final r = await raw.rawQuery(sql, args);
    if (r.isEmpty || r.first.isEmpty) return 0;
    return n(r.first.values.first);
  }

  Future<DbRow?> byId(String table, String? id) async {
    if (id == null || id.isEmpty) return null;
    return q1('SELECT * FROM $table WHERE id = ?', [id]);
  }

  // ---------------------------------------------------------------- meta

  Future<String?> getMeta(String key, {DatabaseExecutor? ex}) async {
    final r = await (ex ?? raw).rawQuery('SELECT value FROM meta WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setMeta(String key, String? value, {DatabaseExecutor? ex}) async {
    final e = ex ?? raw;
    if (value == null) {
      await e.rawDelete('DELETE FROM meta WHERE key = ?', [key]);
    } else {
      await e.rawInsert('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)', [key, value]);
    }
  }

  /// When a phone that was used without a server gets its code, its plain
  /// document numbers get the prefix: 5 becomes 3-5. They were never
  /// uploaded, so no other phone has seen the old numbers.
  Future<void> prefixLocalNumbers(String code) async {
    final now = nowIso();
    for (final t in const ['crop_trades', 'invoices', 'vouchers', 'stock_moves']) {
      await raw.rawUpdate(
        "UPDATE $t SET number = ? || '-' || number, dirty = 1, updated_at = ? "
        "WHERE IFNULL(number, '') <> '' AND number NOT LIKE '%-%'",
        [code, now],
      );
    }
    await raw.rawDelete("DELETE FROM meta WHERE key LIKE 'num:%'");
  }

  Future<int> pendingCount() async {
    var total = 0;
    for (final t in syncedTables) {
      total += (await val('SELECT COUNT(*) FROM ${t.name} WHERE dirty = 1')).toInt();
    }
    return total;
  }

  // ---------------------------------------------------------------- writes

  /// Runs [action] in one transaction and notifies listeners afterwards.
  Future<T> write<T>(Future<T> Function(Writer w) action) async {
    late Set<String> touched;
    final result = await raw.transaction((txn) async {
      final w = Writer._(txn, this);
      final r = await action(w);
      touched = w.touched;
      return r;
    });
    notify(touched);
    return result;
  }
}

/// All user edits go through a Writer so that every row carries the fields
/// the sync engine relies on (updated_at, dirty, created_by).
class Writer {
  Writer._(this.ex, this._db);

  final Transaction ex;
  final AppDb _db;
  final Set<String> touched = {};

  Future<String> insert(String table, DbRow values) async {
    final t = tableByName[table]!;
    final now = nowIso();
    final row = <String, Object?>{
      for (final c in t.allCols) c.name: toLocalValue(c, values[c.name]),
    };
    row['id'] = values['id'] ?? newId();
    row['division'] = values['division'] ?? _db.division;
    row['created_at'] = values['created_at'] ?? now;
    row['updated_at'] = now;
    row['deleted'] = 0;
    row['created_by_name'] = values['created_by_name'] ?? _db.person;
    row['updated_by_name'] = _db.person;
    row['dirty'] = 1;
    await ex.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    touched.add(table);
    return row['id'] as String;
  }

  /// Inserts only when no row with this id exists (seed data with fixed ids).
  Future<bool> insertIfAbsent(String table, DbRow values) async {
    final found = await ex.rawQuery('SELECT 1 FROM $table WHERE id = ?', [values['id']]);
    if (found.isNotEmpty) return false;
    await insert(table, values);
    return true;
  }

  Future<void> update(String table, String id, DbRow values) async {
    final t = tableByName[table]!;
    final cur = await ex.rawQuery('SELECT updated_at FROM $table WHERE id = ?', [id]);
    // Never go back in time: the server keeps the version with the newest
    // updated_at, so an edit must always look newer than what it replaces,
    // even if this phone's clock is behind.
    var ts = DateTime.now().toUtc();
    if (cur.isNotEmpty) {
      final prev = DateTime.tryParse(s(cur.first['updated_at']));
      if (prev != null && !ts.isAfter(prev)) ts = prev.toUtc().add(const Duration(milliseconds: 1));
    }
    final row = <String, Object?>{};
    values.forEach((k, v) {
      final c = t.col(k);
      if (c != null && k != 'id') row[k] = toLocalValue(c, v);
    });
    row['updated_at'] = ts.toIso8601String();
    row['updated_by_name'] = _db.person;
    row['dirty'] = 1;
    await ex.update(table, row, where: 'id = ?', whereArgs: [id]);
    touched.add(table);
  }

  Future<void> delete(String table, String id) => update(table, id, {'deleted': true});

  Future<void> deleteWhere(String table, String where, List<Object?> args) async {
    final rows = await ex.rawQuery('SELECT id FROM $table WHERE deleted = 0 AND ($where)', args);
    for (final r in rows) {
      await delete(table, r['id'] as String);
    }
  }

  /// Next document number for this phone: "3-18" once the phone has a
  /// server code, a plain "18" before that.
  Future<String> nextNumber(String table, String kind) async {
    final code = _db.deviceCode;
    final prefix = code.isEmpty ? '' : '$code-';
    final key = 'num:$table:$kind:$code';
    final stored = int.tryParse(await _db.getMeta(key, ex: ex) ?? '');
    var last = stored ?? 0;
    if (stored == null) {
      // First number on this phone (or after reinstall): continue after the
      // highest number already synced for this device code.
      final rows = await ex.rawQuery(
        code.isEmpty
            ? "SELECT number FROM $table WHERE kind = ? AND number NOT LIKE '%-%'"
            : 'SELECT number FROM $table WHERE kind = ? AND number LIKE ?',
        [kind, if (code.isNotEmpty) '$prefix%'],
      );
      for (final r in rows) {
        final v = int.tryParse(s(r['number']).substring(prefix.length)) ?? 0;
        if (v > last) last = v;
      }
    }
    final next = last + 1;
    await _db.setMeta(key, '$next', ex: ex);
    return '$prefix$next';
  }
}
