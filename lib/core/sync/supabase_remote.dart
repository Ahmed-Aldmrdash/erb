import 'package:supabase/supabase.dart';

import 'sync_engine.dart';

class SupabaseRemote implements SyncRemote {
  SupabaseRemote(this.client);

  final SupabaseClient client;

  @override
  Future<DateTime> serverNow() async {
    final r = await client.rpc('server_now');
    return DateTime.parse(r as String);
  }

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows) async {
    await client.from(table).upsert(rows, onConflict: 'id');
  }

  @override
  Future<List<Map<String, dynamic>>> pull(String table, int afterSeq, int limit, List<String> divisions) async {
    final data = await client
        .from(table)
        .select()
        .inFilter('division', divisions)
        .gt('sync_seq', afterSeq)
        .order('sync_seq', ascending: true)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data);
  }

  @override
  Future<String?> resetId() async {
    try {
      final r = await client.rpc('erp_reset_id');
      return r == null ? null : '$r';
    } on PostgrestException catch (e) {
      // A server without the reset mark (older schema.sql).
      if (e.code == 'PGRST202') return null;
      rethrow;
    }
  }
}
