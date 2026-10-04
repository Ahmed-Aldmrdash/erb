import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/accounts_repo.dart';
import '../data/activity_repo.dart';
import '../data/appliances_repo.dart';
import '../data/crops_repo.dart';
import '../data/notes_repo.dart';
import '../data/permissions.dart';
import '../data/reports_repo.dart';
import 'config.dart';
import 'label_queue.dart';
import 'db/app_db.dart';
import 'db/prefs.dart';
import 'db/schema.dart';
import 'db/v1_import.dart';
import 'seed.dart';
import 'sync/server_api.dart';
import 'sync/sync_engine.dart';
import 'sync/sync_service.dart';
import 'util/format.dart';
import 'util/uuid.dart';

/// The one app-wide object: settings of this phone, the open division
/// database with its repositories, the session and the sync.
late AppState app;

enum Gate { loading, setupServer, setupAccounts, login, pickDivision, syncing, ready }

class AppState extends ChangeNotifier {
  late Prefs prefs;
  AppDb? _db;

  late AccountsRepo accounts;
  late CropsRepo crops;
  late AppliancesRepo appliances;
  late ReportsRepo reports;
  late NotesRepo notes;
  late ActivityRepo activity;

  Gate gate = Gate.loading;
  String? startupError;

  /// Progress / error text shown by the gate screens.
  String gateMessage = '';
  Map<String, String> settings = {};
  ServerApi? server;
  SyncService? sync;
  StreamSubscription<Set<String>>? _dbSub;

  /// Records typed in the first version of the app that wait for the user's
  /// choice: keep them (importOldVersion) or delete them (discardOldVersion).
  int oldVersionRecords = 0;

  /// One-off message for the home screen (e.g. after the server was wiped).
  String? _notice;

  String? takeNotice() {
    final n = _notice;
    _notice = null;
    return n;
  }

  AppDb get db => _db!;
  bool get hasDb => _db != null;

  /// '' (not chosen yet) | local | cloud
  String get mode => prefs.get('mode');
  bool get isCloud => mode == 'cloud';

  /// crops | appliances | all (manager). Local mode behaves like a manager.
  String get sessionDivision => isCloud ? prefs.get('session_division') : Division.all;
  bool get isManager => sessionDivision == Division.all;
  String get departmentName => isCloud ? prefs.get('session_name') : 'بدون سيرفر';

  /// What this login may open. Empty means no limits (the accounts of the
  /// business itself, and every phone working without a server).
  Set<String> get permissions => isCloud ? Perm.parse(prefs.get('session_perms')) : const {};

  /// Whether this login may open a section (see [Perm]).
  bool can(String section) => permissions.isEmpty || permissions.contains(section);

  /// The division whose data is open now.
  String get division => _db?.division ?? prefs.get('division', Division.appliances);
  String get divisionName => Division.names[division] ?? '';
  bool get isCrops => division == Division.crops;

  /// Whoever is using the phone now (typed at login).
  String get person => prefs.get('person');
  List<String> get recentPersons {
    try {
      return List<String>.from(jsonDecode(prefs.get('recent_persons', '[]')) as List);
    } catch (_) {
      return const [];
    }
  }

  String get deviceId => prefs.get('device_id');
  String get companyName {
    final n = settings['company_name']?.trim() ?? '';
    return n.isEmpty ? defaultCompanyName : n;
  }

  /// Selling prices are rounded up to this (المزيد ← بيانات المؤسسة), so a
  /// price never comes out as 4,523.40.
  double get priceStep {
    final v = double.tryParse(settings['price_round'] ?? '') ?? 10;
    return v <= 0 ? 1 : v;
  }

  /// The margin a new product starts with, in percent.
  double get defaultProfitPct => double.tryParse(settings['default_profit_pct'] ?? '') ?? 0;

  Future<void> init() async {
    try {
      prefs = await Prefs.open();
      if (!prefs.has('device_id')) await prefs.set('device_id', newId());
      if (mode.isEmpty && Env.hasSupabase) {
        await prefs.set('server_url', Env.supabaseUrl);
        await prefs.set('server_key', Env.supabaseAnonKey);
        await prefs.set('mode', 'cloud');
      }
      switch (mode) {
        case 'local':
          final d = prefs.get('division');
          if (d.isEmpty) {
            _setGate(Gate.pickDivision);
          } else {
            await openDivision(d);
          }
        case 'cloud':
          await _startCloud();
        default:
          _setGate(Gate.setupServer);
      }
    } catch (e, st) {
      debugPrint('startup failed: $e\n$st');
      startupError = '$e';
      notifyListeners();
    }
  }

  void _setGate(Gate g) {
    gate = g;
    notifyListeners();
  }

