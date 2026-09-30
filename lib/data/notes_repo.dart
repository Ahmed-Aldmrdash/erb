import '../core/db/app_db.dart';
import '../core/util/format.dart';

/// Reminders (money left for someone, tasks, notes) shared by everybody in the
/// division, or by both divisions when division = 'all'.
class NotesRepo {
  NotesRepo(this.db);

  final AppDb db;

  /// [kinds] keeps only these kinds, [exceptKinds] leaves them out: the
  /// reminder board and the list of what the shop is out of live in the same
  /// table but are two different screens.
  Future<List<DbRow>> list({
    required bool done,
    String search = '',
    List<String>? kinds,
    List<String>? exceptKinds,
  }) {
    final where = <String>['deleted = 0', 'done = ?'];
    final args = <Object?>[done ? 1 : 0];
    if (kinds != null && kinds.isNotEmpty) {
      where.add('kind IN (${List.filled(kinds.length, '?').join(', ')})');
      args.addAll(kinds);
    }
    if (exceptKinds != null && exceptKinds.isNotEmpty) {
      where.add('kind NOT IN (${List.filled(exceptKinds.length, '?').join(', ')})');
      args.addAll(exceptKinds);
    }
    if (search.trim().isNotEmpty) {
      where.add('(${arFoldSql('body')} LIKE ? OR ${arFoldSql('person')} LIKE ?)');
      final q = '%${arFold(search)}%';
      args.addAll([q, q]);
    }
    final order = done
        ? 'done_at DESC'
        : "pinned DESC, CASE WHEN IFNULL(due_date, '') = '' THEN 1 ELSE 0 END, due_date, created_at DESC";
    return db.q('SELECT * FROM notes WHERE ${where.join(' AND ')} ORDER BY $order LIMIT 300', args);
  }

  Future<int> openCount({List<String>? kinds, List<String>? exceptKinds}) async {
    final where = <String>['deleted = 0', 'done = 0'];
    final args = <Object?>[];
    if (kinds != null && kinds.isNotEmpty) {
      where.add('kind IN (${List.filled(kinds.length, '?').join(', ')})');
      args.addAll(kinds);
    }
    if (exceptKinds != null && exceptKinds.isNotEmpty) {
      where.add('kind NOT IN (${List.filled(exceptKinds.length, '?').join(', ')})');
      args.addAll(exceptKinds);
    }
    return (await db.val('SELECT COUNT(*) FROM notes WHERE ${where.join(' AND ')}', args)).toInt();
  }

  Future<DbRow?> note(String id) => db.byId('notes', id);

  Future<String> save(DbRow values, {String? id}) => db.write((w) async {
        if (id == null) return w.insert('notes', values);
        await w.update('notes', id, values);
        return id;
      });

  Future<void> setDone(String id, bool done) => db.write((w) => w.update('notes', id, {
        'done': done,
        'done_by': done ? db.person : null,
        'done_at': done ? nowIso() : null,
      }));

  Future<void> togglePin(String id, bool pinned) => db.write((w) => w.update('notes', id, {'pinned': pinned}));

  Future<void> delete(String id) => db.write((w) => w.delete('notes', id));
}
