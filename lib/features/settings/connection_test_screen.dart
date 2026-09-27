import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/sync/resilient_http.dart';
import '../../core/sync/server_api.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class _Check {
  _Check(this.title, this.ok, this.detail);

  final String title;
  final bool ok;
  final String detail;
}

/// اختبار الاتصال: finds out why the phone cannot reach the server (no
/// internet for the app, the name lookup, the server itself, or the new
/// database file not run yet) and says what to do.
class ConnectionTestScreen extends StatefulWidget {
  const ConnectionTestScreen({super.key, this.url, this.apiKey});

  /// Server to test; the saved one when empty.
  final String? url;
  final String? apiKey;

  @override
  State<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

class _ConnectionTestScreenState extends State<ConnectionTestScreen> {
  final List<_Check> _checks = [];
  bool _running = false;
  String _advice = '';
  bool _allGood = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  String get _url {
    final u = (widget.url ?? '').trim();
    return u.isNotEmpty ? u : app.prefs.get('server_url', Env.supabaseUrl);
  }

  String get _key {
    final k = (widget.apiKey ?? '').trim();
    return k.isNotEmpty ? k : app.prefs.get('server_key', Env.supabaseAnonKey);
  }

  void _add(String title, bool ok, String detail) => setState(() => _checks.add(_Check(title, ok, detail)));

  Future<void> _run() async {
    setState(() {
      _running = true;
      _checks.clear();
      _advice = '';
      _allGood = false;
    });
    final host = Uri.tryParse(_url)?.host ?? '';

    var internet = false;
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final res = await (await c.getUrl(Uri.parse('https://www.google.com/generate_204'))).close().timeout(const Duration(seconds: 10));
      internet = res.statusCode == 204 || res.statusCode == 200;
      c.close(force: true);
    } catch (_) {}
    _add('النت على الموبايل', internet, internet ? 'شغال' : 'الأبلكيشن مش قادر يفتح أي موقع');

    var dnsOk = false;
    try {
      dnsOk = (await InternetAddress.lookup(host).timeout(const Duration(seconds: 10))).isNotEmpty;
    } catch (_) {}
    final doh = dnsOk ? null : await ResilientHttp.dohLookup(host);
    _add(
      'عنوان السيرفر',
      dnsOk || doh != null,
      dnsOk ? 'الموبايل لاقي العنوان' : (doh != null ? 'شبكة الموبايل مش لاقياه، بس الأبلكيشن لقاه بطريقة احتياطية' : 'مش لاقي عنوان السيرفر'),
    );

    final api = ServerApi(_url, _key);
    var serverOk = false, schemaOk = false;
    try {
      final now = await api.client.rpc('server_now');
      serverOk = true;
      _add('الوصول للسيرفر', true, 'السيرفر رد (${'$now'.length > 19 ? '$now'.substring(0, 19).replaceAll('T', ' ') : now})');
    } catch (e) {
      _add('الوصول للسيرفر', false, _short(e));
    }
    if (serverOk) {
      try {
        await api.setupNeeded();
        schemaOk = true;
        _add('قاعدة البيانات', true, 'النسخة الجديدة متركبة');
      } catch (e) {
        _add('قاعدة البيانات', false, 'ملف schema.sql الجديد لسه متنفذش');
      }
    }
    await api.dispose();

    if (!mounted) return;
    setState(() {
      _running = false;
      _allGood = serverOk && schemaOk;
      if (_allGood) {
        _advice = doh != null
            ? 'كله تمام. شبكة الموبايل عندها مشكلة في معرفة عنوان السيرفر، بس الأبلكيشن بيوصله بطريقة احتياطية، فالمزامنة هتشتغل.'
            : 'كله تمام، الأبلكيشن واصل للسيرفر.';
      } else if (!internet && !serverOk) {
        _advice = 'الأبلكيشن مش واخد نت، مع إن ممكن باقي البرامج شغالة:\n'
            '1. اتأكد إن الواي فاي أو بيانات الموبايل شغالين.\n'
            '2. افتح إعدادات الموبايل ← التطبيقات ← الدمرداش ← استخدام البيانات، واسمح بالواي فاي وبيانات الموبايل وبيانات الخلفية.\n'
            '3. لو فيه "DNS خاص / Private DNS" في إعدادات الشبكة خليه "تلقائي".\n'
            '4. اقفل "توفير البيانات" لو مفعّل.';
      } else if (!serverOk) {
        _advice = 'النت شغال بس السيرفر مش بيرد:\n'
            '• افتح لوحة Supabase واتأكد إن المشروع مش متوقف (Paused). المشاريع المجانية بتقف لو محدش استخدمها أسبوع، ودوس Restore.\n'
            '• اتأكد إن رابط السيرفر والـ Publishable key صح.';
      } else {
        _advice = 'السيرفر شغال بس لسه عليه النسخة القديمة من قاعدة البيانات. افتح Supabase ← SQL Editor، والصق ملف supabase/schema.sql الجديد كله ودوس Run.';
      }
    });
  }

  String _short(Object e) {
    final t = e.toString();
    if (t.contains('Failed host lookup')) return 'مش لاقي عنوان السيرفر';
    if (t.contains('SocketException') || t.contains('ClientException')) return 'مفيش اتصال بالسيرفر';
    if (t.contains('TimeoutException')) return 'السيرفر اتأخر في الرد';
    return t.length > 120 ? '${t.substring(0, 120)}…' : t;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('اختبار الاتصال')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_url, textDirection: TextDirection.ltr, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            const Gap(10),
            TileGroup(margin: EdgeInsets.zero, children: [
              for (final c in _checks)
                ListTile(
                  leading: Icon(c.ok ? Icons.check_circle : Icons.cancel, color: c.ok ? AppColors.good : AppColors.bad),
                  title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(c.detail),
                ),
              if (_running)
                const ListTile(
                  leading: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  title: Text('بيختبر...'),
                ),
            ]),
            if (_advice.isNotEmpty) ...[
              const Gap(14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _allGood ? AppColors.goodSoft : AppColors.warnSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_advice, style: const TextStyle(height: 1.7)),
              ),
            ],
            const Gap(16),
            FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.refresh),
              label: const Text('اختبر تاني'),
            ),
          ],
        ),
      );
}
