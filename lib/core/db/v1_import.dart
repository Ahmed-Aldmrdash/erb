import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../util/format.dart';
import 'app_db.dart';
import 'schema.dart';

/// The first version kept both businesses in one file (trade_erp.db). When
/// the user chooses to keep it, the old records are copied into the database
/// of their division and marked unsent so they reach the server; otherwise
/// the file is deleted.
class V1Import {
  static const fileName = 'trade_erp.db';

  static Future<String> _path(DatabaseFactory f, String? v1Path) async =>
      v1Path ?? p.join(await f.getDatabasesPath(), fileName);

  /// How many records someone typed in the first version (customers,
  /// weighings, invoices, money...); 0 when there is no old file. The
  /// starter crops, warehouses and cash boxes do not count.
  static Future<int> countOldData({String? v1Path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final path = await _path(f, v1Path);
    if (!await f.databaseExists(path)) return 0;
    final old = await f.openDatabase(path, options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    try {
      final tables = {
        for (final r in await old.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'")) r['name'] as String,
      };
      var count = 0;
      for (final t in const ['parties', 'crop_trades', 'products', 'invoices', 'vouchers', 'stock_moves']) {
        if (!tables.contains(t)) continue;
        final r = await old.rawQuery('SELECT COUNT(*) AS c FROM $t');
        count += (r.first['c'] as int?) ?? 0;
      }
      return count;
    } finally {
      await old.close();
    }
  }

  /// Deletes the first version's file (its data was only a trial).
  static Future<void> deleteOldFile({String? v1Path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final path = await _path(f, v1Path);
    if (await f.databaseExists(path)) await f.deleteDatabase(path);
  }

  /// Returns how many rows were copied.
  static Future<int> run(AppDb db, {String? v1Path, DatabaseFactory? factory}) async {
    if (await db.getMeta('v1_imported') == '1') return 0;
    final f = factory ?? databaseFactory;
    final path = await _path(f, v1Path);
    if (!await f.databaseExists(path)) {
      await db.setMeta('v1_imported', '1');
      return 0;
    }
    final old = await f.openDatabase(path, options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    var count = 0;
    try {
      final tables = {
        for (final r in await old.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'")) r['name'] as String,
      };
      Future<List<Map<String, Object?>>> rows(String t) async => tables.contains(t) ? await old.query(t) : const [];

      final boxes = {for (final b in await rows('cash_boxes')) s(b['id']): _division(b['division'])};
      // Parties were shared by both businesses: each goes where it was used
      // most (+1 trade, -1 showroom), else by its kind.
      final votes = <String, int>{};
      void vote(Object? id, int v) {
        if (id != null) votes[s(id)] = (votes[s(id)] ?? 0) + v;
      }

      for (final t in await rows('crop_trades')) {
        vote(t['party_id'], 1);
      }
      for (final i in await rows('invoices')) {
        vote(i['party_id'], -1);
      }
      for (final v in await rows('vouchers')) {
        vote(v['party_id'], _voucherDivision(v, boxes) == Division.crops ? 1 : -1);
      }
      String partyDivision(Map<String, Object?> r) {
        final v = votes[s(r['id'])] ?? 0;
        if (v != 0) return v > 0 ? Division.crops : Division.appliances;
        return r['kind'] == 'farmer' || r['kind'] == 'trader' ? Division.crops : Division.appliances;
      }

      String? divisionOf(String table, Map<String, Object?> r) => switch (table) {
            'crops' || 'crop_trades' => Division.crops,
            'products' || 'invoices' || 'invoice_lines' || 'installments' => Division.appliances,
            'warehouses' || 'cash_boxes' => _division(r['division']),
            'vouchers' => _voucherDivision(r, boxes),
            'stock_moves' => r['item_type'] == 'crop' ? Division.crops : Division.appliances,
            'parties' => partyDivision(r),
            // Settings are kept per division now; the old ones are not copied.
            _ => null,
          };

      await db.raw.transaction((txn) async {
        for (final t in syncedTables) {
          final cols = {for (final c in t.allCols) c.name};
          for (final r in await rows(t.name)) {
            if (divisionOf(t.name, r) != db.division) continue;
            final values = <String, Object?>{
              for (final e in r.entries)
                if (cols.contains(e.key) && e.value != null) e.key: e.value,
            };
            values['division'] = db.division;
            values['dirty'] = 1;
            await txn.insert(t.name, values, conflictAlgorithm: ConflictAlgorithm.replace);
            count++;
          }
        }
      });
    } finally {
      await old.close();
    }
    await db.setMeta('v1_imported', '1');
    if (count > 0) db.notify(syncedTables.map((t) => t.name).toSet(), local: false);
    return count;
  }

  static String _division(Object? d) => d == Division.crops ? Division.crops : Division.appliances;

  static String _voucherDivision(Map<String, Object?> v, Map<String, String> boxes) {
    final d = v['division'];
    if (d == Division.crops || d == Division.appliances) return d as String;
    return boxes[s(v['cash_box_id'])] ?? Division.appliances;
  }
}