  // ---------------------------------------------------------------- server

  Future<void> _startCloud() async {
    final url = prefs.get('server_url');
    final key = prefs.get('server_key');
    if (url.isEmpty || key.isEmpty) {
      _setGate(Gate.setupServer);
      return;
    }
    server ??= ServerApi(url, key, token: prefs.get('session_token'));
    if (!prefs.has('session_token')) {
      await _toLoginOrSetup();
      return;
    }
    // Signed in before: open right away (works offline) and check the
    // session in the background.
    final div = isManager ? prefs.get('division') : sessionDivision;
    if (div.isEmpty) {
      _setGate(Gate.pickDivision);
    } else {
      await openDivision(div);
    }
    unawaited(checkSession());
  }

  Future<void> _toLoginOrSetup() async {
    gateMessage = '';
    try {
      if (await server!.setupNeeded()) {
        _setGate(Gate.setupAccounts);
        return;
      }
    } catch (e) {
      gateMessage = _serverProblem(e);
    }
    _setGate(Gate.login);
  }

  /// Saves the server address after checking that it answers.
  Future<String?> connectServer(String url, String key) async {
    url = url.trim();
    key = key.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return 'رابط السيرفر غير صحيح';
    if (key.length < 20) return 'الـ key غير صحيح';
    if (key.startsWith('sb_secret_')) return 'ده الـ secret key! استخدم الـ Publishable key بس.';
    final api = ServerApi(url, key);
    try {
      await api.setupNeeded();
    } catch (e) {
      await api.dispose();
      return isOfflineError(e)
          ? 'الموبايل مش قادر يوصل للسيرفر. اتأكد إن النت شغال على الموبايل وجرب تاني.'
          : 'السيرفر مش بيرد صح. اتأكد من الرابط والـ key وإن ملف schema.sql الجديد اتنفذ.';
    }
    await server?.dispose();
    server = api;
    await prefs.set('server_url', url);
    await prefs.set('server_key', key);
    await prefs.set('mode', 'cloud');
    await _toLoginOrSetup();
    return null;
  }

  /// First start: usernames and passwords of the departments.
  Future<String?> setupAccounts({
    required String cropsUser,
    required String cropsPass,
    required String appliancesUser,
    required String appliancesPass,
    String? ownerUser,
    String? ownerPass,
  }) async {
    try {
      final r = await server!.setup(
        cropsUser: cropsUser.trim(),
        cropsPass: cropsPass,
        appliancesUser: appliancesUser.trim(),
        appliancesPass: appliancesPass,
        ownerUser: (ownerUser ?? '').trim().isEmpty ? null : ownerUser!.trim(),
        ownerPass: (ownerUser ?? '').trim().isEmpty ? null : ownerPass,
      );
      if (r['error'] != null) return serverErrorText(r);
    } catch (e) {
      return _serverProblem(e);
    }
    gateMessage = 'تم إنشاء الحسابات. سجل دخول باسم مستخدم القسم.';
    _setGate(Gate.login);
    return null;
  }

  Future<String?> login(String username, String password, String person) async {
    final name = person.trim();
    if (name.isEmpty) return 'اكتب اسمك';
    final Map<String, dynamic> r;
    try {
      r = await server!.login(
        username: username.trim(),
        password: password,
        deviceId: deviceId,
        deviceName: _deviceName(),
        person: name,
      );
    } catch (e) {
      return _serverProblem(e);
    }
    if (r['error'] != null) return serverErrorText(r);
    final token = s(r['token']);
    final div = s(r['division']);
    await prefs.set('session_token', token);
    await prefs.set('session_division', div);
    await prefs.set('session_name', s(r['display_name']));
    await prefs.set('session_perms', s(r['permissions']));
    await prefs.set('username', username.trim());
    if (r['device_code'] != null) await prefs.set('device_code', '${r['device_code']}');
    await setPerson(name);
    server!.setToken(token);
    // A department phone keeps only its own data.
    if (div != Division.all) await _forgetOtherDivision(div);
    gateMessage = '';
    final open = div == Division.all ? prefs.get('division') : div;
    if (open.isEmpty) {
      _setGate(Gate.pickDivision);
    } else {
      await openDivision(open);
    }
    return null;
  }

  Future<void> checkSession() async {
    if (!isCloud || server == null || !prefs.has('session_token')) return;
    try {
      if (await server!.sessionInfo() == null) await _sessionEnded();
    } catch (_) {
      // Offline: keep working, the next check decides.
    }
  }

  Future<void> _sessionEnded() async {
    _setGate(Gate.loading);
    await _closeDivision();
    await prefs.set('session_token', null);
    server?.setToken(null);
    gateMessage = 'انتهت الجلسة (ممكن كلمة المرور اتغيرت). سجل دخول تاني.';
    _setGate(Gate.login);
  }

