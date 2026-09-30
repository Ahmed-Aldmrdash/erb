import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/labels.dart';
import '../../ui/pickers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Money in / out, farmer advances, expenses, transfers between cash boxes,
/// deposits and withdrawals. Every voucher belongs to the open division and
/// remembers who of us handled the money.
class VoucherForm extends StatefulWidget {
  const VoucherForm({
    super.key,
    required this.kind,
    this.id,
    this.partyId,
    this.invoiceId,
    this.amount,
    this.notes,
  });

  final String kind;
  final String? id;
  final String? partyId;
  final String? invoiceId;
  final double? amount;
  final String? notes;

  @override
  State<VoucherForm> createState() => _VoucherFormState();
}

class _VoucherFormState extends State<VoucherForm> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _category = TextEditingController();
  final _notes = TextEditingController();
  final _handledBy = TextEditingController(text: app.person);
  String _date = todayStr();
  DbRow? _party;
  DbRow? _box;
  DbRow? _toBox;
  String? _invoiceId;
  String? _invoiceNumber;
  double _partyBalance = 0;

  /// Effect of the voucher being edited on its party's balance.
  double _originalEffect = 0;
  String? _originalPartyId;
  List<String> _categories = defaultExpenseCategories;
  bool _submitted = false;
  bool _busy = false;

  String get kind => widget.kind;

  /// Adds to / takes from an account without any cash.
  bool get _isAdjust => kind == 'debit_adj' || kind == 'credit_adj';
  bool get _needsParty => kind == 'receipt' || kind == 'payment' || kind == 'advance' || _isAdjust;

  /// +1 when the voucher makes the party owe us more.
  int get _sign => kind == 'receipt' || kind == 'credit_adj' ? -1 : 1;

  Color get _color => switch (kind) {
        'receipt' || 'deposit' => AppColors.good,
        'payment' || 'advance' || 'withdrawal' => AppColors.bad,
        'expense' => AppColors.warn,
        _ => AppColors.primary,
      };

  @override
  void initState() {
    super.initState();
    _invoiceId = widget.invoiceId;
    if (widget.amount != null) _amount.text = numText(widget.amount);
    if (widget.notes != null) _notes.text = widget.notes!;
    _init();
  }

  @override
  void dispose() {
    _amount.dispose();
    _category.dispose();
    _notes.dispose();
    _handledBy.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (kind == 'expense') {
      final cats = await app.accounts.expenseCategories();
      if (mounted) setState(() => _categories = cats);
    }
    if (widget.id != null) {
      final v = await app.accounts.voucher(widget.id!);
      if (v == null || !mounted) return;
      _date = s(v['date']);
      _amount.text = numText(n(v['amount']));
      _category.text = s(v['category']);
      _notes.text = s(v['notes']);
      _handledBy.text = s(v['handled_by']);
      _invoiceId = v['invoice_id'] as String?;
      _invoiceNumber = v['invoice_number'] as String?;
      _box = await app.accounts.cashBox(s(v['cash_box_id']));
      if (v['to_cash_box_id'] != null) _toBox = await app.accounts.cashBox(s(v['to_cash_box_id']));
      if (v['party_id'] != null) {
        _originalEffect = _sign * n(v['amount']);
        _originalPartyId = s(v['party_id']);
        await _setParty(await app.accounts.party(s(v['party_id'])));
      }
      if (mounted) setState(() {});
      return;
    }
    if (widget.partyId != null) await _setParty(await app.accounts.party(widget.partyId!));
    if (_invoiceId != null) {
      final inv = await app.db.byId('invoices', _invoiceId);
      _invoiceNumber = inv?['number'] as String?;
    }
    if (!_isAdjust) _box = await app.accounts.defaultCashBox();
    if (mounted) setState(() {});
  }

  Future<void> _setParty(DbRow? p) async {
    _party = p;
    _partyBalance = p == null ? 0 : n(p['balance']);
    if (mounted) setState(() {});
  }

  /// Party balance without the voucher being edited.
  double get _baseBalance =>
      _partyBalance - (_party != null && _party!['id'] == _originalPartyId ? _originalEffect : 0);

  String get _title => switch (kind) {
        'advance' => 'سلفة لفلاح',
        _ => voucherKinds[kind] ?? 'حركة فلوس',
      };

  String get _handledLabel => switch (kind) {
        'receipt' || 'deposit' => 'مين استلم الفلوس؟',
        'transfer' => 'مين نقل الفلوس؟',
        'withdrawal' => 'مين سحب الفلوس؟',
        _ => 'مين دفع الفلوس؟',
      };

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!_form.currentState!.validate()) return;
    if ((_box == null && !_isAdjust) || (_needsParty && _party == null)) return;
    if (kind == 'transfer' && (_toBox == null || _toBox!['id'] == _box!['id'])) return;
    setState(() => _busy = true);
    await app.accounts.saveVoucher({
      'kind': kind,
      'date': _date,
      'party_id': _needsParty ? _party!['id'] : null,
      'cash_box_id': _isAdjust ? null : _box!['id'],
      'to_cash_box_id': kind == 'transfer' ? _toBox!['id'] : null,
      'amount': roundMoney(parseNum(_amount.text)),
      'category': kind == 'expense' ? _category.text.trim() : null,
      'invoice_id': _invoiceId,
      'handled_by': _isAdjust ? null : _handledBy.text.trim(),
      'notes': _notes.text.trim(),
    }, id: widget.id);
    if (!mounted) return;
    toast(context, 'تم الحفظ');
    Navigator.pop(context, true);
  }

  /// Money was typed on the voucher but not written down yet.
  bool get _dirty => !_busy && widget.id == null && parseNum(_amount.text) > 0;

  @override
  Widget build(BuildContext context) {
    final amount = parseNum(_amount.text);
    final after = _baseBalance + _sign * amount;
    return UnsavedGuard(
      dirty: () => _dirty,
      message: 'المبلغ اللي كتبته هيضيع من غير حفظ.',
      child: Scaffold(
      appBar: AppBar(title: Text(widget.id == null ? _title : 'تعديل $_title')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DateField(label: 'التاريخ', value: _date, onChanged: (v) => setState(() => _date = v)),
            const Gap(),
            if (_needsParty) ...[
              PickField(
                label: switch (kind) {
                  'advance' => 'الفلاح',
                  'receipt' => 'استلمنا من',
                  'payment' => 'دفعنا لـ',
                  _ => 'الاسم',
                },
                value: _party == null ? null : s(_party!['name']),
                icon: Icons.person_outline,
                errorText: _submitted && _party == null ? 'اختار الاسم' : null,
                helper: _party == null ? null : 'الرصيد الحالي: ${balanceInfo(_baseBalance).text}',
                onTap: () async {
                  final p = await pickParty(
                    context,
                    preferKinds: kind == 'advance' ? const ['farmer'] : null,
                    newKind: kind == 'advance' ? 'farmer' : null,
                  );
                  if (p != null) await _setParty(await app.accounts.party(s(p['id'])));
                },
              ),
              const Gap(),
            ],
            if (kind == 'expense') ...[
              TextF(controller: _category, label: 'البند', icon: Icons.label_outline, validator: requiredText),
              const Gap(6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in _categories.take(12))
                    ChoiceChip(
                      label: Text(c),
                      selected: _category.text == c,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _category.text = c),
                    ),
                ],
              ),
              const Gap(),
            ],
            NumField(
              controller: _amount,
              label: 'المبلغ',
              suffix: currency,
              validator: positiveNumber,
              autofocus: widget.id == null && widget.amount == null && !_needsParty && kind != 'expense',
              onChanged: (_) => setState(() {}),
            ),
            if (widget.id == null &&
                _box != null &&
                !_isAdjust &&
                kind != 'receipt' &&
                kind != 'deposit' &&
                amount > n(_box!['balance']) + 0.009) ...[
              const Gap(6),
              Text(
                'تنبيه: رصيد ${s(_box!['name'])} (${egp(n(_box!['balance']))}) أقل من المبلغ',
                style: const TextStyle(color: AppColors.warn),
              ),
            ],
            if (_needsParty && _party != null && amount > 0) ...[
              const Gap(6),
              Text('الرصيد بعد كده: ${balanceInfo(after).text}', style: TextStyle(color: balanceInfo(after).color)),
            ],
            const Gap(),
            if (!_isAdjust) ...[
              PickField(
                label: kind == 'transfer' ? 'من خزنة' : 'الخزنة',
                value: _box == null ? null : '${s(_box!['name'])} (${egp(n(_box!['balance']))})',
                icon: Icons.account_balance_wallet_outlined,
                errorText: _submitted && _box == null ? 'اختار الخزنة' : null,
                onTap: () async {
                  final b = await pickCashBox(context);
                  if (b != null) setState(() => _box = b);
                },
              ),
              const Gap(),
              if (kind == 'transfer') ...[
                PickField(
                  label: 'إلى خزنة',
                  value: _toBox == null ? null : s(_toBox!['name']),
                  icon: Icons.account_balance_wallet_outlined,
                  errorText: _submitted && (_toBox == null || _toBox!['id'] == _box?['id']) ? 'اختار خزنة مختلفة' : null,
                  onTap: () async {
                    final b = await pickCashBox(context);
                    if (b != null) setState(() => _toBox = b);
                  },
                ),
                const Gap(),
              ],
              TextF(controller: _handledBy, label: _handledLabel, icon: Icons.badge_outlined),
              if (app.recentPersons.length > 1) ...[
                const Gap(6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in app.recentPersons)
                      ChoiceChip(
                        label: Text(p),
                        selected: _handledBy.text == p,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _handledBy.text = p),
                      ),
                  ],
                ),
              ],
              const Gap(),
            ],
            if (_invoiceNumber != null) ...[
              InfoRow('عن فاتورة رقم', _invoiceNumber!),
              const Gap(6),
            ],
            TextF(controller: _notes, label: 'البيان (الفلوس دي عن إيه؟)', maxLines: 3),
          ],
        ),
      ),
      bottomNavigationBar: SaveBar(onSave: _save, busy: _busy, color: _color),
      ),
    );
  }
}
