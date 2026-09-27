import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// App-level settings of this phone (server, session, current person...),
/// kept apart from the per-division business databases.
class Prefs {
  Prefs._(this._db, this._cache);

  final Database _db;
  final Map<String, String> _cache;

  static Future<Prefs> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'erp_prefs.db');
    final db = await f.openDatabase(dbPath, options: OpenDatabaseOptions(version: 1));
    await db.execute('CREATE TABLE IF NOT EXISTS prefs (key TEXT PRIMARY KEY NOT NULL, value TEXT)');
    final rows = await db.rawQuery('SELECT key, value FROM prefs');
    return Prefs._(db, {for (final r in rows) r['key'] as String: (r['value'] as String?) ?? ''});
  }

  String get(String key, [String fallback = '']) => _cache[key] ?? fallback;

  bool has(String key) => (_cache[key] ?? '').isNotEmpty;

  Future<void> set(String key, String? value) async {
    if (value == null || value.isEmpty) {
      _cache.remove(key);
      await _db.rawDelete('DELETE FROM prefs WHERE key = ?', [key]);
    } else {
      _cache[key] = value;
      await _db.rawInsert('INSERT OR REPLACE INTO prefs (key, value) VALUES (?, ?)', [key, value]);
    }
  }

  Future<void> close() => _db.close();
}
