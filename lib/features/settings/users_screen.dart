import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/schema.dart';
import '../../core/sync/server_api.dart';
import '../../core/util/format.dart';
import '../../data/permissions.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// المستخدمين والصلاحيات: who may sign in, to which business, and what each
/// of them is allowed to open. Only the owner account gets here.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>> _users = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!app.isCloud || app.server == null) {
      setState(() {
        _error = 'الموبايل ده شغال من غير سيرفر، فمفيش مستخدمين.';
        _loading = false;
      });
      return;
    }
    try {
      final users = await app.server!.departments();
      if (mounted) {
        setState(() {
          _users = users;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'مش قادر يوصل للسيرفر. اتأكد إن النت شغال وجرب تاني.';
          _loading = false;
        });
      }
    }
  }

  /// Whether this account is stopped. The server answers with a real
  /// true/false, so it is read as one.
  static bool _off(Map<String, dynamic> user) => !flag(user['active'], orElse: true);

  /// Shows what came back from the server, and reloads when it worked.
  Future<bool> _apply(Future<Map<String, dynamic>> Function() call) async {
    try {
      final r = await call();
      if (!mounted) return false;
      if (r['error'] != null) {
        toast(context, serverErrorText(r), error: true);
        return false;
      }
      await _load();
      return true;
    } catch (e) {
      if (mounted) toast(context, 'مش قادر يوصل للسيرفر. جرب تاني.', error: true);
      return false;
    }
  }

  Future<void> _add() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _UserForm(),
    );
    if (done == true) await _load();
  }

  Future<void> _edit(Map<String, dynamic> user) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _UserForm(user: user),
    );
    if (done == true) await _load();
  }

  Future<void> _toggle(Map<String, dynamic> user) async {
    final off = _off(user);
    final name = s(user['display_name']);
    final ok = off ||
        await confirmDialog(
          context,
          title: 'وقف الحساب',
          message: 'توقف حساب "$name"؟ مش هيقدر يدخل لحد ما تشغّله تاني، '
              'واللي سجله قبل كده بيفضل زي ما هو.',
          ok: 'وقف الحساب',
          danger: true,
        );
    if (!ok) return;
    final done = await _apply(() => app.server!.updateUser(id: s(user['id']), active: off));
    if (done && mounted) toast(context, off ? 'الحساب بقى شغال' : 'الحساب اتوقف');
  }

  Future<void> _delete(Map<String, dynamic> user) async {
    final ok = await confirmDialog(
      context,
      title: 'حذف الحساب',
      message: 'تحذف حساب "${s(user['display_name'])}"؟ مش هيقدر يدخل تاني. '
          'اللي سجله قبل كده بيفضل زي ما هو.',
      ok: 'حذف',
      danger: true,
    );
    if (!ok) return;
    await _apply(() => app.server!.deleteUser(s(user['id'])));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المستخدمين والصلاحيات')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('حساب جديد'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? EmptyView(
                    icon: Icons.cloud_off_outlined,
                    text: _error!,
                    actionLabel: 'جرب تاني',
                    onAction: _load,
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 90),
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: Text(
                          'كل واحد بيشتغل معاك بحساب باسمه: تحدد يدخل على أنهي قسم، ويشوف إيه. '
                          'أي تعديل هنا بيخرّجه من الأبلكيشن ويدخل تاني بالصلاحيات الجديدة.',
                          style: TextStyle(color: AppColors.muted, height: 1.6),
                        ),
                      ),
                      TileGroup(children: [
                        for (final u in _users)
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _off(u) ? AppColors.badSoft : AppColors.primarySoft,
                              child: Icon(
                                _off(u) ? Icons.person_off_outlined : Icons.person_outline,
                                color: _off(u) ? AppColors.bad : AppColors.primary,
                              ),
                            ),
                            title: Text(
                              '${s(u['display_name'])}${_off(u) ? ' (موقوف)' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '${s(u['username'])} • ${Division.names[s(u['division'])] ?? 'القسمين'}\n'
                              '${Perm.describe(s(u['permissions']))}',
                              style: const TextStyle(height: 1.5),
                            ),
                            isThreeLine: true,
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) => switch (v) {
                                'edit' => _edit(u),
                                'toggle' => _toggle(u),
                                _ => _delete(u),
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: Text(_off(u) ? 'شغّل الحساب' : 'وقف الحساب'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('حذف', style: TextStyle(color: AppColors.bad)),
                                ),
                              ],
                            ),
                            onTap: () => _edit(u),
                          ),
                      ]),
                      const Gap(),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'كلمات المرور بتتغير من "الحساب والمزامنة ← كلمات المرور".',
                          style: TextStyle(color: AppColors.muted, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
      );
}

/// Adding somebody new, or changing what an existing account may do.
class _UserForm extends StatefulWidget {
  const _UserForm({this.user});

  final Map<String, dynamic>? user;

