import 'package:supabase/supabase.dart';

import 'resilient_http.dart';

/// Talks to the company server. Department logins are checked by database
/// functions (see supabase/schema.sql); the session token then travels in the
/// x-erp-session header of every request and the row level security of each
/// table only lets it see its own division.
class ServerApi {
  ServerApi(this.url, this.key, {String? token}) : client = SupabaseClient(url, key, httpClient: ResilientHttp.create()) {
    setToken(token);
  }

  final String url;
  final String key;
  final SupabaseClient client;

  void setToken(String? token) {
    client.headers = {if (token != null && token.isNotEmpty) 'x-erp-session': token};
  }

  Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  Future<bool> setupNeeded() async => await client.rpc('erp_setup_needed') == true;

  Future<Map<String, dynamic>> setup({
    required String cropsUser,
    required String cropsPass,
    required String appliancesUser,
    required String appliancesPass,
    String? ownerUser,
    String? ownerPass,
  }) async =>
      _map(await client.rpc('erp_setup', params: {
        'p_crops_user': cropsUser,
        'p_crops_pass': cropsPass,
        'p_app_user': appliancesUser,
        'p_app_pass': appliancesPass,
        'p_owner_user': ownerUser,
        'p_owner_pass': ownerPass,
      }));

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    required String deviceId,
    required String deviceName,
    required String person,
  }) async =>
      _map(await client.rpc('erp_login', params: {
        'p_username': username,
        'p_password': password,
        'p_device': deviceId,
        'p_device_name': deviceName,
        'p_person': person,
      }));

  /// Null when the session ended (logout, password changed).
  Future<Map<String, dynamic>?> sessionInfo() async {
    final r = await client.rpc('erp_session_info');
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Future<void> logout() => client.rpc('erp_logout');

  Future<List<Map<String, dynamic>>> departments() async {
    final r = await client.rpc('erp_departments');
    return r is List ? [for (final x in r) Map<String, dynamic>.from(x as Map)] : const [];
  }

  /// Only the owner account may manage users.
  Future<Map<String, dynamic>> addUser({
    required String username,
    required String password,
    required String name,
    required String division,
    required String permissions,
  }) async =>
      _map(await client.rpc('erp_add_user', params: {
        'p_username': username,
        'p_password': password,
        'p_name': name,
        'p_division': division,
        'p_permissions': permissions,
      }));

  Future<Map<String, dynamic>> updateUser({
    required String id,
    String? name,
    String? division,
    String? permissions,
    bool? active,
  }) async =>
      _map(await client.rpc('erp_update_user', params: {
        'p_id': id,
        'p_name': name,
        'p_division': division,
        'p_permissions': permissions,
        'p_active': active,
      }));

  Future<Map<String, dynamic>> deleteUser(String id) async =>
      _map(await client.rpc('erp_delete_user', params: {'p_id': id}));

  Future<Map<String, dynamic>> changePassword({
    required String department,
    String? oldPassword,
    required String newPassword,
    String? newUsername,
  }) async =>
      _map(await client.rpc('erp_change_password', params: {
        'p_department': department,
        'p_old': oldPassword,
        'p_new': newPassword,
        'p_new_username': newUsername,
      }));

  Future<void> dispose() => client.dispose();
}

/// Arabic text for the error codes returned by the server functions.
String serverErrorText(Map<String, dynamic> r) {
  switch (r['error']) {
    case 'invalid':
      return 'اسم المستخدم أو كلمة المرور غلط';
    case 'locked':
      final minutes = ((r['seconds'] as num? ?? 60) / 60).ceil();
      return 'محاولات غلط كتير. استنى $minutes دقيقة وحاول تاني';
    case 'configured':
      return 'الحسابات متظبطة قبل كده. سجل دخول.';
    case 'duplicate':
      return 'اسم المستخدم ده مستخدم في قسم تاني';
    case 'username':
      return 'اكتب اسم مستخدم لكل قسم';
    case 'short':
      return 'كلمة المرور لازم تكون 6 حروف أو أرقام على الأقل';
    case 'old_password':
      return 'كلمة المرور القديمة غلط';
    case 'forbidden':
      return 'مش مسموح تغير بيانات القسم ده';
    case 'session':
      return 'انتهت الجلسة، سجل دخول تاني';
    case 'disabled':
      return 'الحساب ده موقوف. كلم صاحب المحل.';
    case 'last_owner':
      return 'لازم يفضل حساب واحد على الأقل شايف القسمين وبكل الصلاحيات';
    case 'self':
      return 'مينفعش تحذف الحساب اللي انت داخل بيه';
    case 'missing':
      return 'اكتب اسم المستخدم والاسم';
    case 'department':
      return 'الحساب ده مش موجود';
    case 'division':
      return 'اختار القسم';
  }
  return 'حصلت مشكلة: ${r['error'] ?? 'غير معروفة'}';
}
