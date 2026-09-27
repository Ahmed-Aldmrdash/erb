import 'dart:convert';

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../core/db/app_db.dart';
import '../core/db/schema.dart';
import '../core/util/format.dart';

/// A copy of everything this division has, as one text file.
///
/// It is a plain list of the rows of every table, not a copy of the database
/// file: it can be opened on any phone whatever its Android version, and
/// putting it back goes through the normal writing path, so the restored rows
/// are uploaded to the server like any other change.
class Backup {
  static const fileVersion = 1;

  /// Everything of [db] as JSON text.
  static Future<String> create(AppDb db, {String? company}) async {
    final tables = <String, List<DbRow>>{};
    for (final t in allTables) {
      tables[t.name] = await db.q('SELECT * FROM ${t.name}');
    }
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'damardash',
      'version': fileVersion,
      'created_at': nowIso(),
      'division': db.division,
      'company': company ?? '',
      'counts': {for (final e in tables.entries) e.key: e.value.length},
      'tables': tables,
    });
  }

  /// What is inside a backup file, without touching anything.
  static BackupInfo read(String text) {
    final Object? raw = jsonDecode(text);
    if (raw is! Map || raw['app'] != 'damardash' || raw['tables'] is! Map) {
      throw const FormatException('الملف ده مش نسخة احتياطية من الأبلكيشن');
    }
    if (ni(raw['version']) > fileVersion) {
      throw const FormatException('النسخة دي من إصدار أحدث من الأبلكيشن. حدّث الأبلكيشن الأول.');
    }
    final tables = <String, List<DbRow>>{};
    (raw['tables'] as Map).forEach((key, value) {
      if (value is! List) return;
      tables[s(key)] = [
        for (final r in value)
          if (r is Map) {for (final e in r.entries) s(e.key): e.value},
      ];
    });
    return BackupInfo(
      division: s(raw['division']),
      company: s(raw['company']),
      createdAt: s(raw['created_at']),
      tables: tables,
    );
  }

  /// Writes the rows of [info] into [db]. Rows that are already there are
  /// replaced by the ones in the file, rows the file does not know are left
  /// alone, and everything restored is queued for the server.
  ///
  /// The restored rows are stamped with the time of the restore, not the time
  /// they were first written: putting a copy back is itself the newest word,
  /// so it also wins on the other phones and on the server.
  ///
  /// Returns how many rows were written.
  static Future<int> restore(AppDb db, BackupInfo info) async {
    var written = 0;
    final now = nowIso();
    await db.write((w) async {
      for (final t in allTables) {
        final rows = info.tables[t.name];
        if (rows == null) continue;
        for (final row in rows) {
          final id = s(row['id']);
          if (id.isEmpty) continue;
          final values = <String, Object?>{
            for (final c in t.allCols)
              if (row.containsKey(c.name)) c.name: row[c.name],
          };
          values['id'] = id;
          values['division'] = s(row['division']).isEmpty ? db.division : row['division'];
          values['created_at'] = s(row['created_at']).isEmpty ? now : row['created_at'];
          values['updated_at'] = now;
          values['updated_by_name'] = db.person;
          values['deleted'] = ni(row['deleted']) == 1 ? 1 : 0;
          values['dirty'] = 1;
          await w.ex.insert(t.name, values, conflictAlgorithm: ConflictAlgorithm.replace);
          written++;
        }
        w.touched.add(t.name);
      }
    });
    return written;
  }
}

class BackupInfo {
  const BackupInfo({
    required this.division,
    required this.company,
    required this.createdAt,
    required this.tables,
  });

  final String division;
  final String company;
  final String createdAt;
  final Map<String, List<DbRow>> tables;

  int get rows => tables.values.fold(0, (a, b) => a + b.length);

  /// "12 صنف • 40 فاتورة" for the confirmation screen.
  Map<String, int> get highlights => {
        for (final e in {
          'الحسابات': 'parties',
          'الأصناف': 'products',
          'الفواتير': 'invoices',
          'عمليات المحاصيل': 'crop_trades',
          'حركات الفلوس': 'vouchers',
        }.entries)
          if ((tables[e.value]?.length ?? 0) > 0) e.key: tables[e.value]!.length,
      };
}