  @override
  State<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<_UserForm> {
  late final _name = TextEditingController(text: s(widget.user?['display_name']));
  late final _username = TextEditingController(text: s(widget.user?['username']));
  final _password = TextEditingController();
  // Somebody signed in to one business only makes people for that business.
  late String _division = s(widget.user?['division']).isNotEmpty
      ? s(widget.user!['division'])
      : (app.isManager ? Division.appliances : app.sessionDivision);
  late Set<String> _perms = Perm.parse(s(widget.user?['permissions']));
  // A new account is working from the moment it is made.
  late bool _active = widget.user == null || flag(widget.user!['active'], orElse: true);
  bool _busy = false;

  bool get _isNew => widget.user == null;

  /// An empty list on the server means "everything"; in the form that is every
  /// box ticked, which reads the same to whoever is looking at it.
  Set<String> get _shown => _perms.isEmpty ? Perm.all.toSet() : _perms;

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      toast(context, 'اكتب اسم صاحب الحساب', error: true);
      return;
    }
    if (_isNew && _username.text.trim().isEmpty) {
      toast(context, 'اكتب اسم المستخدم للدخول', error: true);
      return;
    }
    if (_isNew && _password.text.length < 6) {
      toast(context, 'كلمة المرور لازم تكون 6 حروف أو أرقام على الأقل', error: true);
      return;
    }
    if (_shown.isEmpty) {
      toast(context, 'اختار حاجة واحدة على الأقل يشوفها', error: true);
      return;
    }
    setState(() => _busy = true);
    // Everything ticked is written as "no limits", so the account keeps
    // working even when a new section is added to the app later.
    final perms = _shown.length == Perm.all.length ? '' : Perm.write(_shown);
    try {
      final r = _isNew
          ? await app.server!.addUser(
              username: _username.text.trim(),
              password: _password.text,
              name: name,
              division: _division,
              permissions: perms,
            )
          : await app.server!.updateUser(
              id: s(widget.user!['id']),
              name: name,
              division: _division,
              permissions: perms,
              active: _active,
            );
      if (!mounted) return;
      if (r['error'] != null) {
        setState(() => _busy = false);
        toast(context, serverErrorText(r), error: true);
        return;
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'مش قادر يوصل للسيرفر. جرب تاني.', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                _isNew ? 'حساب جديد' : 'تعديل ${s(widget.user!['display_name'])}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                children: [
                  TextF(controller: _name, label: 'اسم صاحب الحساب', hint: 'مصطفى'),
                  const Gap(),
                  if (_isNew) ...[
                    TextF(
                      controller: _username,
                      label: 'اسم المستخدم للدخول',
                      hint: 'kasher',
                      textDirection: TextDirection.ltr,
                    ),
                    const Gap(),
                    TextF(controller: _password, label: 'كلمة المرور', obscure: true),
                    const Gap(),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'اسم المستخدم: ${s(widget.user!['username'])}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                  const Text('يدخل على', style: TextStyle(fontWeight: FontWeight.w700)),
                  const Gap(6),
                  if (app.isManager)
                    Choice<String>(
                      options: const {
                        Division.appliances: 'المعرض',
                        Division.crops: 'التجارة',
                        Division.all: 'الاتنين',
                      },
                      value: _division,
                      onChanged: (v) => setState(() => _division = v),
                    )
                  else
                    Text(
                      Division.names[_division] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted),
                    ),
                  const Gap(16),
                  const Text('يشوف إيه', style: TextStyle(fontWeight: FontWeight.w700)),
                  const Gap(4),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('كاشير بس'),
                        onPressed: () => setState(() => _perms = Perm.cashierPreset.toSet()),
                      ),
                      ActionChip(
                        label: const Text('مسؤول قسم'),
                        onPressed: () => setState(() => _perms = Perm.managerPreset.toSet()),
                      ),
                      ActionChip(
                        label: const Text('كل حاجة'),
                        onPressed: () => setState(() => _perms = Perm.all.toSet()),
                      ),
                    ],
                  ),
                  const Gap(4),
                  for (final p in Perm.all)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _shown.contains(p),
                      title: Text(Perm.names[p]!, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(Perm.details[p]!, style: const TextStyle(fontSize: 12.5, height: 1.4)),
                      onChanged: (v) => setState(() {
                        final next = {..._shown};
                        v == true ? next.add(p) : next.remove(p);
                        _perms = next;
                      }),
                    ),
                  const Divider(),
                  if (_isNew)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.check_circle_outline, color: AppColors.good),
                      title: Text('الحساب هيشتغل على طول'),
                      subtitle: Text('يقدر يدخل بمجرد ما تديله اسم المستخدم وكلمة المرور'),
                    )
                  else
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_active ? 'الحساب شغال' : 'الحساب موقوف'),
                      subtitle: Text(_active
                          ? 'قفل الزرار ده لو الشخص ده مابقاش شغال معاك'
                          : 'مش هيقدر يدخل. افتح الزرار عشان يشتغل تاني.'),
                      value: _active,
                      onChanged: (v) => setState(() => _active = v),
                    ),
                ],
              ),
            ),
            SaveBar(onSave: _busy ? null : _save, busy: _busy, label: _isNew ? 'إضافة الحساب' : 'حفظ'),
          ],
        ),
      );
}
