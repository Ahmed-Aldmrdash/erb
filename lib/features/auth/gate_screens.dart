import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/db/schema.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class _Logo extends StatelessWidget {
  const _Logo({this.subtitle = 'المعرض • التجارة'});

  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Image.asset('assets/images/logo.png', width: 92, height: 92),
          ),
          const SizedBox(height: 14),
          const Text('الدمرداش', style: TextStyle(fontFamily: 'Ruqaa', fontSize: 34, color: AppColors.text, height: 1.2)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: AppColors.muted)),
        ],
      );
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [_Logo(), SizedBox(height: 32), CircularProgressIndicator()],
          ),
        ),
      );
}

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 56, color: AppColors.bad),
                const SizedBox(height: 12),
                const Text('الأبلكيشن مقدرش يفتح قاعدة البيانات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(error, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
        ),
      );
}

Widget _message(String text, {bool error = false}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? AppColors.badSoft : AppColors.goodSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: error ? AppColors.bad : AppColors.good, height: 1.5)),
    );

// ---------------------------------------------------------------- server

class SetupServerScreen extends StatefulWidget {
  const SetupServerScreen({super.key});

  @override
  State<SetupServerScreen> createState() => _SetupServerScreenState();
}

class _SetupServerScreenState extends State<SetupServerScreen> {
  late final _url = TextEditingController(text: app.prefs.get('server_url', Env.supabaseUrl));
  late final _key = TextEditingController(text: app.prefs.get('server_key', Env.supabaseAnonKey));
  bool _busy = false;
  String? _error;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await app.connectServer(_url.text, _key.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Future<void> _local() async {
    final div = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('تجربة بدون سيرفر', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'البيانات هتتحفظ على الموبايل ده بس. تقدر بعدين تربطه بالسيرفر وكل اللي سجلته هيترفع.',
                style: TextStyle(color: AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: 14),
              _DivisionCard(division: Division.appliances, onTap: () => Navigator.pop(c, Division.appliances)),
              const SizedBox(height: 10),
              _DivisionCard(division: Division.crops, onTap: () => Navigator.pop(c, Division.crops)),
            ],
          ),
        ),
      ),
    );
    if (div != null) await app.useLocalMode(div);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 16),
              const _Logo(),
              const SizedBox(height: 24),
              Box(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('ربط بسيرفر الشركة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text(
                      'هتلاقي الاتنين في لوحة Supabase من زرار Connect، أو Project Settings ← API Keys.',
                      style: TextStyle(color: AppColors.muted, height: 1.5),
                    ),
                    const SizedBox(height: 14),
                    TextF(controller: _url, label: 'Project URL', keyboard: TextInputType.url, textDirection: TextDirection.ltr),
                    const SizedBox(height: 12),
                    TextF(controller: _key, label: 'Publishable key', textDirection: TextDirection.ltr),
                    if (_error != null) ...[const SizedBox(height: 10), _message(_error!, error: true)],
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _busy ? null : _connect,
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('اتصال'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _busy ? null : _local,
                icon: const Icon(Icons.phone_android),
                label: const Text('جرب بدون سيرفر'),
              ),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------- accounts

/// First start on a new server: username / password of each department.
class SetupAccountsScreen extends StatefulWidget {
  const SetupAccountsScreen({super.key});

  @override
  State<SetupAccountsScreen> createState() => _SetupAccountsScreenState();
}

class _SetupAccountsScreenState extends State<SetupAccountsScreen> {
  final _form = GlobalKey<FormState>();
  final _appUser = TextEditingController(text: 'maarad');
  final _appPass = TextEditingController();
  final _appPass2 = TextEditingController();
  final _cropsUser = TextEditingController(text: 'tegara');
  final _cropsPass = TextEditingController();
  final _cropsPass2 = TextEditingController();
  final _ownerUser = TextEditingController(text: 'admin');
  final _ownerPass = TextEditingController();
  bool _withOwner = true;
  bool _busy = false;
  String? _error;

  String? _pass(String? v) => (v == null || v.length < 6) ? '6 حروف أو أرقام على الأقل' : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await app.setupAccounts(
      cropsUser: _cropsUser.text,
      cropsPass: _cropsPass.text,
      appliancesUser: _appUser.text,
      appliancesPass: _appPass.text,
      ownerUser: _withOwner ? _ownerUser.text : null,
      ownerPass: _withOwner ? _ownerPass.text : null,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Widget _department({
    required String division,
    required TextEditingController user,
    required TextEditingController pass,
    required TextEditingController pass2,
  }) {
    final color = division == Division.crops ? tradePalette.primary : showroomPalette.primary;
    return Box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(division == Division.crops ? Icons.grass : Icons.kitchen, color: color),
              const SizedBox(width: 8),
              Text(Division.names[division]!, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(Division.long[division]!, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextF(controller: user, label: 'اسم المستخدم', icon: Icons.badge_outlined, validator: requiredText, textDirection: TextDirection.ltr),
          const SizedBox(height: 10),
          TextF(controller: pass, label: 'كلمة المرور', icon: Icons.lock_outline, obscure: true, validator: _pass, textDirection: TextDirection.ltr),
          const SizedBox(height: 10),
          TextF(
            controller: pass2,
            label: 'تأكيد كلمة المرور',
            icon: Icons.lock_outline,
            obscure: true,
            textDirection: TextDirection.ltr,
            validator: (v) => v != pass.text ? 'مش زي كلمة المرور' : null,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const _Logo(subtitle: 'تظبيط الحسابات لأول مرة'),
                const SizedBox(height: 18),
                const Text(
                  'حدد اسم مستخدم وكلمة مرور لكل قسم. أي حد هيدخل هيكتب اسمه بس، وكل حاجة هيسجلها هتتكتب باسمه.',
                  style: TextStyle(color: AppColors.muted, height: 1.6),
                ),
                const SizedBox(height: 14),
                _department(division: Division.appliances, user: _appUser, pass: _appPass, pass2: _appPass2),
                const SizedBox(height: 12),
                _department(division: Division.crops, user: _cropsUser, pass: _cropsPass, pass2: _cropsPass2),
                const SizedBox(height: 12),
                Box(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _withOwner,
                        onChanged: (v) => setState(() => _withOwner = v),
                        title: const Text('حساب الإدارة', style: TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: const Text('يشوف القسمين ويقدر يغير كلمات المرور (اختياري)'),
                      ),
                      if (_withOwner) ...[
                        TextF(controller: _ownerUser, label: 'اسم المستخدم', icon: Icons.badge_outlined, validator: requiredText, textDirection: TextDirection.ltr),
                        const SizedBox(height: 10),
                        TextF(controller: _ownerPass, label: 'كلمة المرور', icon: Icons.lock_outline, obscure: true, validator: _pass, textDirection: TextDirection.ltr),
                      ],
                    ],
                  ),
                ),
                if (_error != null) ...[const SizedBox(height: 12), _message(_error!, error: true)],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.check),
                  label: const Text('حفظ الحسابات'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'احتفظ بكلمات المرور في مكان آمن. تقدر تغيرها بعدين من الإعدادات.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------- login

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  late final _user = TextEditingController(text: app.prefs.get('username'));
  final _pass = TextEditingController();
  late final _person = TextEditingController(text: app.person);
  bool _show = false;
  bool _busy = false;
  String? _error;

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await app.login(_user.text, _pass.text, _person.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final recent = app.recentPersons;
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 16),
              const _Logo(),
              const SizedBox(height: 24),
              if (app.gateMessage.isNotEmpty) ...[
                // Everything but "تم إنشاء الحسابات" is a problem to fix.
                _message(app.gateMessage, error: !app.gateMessage.startsWith('تم ')),
                const SizedBox(height: 12),
              ],
              Box(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('تسجيل الدخول', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    TextF(
                      controller: _user,
                      label: 'اسم المستخدم (المعرض أو التجارة)',
                      icon: Icons.badge_outlined,
                      textDirection: TextDirection.ltr,
                      validator: requiredText,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pass,
                      obscureText: !_show,
                      textDirection: TextDirection.ltr,
                      validator: requiredText,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _show = !_show),
                          icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextF(controller: _person, label: 'اسمك', icon: Icons.person_outline, validator: requiredText),
                    if (recent.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final r in recent)
                            ActionChip(label: Text(r), onPressed: () => setState(() => _person.text = r)),
                        ],
                      ),
                    ],
                    if (_error != null) ...[const SizedBox(height: 12), _message(_error!, error: true)],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _login,
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('دخول'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- division

class _DivisionCard extends StatelessWidget {
  const _DivisionCard({required this.division, required this.onTap});

  final String division;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = division == Division.crops ? tradePalette : showroomPalette;
    return Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [p.primary, p.dark], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(16)),
                child: Icon(division == Division.crops ? Icons.grass : Icons.kitchen, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Division.names[division]!, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    Text(Division.long[division]!, style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// Manager / trial: choose which business to open.
class PickDivisionScreen extends StatelessWidget {
  const PickDivisionScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 16),
              _Logo(subtitle: app.isCloud ? 'أهلاً ${app.person}' : 'تجربة بدون سيرفر'),
              const SizedBox(height: 28),
              const Text('افتح أنهي قسم؟', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _DivisionCard(division: Division.appliances, onTap: () => app.switchDivision(Division.appliances)),
              const SizedBox(height: 12),
              _DivisionCard(division: Division.crops, onTap: () => app.switchDivision(Division.crops)),
              const SizedBox(height: 20),
              if (app.isCloud)
                TextButton.icon(onPressed: app.logout, icon: const Icon(Icons.logout), label: const Text('تسجيل خروج'))
              else
                TextButton(onPressed: app.changeServer, child: const Text('ربط بالسيرفر')),
            ],
          ),
        ),
      );
}

class InitialSyncScreen extends StatelessWidget {
  const InitialSyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final failed = app.gateMessage.startsWith('فشل');
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Logo(),
              const SizedBox(height: 32),
              if (!failed) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(app.gateMessage, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
              if (failed) ...[
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: app.retryOpen, icon: const Icon(Icons.refresh), label: const Text('حاول تاني')),
                TextButton(onPressed: app.logout, child: const Text('تسجيل خروج')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