  Future<void> _forgetOtherDivision(String keep) async {
    final other = keep == Division.crops ? Division.appliances : Division.crops;
    try {
      final odb = await AppDb.open(division: other);
      final pending = await odb.pendingCount();
      await odb.close();
      if (pending == 0) await AppDb.deleteFile(other);
    } catch (e) {
      debugPrint('could not clean $other: $e');
    }
  }

  Future<void> logout() async {
    if (isCloud) {
      try {
        await sync?.syncNow();
        await server?.logout();
      } catch (_) {
        // Offline: the session simply stays until the password changes.
      }
    }
    _setGate(Gate.loading);
    await _closeDivision();
    if (isCloud) {
      await prefs.set('session_token', null);
      await prefs.set('session_division', null);
      await prefs.set('session_name', null);
      await prefs.set('session_perms', null);
      server?.setToken(null);
      await _toLoginOrSetup();
    } else {
      await prefs.set('division', null);
      _setGate(Gate.pickDivision);
    }
  }

  Future<String?> changePassword({
    required String department,
    String? oldPassword,
    required String newPassword,
    String? newUsername,
  }) async {
    try {
      final r = await server!.changePassword(
        department: department,
        oldPassword: oldPassword,
        newPassword: newPassword,
        newUsername: newUsername,
      );
      if (r['error'] != null) return serverErrorText(r);
      if ((newUsername ?? '').trim().isNotEmpty && department == prefs.get('session_division')) {
        await prefs.set('username', newUsername!.trim());
      }
      return null;
    } catch (e) {
      return isOfflineError(e) ? 'محتاج إنترنت علشان تغير كلمة المرور' : 'تعذر الحفظ: ${_short(e)}';
    }
  }

  /// Use the app on this phone only (trial). Behaves like a manager.
  Future<void> useLocalMode(String division) async {
    await prefs.set('mode', 'local');
    if (person.isEmpty) await setPerson('المدير');
    await openDivision(division);
  }

  Future<void> changeServer() async {
    _setGate(Gate.loading);
    await _closeDivision();
    await prefs.set('mode', null);
    await prefs.set('session_token', null);
    await server?.dispose();
    server = null;
    _setGate(Gate.setupServer);
  }

  // ---------------------------------------------------------------- divisions

  Future<void> switchDivision(String division) async {
    if (division == this.division && hasDb) return;
    _setGate(Gate.loading);
    await openDivision(division);
  }

  Future<void> retryOpen() => openDivision(division);

  Future<void> openDivision(String div) async {
    await _closeDivision();
    // The sticker queue belongs to the division that was open.
    LabelQueue.reset();
    final d = await AppDb.open(division: div);
    d.person = person;
    d.deviceCode = prefs.get('device_code');
    _db = d;
    accounts = AccountsRepo(d);
    crops = CropsRepo(d);
    appliances = AppliancesRepo(d);
    reports = ReportsRepo(d, crops, appliances);
    notes = NotesRepo(d);
    activity = ActivityRepo(d);
    await prefs.set('division', div);
    _dbSub = d.changes.listen(_onDbChange);
    // Plain numbers made before this phone had a server code get its prefix.
    if (d.deviceCode.isNotEmpty && await d.getMeta('numbers_prefixed') != '1') {
      await d.prefixLocalNumbers(d.deviceCode);
      await d.setMeta('numbers_prefixed', '1');
    }
    // The first version kept both businesses in one file: its records come
    // over only when the user chose to keep them.
    final oldChoice = prefs.get('v1_decision');
    try {
      if (oldChoice == 'import') {
        await V1Import.run(d);
      } else if (oldChoice.isEmpty) {
        oldVersionRecords = await V1Import.countOldData();
        if (oldVersionRecords == 0) await prefs.set('v1_decision', 'none');
      }
    } catch (e) {
      debugPrint('old version file: $e');
    }
    if (!isCloud) {
      await seedDefaults(d);
      await _loadSettings();
      _setGate(Gate.ready);
      return;
    }
    final s = SyncService(
      d,
      server!.client,
      onSessionLost: () => unawaited(checkSession()),
      onServerReset: (_) => unawaited(_serverWasReset()),
    );
    sync = s;
    if (await d.getMeta('initial_sync_done') != '1') {
      gateMessage = 'جاري تحميل بيانات ${Division.names[div]}...';
      _setGate(Gate.syncing);
      try {
        await s.engine.run(onProgress: (m) {
          gateMessage = m;
          notifyListeners();
        });
        await d.setMeta('initial_sync_done', '1');
      } on ServerResetException {
        // Left over from before the server was wiped: start clean.
        await _closeDivision();
        await _deleteLocalFiles();
        return openDivision(div);
      } catch (e) {
        gateMessage = 'فشل تحميل البيانات: ${isOfflineError(e) ? 'مفيش إنترنت' : _short(e)}';
        notifyListeners();
        return;
      }
    }
    await seedDefaults(d);
    await _loadSettings();
    _setGate(Gate.ready);
    s.start();
  }

