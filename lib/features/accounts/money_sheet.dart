import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../ui/pickers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Quick "استلمت فلوس" / "دفعت فلوس" entry on an account: amount, date,
/// cash box, who of us handled the money and what it was for.
Future<bool?> showMoneySheet(
  BuildContext context, {
  required DbRow party,
  required bool receive,
  double? amount,
  String? note,
  String? invoiceId,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MoneySheet(party: party, receive: receive, amount: amount, note: note, invoiceId: invoiceId),
    );

class _MoneySheet extends StatefulWidget {
  const _MoneySheet({required this.party, required this.receive, this.amount, this.note, this.invoiceId});

  final DbRow party;
  final bool receive;
  final double? amount;
  final String? note;
  final String? invoiceId;

  @override
  State<_MoneySheet> createState() => _MoneySheetState();
}

class _MoneySheetState extends State<_MoneySheet> {
  late final _amount = TextEditingController(text: numText(widget.amount));
  late final _handledBy = TextEditingController(text: app.person);
  late final _notes = TextEditingController(text: widget.note ?? '');
  String _date = todayStr();
  DbRow? _box;
  bool _advance = false;
  bool _busy = false;

  bool get _farmer => widget.party['kind'] == 'farmer';

  @override
  void initState() {
    super.initState();
    app.accounts.defaultCashBox().then((b) {
      if (mounted) setState(() => _box = b);
    });
  }

  Future<void> _save() async {
    final amount = roundMoney(parseNum(_amount.text));
    if (amount <= 0) {
      toast(context, 'اكتب المبلغ', error: true);
      return;
    }
    if (_box == null) {
      toast(context, 'اختار الخزنة', error: true);
      return;
    }
    setState(() => _busy = true);
    await app.accounts.saveVoucher({
      'kind': widget.receive ? 'receipt' : (_advance ? 'advance' : 'payment'),
      'date': _date,
      'party_id': widget.party['id'],
      'cash_box_id': _box!['id'],
      'amount': amount,
      'invoice_id': widget.invoiceId,
      'handled_by': _handledBy.text.trim(),
      'notes': _notes.text.trim(),
    });
    if (!mounted) return;
    toast(context, widget.receive ? 'اتسجل استلام ${egp(amount)}' : 'اتسجل دفع ${egp(amount)}');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.receive ? AppColors.good : AppColors.bad;
    final today = DateTime.now();
    final balance = n(widget.party['balance']);
    final after = balance + (widget.receive ? -1 : 1) * parseNum(_amount.text);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(widget.receive ? Icons.south_west : Icons.north_east, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.receive ? 'استلمت فلوس من ${s(widget.party['name'])}' : 'دفعت فلوس لـ ${s(widget.party['name'])}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
                  ),
                ),
              ],
            ),
            const Gap(14),
            TextField(
              controller: _amount,
              autofocus: widget.amount == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: color),
              decoration: const InputDecoration(hintText: '0', suffixText: currency),
              onChanged: (_) => setState(() {}),
            ),
            const Gap(6),
            Text('الحساب بعد كده: ${balanceInfo(after).text}', textAlign: TextAlign.center, style: TextStyle(color: balanceInfo(after).color)),
            if (_farmer && !widget.receive) ...[
              const Gap(),
              Choice<bool>(
                options: const {false: 'دفعة من الحساب', true: 'سلفة'},
                value: _advance,
                onChanged: (v) => setState(() => _advance = v),
              ),
            ],
            const Gap(),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('التاريخ:', style: TextStyle(color: AppColors.muted)),
                for (final e in {
                  'النهارده': dateStr(today),
                  'امبارح': dateStr(today.subtract(const Duration(days: 1))),
                }.entries)
                  ChoiceChip(
                    label: Text(e.key),
                    selected: _date == e.value,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _date = e.value),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.event, size: 18),
                  label: Text(showDate(_date)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: parseDate(_date) ?? today,
                      firstDate: DateTime(2015),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _date = dateStr(d));
                  },
                ),
              ],
            ),
            const Gap(),
            TextF(
              controller: _handledBy,
              label: widget.receive ? 'مين استلم الفلوس منه؟' : 'مين سلّم الفلوس؟',
              icon: Icons.person_outline,
            ),
            const Gap(6),
            Wrap(
              spacing: 6,
              children: [
                for (final p in app.recentPersons)
                  ActionChip(label: Text(p), onPressed: () => setState(() => _handledBy.text = p)),
              ],
            ),
            const Gap(),
            TextF(controller: _notes, label: 'البيان (الفلوس دي عن إيه؟)', maxLines: 2),
            const Gap(),
            PickField(
              label: 'الخزنة',
              value: _box == null ? null : s(_box!['name']),
              icon: Icons.account_balance_wallet_outlined,
              onTap: () async {
                final b = await pickCashBox(context);
                if (b != null) setState(() => _box = b);
              },
            ),
            const Gap(16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(widget.receive ? 'تسجيل الاستلام' : 'تسجيل الدفع'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Change an account without any cash: زوّد على حسابه (goods taken without
/// an invoice, an old debt) or نزّل من حسابه (a discount, a mistake).
Future<bool?> showAdjustSheet(BuildContext context, {required DbRow party, required bool increase}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AdjustSheet(party: party, increase: increase),
    );

class _AdjustSheet extends StatefulWidget {
  const _AdjustSheet({required this.party, required this.increase});

  final DbRow party;
  final bool increase;

  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String _date = todayStr();
  bool _busy = false;

  List<String> get _reasons => widget.increase
      ? const ['بضاعة من غير فاتورة', 'حساب قديم من الدفتر', 'فرق حساب', 'مصاريف عليه']
      : const ['خصم', 'سماح', 'غلطة في الحساب', 'فرق وزن'];

  Future<void> _save() async {
    final amount = roundMoney(parseNum(_amount.text));
    if (amount <= 0) {
      toast(context, 'اكتب المبلغ', error: true);
      return;
    }
    if (_reason.text.trim().isEmpty) {
      toast(context, 'اكتب السبب علشان يبان في الحساب', error: true);
      return;
    }
    setState(() => _busy = true);
    await app.accounts.saveVoucher({
      'kind': widget.increase ? 'debit_adj' : 'credit_adj',
      'date': _date,
      'party_id': widget.party['id'],
      'amount': amount,
      'notes': _reason.text.trim(),
    });
    if (!mounted) return;
    toast(context, widget.increase ? 'اتزوّد ${egp(amount)} على الحساب' : 'اتنزّل ${egp(amount)} من الحساب');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    // No cash moves, so neither the "money in" green nor the "money out" red.
    final color = AppColors.primary;
    final balance = n(widget.party['balance']);
    final after = balance + (widget.increase ? 1 : -1) * parseNum(_amount.text);
    final name = s(widget.party['name']);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.increase ? 'زوّد على حساب $name' : 'نزّل من حساب $name',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
            ),
            const Gap(4),
            Text(
              widget.increase
                  ? 'من غير فلوس ما تخرج من الخزنة: بيزوّد اللي لينا عنده (أو ينقّص اللي علينا له).'
                  : 'من غير فلوس ما تدخل الخزنة: بينقّص اللي لينا عنده (أو يزوّد اللي علينا له).',
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const Gap(12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: color),
              decoration: const InputDecoration(hintText: '0', suffixText: currency),
              onChanged: (_) => setState(() {}),
            ),
            const Gap(6),
            Text(
              'الحساب بعد كده: ${balanceInfo(after).text}',
              textAlign: TextAlign.center,
              style: TextStyle(color: balanceInfo(after).color, fontWeight: FontWeight.w700),
            ),
            const Gap(),
            TextF(controller: _reason, label: 'السبب', icon: Icons.edit_note),
            const Gap(6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in _reasons)
                  ActionChip(label: Text(r), onPressed: () => setState(() => _reason.text = r)),
              ],
            ),
            const Gap(),
            DateField(label: 'التاريخ', value: _date, onChanged: (v) => setState(() => _date = v)),
            const Gap(16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('تسجيل'),
            ),
          ],
        ),
      ),
    );
  }
}
