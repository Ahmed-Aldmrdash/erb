import 'package:flutter/material.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';

import '../../core/app_state.dart';
import '../../core/util/format.dart';
import '../../data/labels.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Add or edit a customer / supplier / farmer / trader. Pops with the saved
/// row so pickers can select it right away.
class PartyFormScreen extends StatefulWidget {
  const PartyFormScreen({super.key, this.id, this.defaultKind = 'customer'});

  final String? id;
  final String defaultKind;

  @override
  State<PartyFormScreen> createState() => _PartyFormScreenState();
}

class _PartyFormScreenState extends State<PartyFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _nationalId = TextEditingController();
  final _opening = TextEditingController();
  final _notes = TextEditingController();
  final _creditLimit = TextEditingController();
  late String _kind = widget.defaultKind;
  String _collectOn = '';
  /// Direction of the old balance; must be chosen when there is an amount.
  bool? _openingOwesUs;
  bool _busy = false;

  final FlutterNativeContactPicker _contactPicker = FlutterNativeContactPicker();

  @override
  void initState() {
    super.initState();
    if (widget.id != null) _load();
  }

  Future<void> _load() async {
    final p = await app.db.byId('parties', widget.id);
    if (p == null || !mounted) return;
    setState(() {
      _name.text = s(p['name']);
      _kind = s(p['kind']);
      _phone.text = s(p['phone']);
      _address.text = s(p['address']);
      _nationalId.text = s(p['national_id']);
      final ob = n(p['opening_balance']);
      _opening.text = numText(ob.abs());
      _openingOwesUs = ob.abs() < 0.01 ? null : ob > 0;
      _notes.text = s(p['notes']);
      _collectOn = s(p['collect_on']);
      _creditLimit.text = numText(n(p['credit_limit']));
    });
  }

  Future<void> _pickContact() async {
    try {
      final contact = await _contactPicker.selectContact();
      if (contact != null) {
        setState(() {
          if (contact.phoneNumbers != null && contact.phoneNumbers!.isNotEmpty) {
            _phone.text = contact.phoneNumbers!.first;
          }
          if (_name.text.isEmpty && contact.fullName != null) {
            _name.text = contact.fullName!;
          }
        });
      }
    } catch (e) {
      if (mounted) toast(context, 'حصل مشكلة في فتح جهات الاتصال', error: true);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final opening = parseNum(_opening.text);
    if (opening > 0 && _openingOwesUs == null) {
      toast(context, 'اختار الرصيد القديم: لينا عنده ولا علينا له؟', error: true);
      return;
    }
    setState(() => _busy = true);
    final id = await app.accounts.saveParty({
      'name': _name.text.trim(),
      'kind': _kind,
      'phone': normalizeDigits(_phone.text.trim()),
      'address': _address.text.trim(),
      'national_id': normalizeDigits(_nationalId.text.trim()),
      'opening_balance': opening <= 0 ? 0 : (_openingOwesUs! ? opening : -opening),
      'collect_on': _collectOn.isEmpty ? null : _collectOn,
      'credit_limit': parseNum(_creditLimit.text),
      'notes': _notes.text.trim(),
    }, id: widget.id);
    final row = await app.accounts.party(id);
    if (mounted) Navigator.pop(context, row);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'حذف',
      message: 'حذف "${_name.text}"؟',
      ok: 'حذف',
      danger: true,
    );
    if (!ok) return;
    final err = await app.accounts.deleteParty(widget.id!);
    if (!mounted) return;
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    Navigator.of(context)
      ..pop()
      ..maybePop();
  }

  /// A name was typed but not written down yet.
  bool get _dirty => !_busy && widget.id == null && _name.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) => UnsavedGuard(
        dirty: () => _dirty,
        message: 'البيانات اللي كتبتها هتضيع من غير حفظ.',
        child: Scaffold(
        appBar: AppBar(
          title: Text(widget.id == null ? 'إضافة اسم جديد' : 'تعديل البيانات'),
          actions: [
            if (widget.id != null)
              IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline, color: AppColors.bad)),
          ],
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextF(controller: _name, label: 'الاسم', icon: Icons.person_outline, validator: requiredText, autofocus: widget.id == null),
              const Gap(),
              const Text('النوع', style: TextStyle(color: AppColors.muted)),
              const Gap(6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in {...partyKindsFor(app.division), if (!partyKindsFor(app.division).containsKey(_kind)) _kind: partyKinds[_kind] ?? _kind}.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _kind == e.key,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _kind = e.key),
                    ),
                ],
              ),
              TextF(
                controller: _phone,
                label: 'التليفون',
                icon: Icons.phone_outlined,
                keyboard: TextInputType.phone,
                suffixIcon: IconButton(
                  icon: Icon(Icons.contacts_outlined, color: AppColors.primary),
                  onPressed: _pickContact,
                  tooltip: 'اختيار من جهات الاتصال',
                ),
              ),
              const Gap(),
              TextF(controller: _address, label: 'العنوان', icon: Icons.location_on_outlined),
              const Gap(),
              TextF(
                controller: _nationalId,
                label: 'الرقم القومي (اختياري)',
                icon: Icons.badge_outlined,
                keyboard: TextInputType.number,
              ),
              const Gap(16),
              Box(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('رصيد سابق (أول المدة)', style: TextStyle(fontWeight: FontWeight.w700)),
                    const Gap(4),
                    const Text('لو في حساب قديم قبل ما تبدأ تستخدم الأبلكيشن', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    const Gap(10),
                    NumField(controller: _opening, label: 'المبلغ', suffix: currency, onChanged: (_) => setState(() {})),
                    const Gap(10),
                    Row(
                      children: [
                        for (final owesUs in [true, false]) ...[
                          if (!owesUs) const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: SizedBox(
                                width: double.infinity,
                                child: Text(
                                  owesUs ? 'لينا عنده\n(هو مديون لينا)' : 'علينا له\n(إحنا مديونين له)',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(height: 1.4),
                                ),
                              ),
                              selected: _openingOwesUs == owesUs,
                              showCheckmark: false,
                              selectedColor: (owesUs ? AppColors.good : AppColors.bad).withValues(alpha: 0.15),
                              onSelected: (_) => setState(() => _openingOwesUs = owesUs),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (parseNum(_opening.text) > 0 && _openingOwesUs != null) ...[
                      const Gap(8),
                      Text(
                        'هيتسجل: ${balanceInfo(_openingOwesUs! ? parseNum(_opening.text) : -parseNum(_opening.text)).text}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _openingOwesUs! ? AppColors.good : AppColors.bad,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(),
              DateField(
                label: 'ميعاد التحصيل / السداد (اختياري)',
                value: _collectOn,
                onChanged: (v) => setState(() => _collectOn = v),
              ),
              if (_collectOn.isNotEmpty)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(onPressed: () => setState(() => _collectOn = ''), child: const Text('بدون ميعاد')),
                ),
              const Gap(),
              NumField(
                controller: _creditLimit,
                label: 'أقصى مبلغ ممكن يبقى عليه (اختياري)',
                suffix: currency,
                helper: 'هيظهر تنبيه لو الحساب عدّاه',
              ),
              const Gap(),
              TextF(controller: _notes, label: 'ملاحظات', maxLines: 3),
            ],
          ),
        ),
        bottomNavigationBar: SaveBar(onSave: _save, busy: _busy),
        ),
      );
}