  Future<void> _closeDivision() async {
    final s = sync;
    sync = null;
    await s?.stop();
    await _dbSub?.cancel();
    _dbSub = null;
    final d = _db;
    _db = null;
    await d?.close();
  }

  // ---------------------------------------------------------------- wiping

  /// Deletes what this phone keeps of both divisions and of the first
  /// version. The server is not touched.
  Future<void> _deleteLocalFiles() async {
    for (final d in [Division.crops, Division.appliances]) {
      await AppDb.deleteFile(d);
    }
    await V1Import.deleteOldFile();
    oldVersionRecords = 0;
    await prefs.set('v1_decision', 'discard');
  }

  bool _wiping = false;

  /// The server data was wiped (supabase/reset_data.sql): drop the old copy
  /// instead of uploading it again, and download the clean server.
  Future<void> _serverWasReset() async {
    if (_wiping || !hasDb) return;
    _wiping = true;
    try {
      final div = division;
      _setGate(Gate.loading);
      await _closeDivision();
      await _deleteLocalFiles();
      _notice = 'بيانات السيرفر اتمسحت، فاتمسحت البيانات القديمة من الموبايل ده كمان.';
      await openDivision(div);
    } finally {
      _wiping = false;
    }
  }

  /// "مسح كل البيانات من الموبايل ده": both divisions and the first version's
  /// file. When signed in to the server, what the server has comes back down.
  Future<void> wipeThisPhone() async {
    final div = division;
    _setGate(Gate.loading);
    await _closeDivision();
    await _deleteLocalFiles();
    _notice = 'اتمسحت كل البيانات من الموبايل ده.';
    if (isCloud && prefs.has('session_token')) {
      await openDivision(isManager ? div : sessionDivision);
    } else if (isCloud) {
      await _toLoginOrSetup();
    } else {
      await prefs.set('division', null);
      _setGate(Gate.pickDivision);
    }
  }

  /// Keep the first version's records: they are copied into this division
  /// now, and into the other one when it opens.
  Future<int> importOldVersion() async {
    await prefs.set('v1_decision', 'import');
    oldVersionRecords = 0;
    final n = await V1Import.run(db);
    notifyListeners();
    return n;
  }

  /// The first version held only trials: delete its file.
  Future<void> discardOldVersion() async {
    await V1Import.deleteOldFile();
    await prefs.set('v1_decision', 'discard');
    oldVersionRecords = 0;
    notifyListeners();
  }

  // ---------------------------------------------------------------- person

  Future<void> setPerson(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    await prefs.set('person', n);
    final list = [n, ...recentPersons.where((x) => x != n)].take(8).toList();
    await prefs.set('recent_persons', jsonEncode(list));
    _db?.person = n;
    notifyListeners();
  }

  // ---------------------------------------------------------------- settings

  Future<void> _loadSettings() async {
    settings = await accounts.settings();
  }

  /// After a restore, so the screens read the settings that came back.
  Future<void> reloadSettings() async {
    await _loadSettings();
    notifyListeners();
  }

  Future<void> _onDbChange(Set<String> tables) async {
    if (tables.contains('app_settings') && hasDb) {
      await _loadSettings();
      notifyListeners();
    }
  }

  String _deviceName() {
    try {
      return '${Platform.operatingSystem} ${Platform.localHostname}';
    } catch (_) {
      return Platform.operatingSystem;
    }
  }

  /// What went wrong talking to the server, in words the family can act on.
  String _serverProblem(Object e) {
    if (isOfflineError(e)) return 'الموبايل مش قادر يوصل للسيرفر. اتأكد إن النت شغال على الموبايل وجرب تاني.';
    final t = e.toString();
    if (t.contains('PGRST202') || t.contains('Could not find the function')) {
      return 'السيرفر لسه عليه النسخة القديمة من قاعدة البيانات. افتح Supabase ← SQL Editor ونفّذ ملف supabase/schema.sql الجديد، وبعدين افتح الأبلكيشن تاني.';
    }
    return 'تعذر الاتصال بالسيرفر: ${_short(e)}';
  }

  String _short(Object e) {
    final t = e.toString();
    return t.length > 160 ? '${t.substring(0, 160)}…' : t;
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    super.dispose();
  }
}
