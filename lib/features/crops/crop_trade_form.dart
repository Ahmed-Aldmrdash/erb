import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/calc.dart';
import '../../ui/pickers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'crop_trade_detail.dart';
import 'sack_weights_screen.dart';

/// One weighing: buying from a farmer (kind = purchase) or selling to a
/// trader / factory (kind = sale), with bag, moisture and impurity deductions,
/// freight and loading, and what was paid now.
class CropTradeForm extends StatefulWidget {
  const CropTradeForm({super.key, required this.kind, this.id, this.partyId, this.cropId});

  final String kind;
  final String? id;
  final String? partyId;
  final String? cropId;

  @override
  State<CropTradeForm> createState() => _CropTradeFormState();
}

class _CropTradeFormState extends State<CropTradeForm> {
  final _form = GlobalKey<FormState>();
  final _gross = TextEditingController();
  final _tare = TextEditingController();
  final _bags = TextEditingController();
  final _bagWeight = TextEditingController();
  final _moisture = TextEditingController();
  final _impurities = TextEditingController();
  final _otherDeduction = TextEditingController();
  final _price = TextEditingController();
  final _freight = TextEditingController();
  final _loading = TextEditingController();
  final _otherExpenses = TextEditingController();
  final _paid = TextEditingController();
  final _ticket = TextEditingController();
  final _vehicle = TextEditingController();
  final _notes = TextEditingController();

  String _date = todayStr();
  DbRow? _party;
  double _partyBalance = 0;
  DbRow? _crop;
  DbRow? _warehouse;
  DbRow? _box;
  /// scale: باسكول (القايم - الفارغ) | sacks: بالشكارة.
  String _mode = app.prefs.get('weigh_mode', 'scale');
  List<double> _sackWeights = [];

  /// Sacks mode: only the count and the total were written (no list).
  bool _sacksByTotal = false;
  String _unitName = 'طن';
  double _kgPerUnit = 1000;
  bool _expensesOnParty = false;
  double _available = 0;
  double _costPerKg = 0;
  String? _origPartyId;
  double _origPartyEffect = 0;
  bool _submitted = false;
  bool _busy = false;

  bool get isSale => widget.kind == 'sale';

  bool get _sacksList => _mode == 'sacks' && !_sacksByTotal;

  CropCalc get calc => CropCalc(
        isSale: isSale,
        grossKg: _sacksList ? _sackWeights.fold<double>(0, (a, w) => a + w) : parseNum(_gross.text),
        tareKg: _mode == 'scale' ? parseNum(_tare.text) : 0,
        bagsCount: _sacksList ? _sackWeights.length.toDouble() : parseNum(_bags.text),
        bagWeightKg: parseNum(_bagWeight.text),
        moistureKg: parseNum(_moisture.text),
        impuritiesKg: parseNum(_impurities.text),
        otherDeductionKg: parseNum(_otherDeduction.text),
        kgPerUnit: _kgPerUnit,
        pricePerUnit: parseNum(_price.text),
        freight: parseNum(_freight.text),
        loading: parseNum(_loading.text),
        otherExpenses: parseNum(_otherExpenses.text),
        expensesOnParty: _expensesOnParty,
        paid: parseNum(_paid.text),
      );

  /// How the trade changes the party balance (+ means the party owes us more).
  double _effect(CropCalc c) => isSale ? c.partyTotal - c.paid : c.paid - c.partyTotal;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.id != null) {
      await _loadExisting();
    } else {
      final bw = app.settings['default_bag_weight'] ?? '';
      if (bw.isNotEmpty) _bagWeight.text = bw;
      final warehouses = await app.crops.warehouses();
      if (warehouses.isNotEmpty) _warehouse = warehouses.first;
      _box = await app.accounts.defaultCashBox();
      if (widget.partyId != null) await _setParty(widget.partyId!);
      if (widget.cropId != null) {
        final c = await app.db.byId('crops', widget.cropId);
        if (c != null) _setCrop(c);
      } else {
        final crops = await app.crops.crops();
        if (crops.length == 1) _setCrop(crops.first);
      }
    }
    await _refreshStock();
    if (mounted) setState(() {});
  }

  Future<void> _loadExisting() async {
    final t = await app.crops.trade(widget.id!);
    if (t == null) return;
    _date = s(t['date']);
    final old = CropCalc.fromRow(t);
    _mode = s(t['weigh_mode']) == 'sacks' ? 'sacks' : 'scale';
    _sackWeights = sackWeightsOf(t['sack_weights']);
    _sacksByTotal = _mode == 'sacks' && _sackWeights.isEmpty;
    _gross.text = numText(n(t['gross_kg']));
    _tare.text = numText(n(t['tare_kg']));
    _bags.text = numText(n(t['bags_count']));
    _bagWeight.text = numText(n(t['bag_weight_kg']));
    // Old weighings kept the deductions as percentages: show them in kilos.
    _moisture.text = numText(old.moistureDeductionKg);
    _impurities.text = numText(old.impuritiesDeductionKg);
    _otherDeduction.text = numText(n(t['other_deduction_kg']));
    _price.text = numText(n(t['price_per_unit']));
    _freight.text = numText(n(t['freight']));
    _loading.text = numText(n(t['loading']));
    _otherExpenses.text = numText(n(t['other_expenses']));
    _paid.text = numText(n(t['paid_amount']));
    _ticket.text = s(t['ticket_no']);
    _vehicle.text = s(t['vehicle']);
    _notes.text = s(t['notes']);
    _expensesOnParty = n(t['expenses_on_party']) == 1;
    _unitName = s(t['unit_name']);
    _kgPerUnit = n(t['kg_per_unit']);
    _crop = await app.db.byId('crops', s(t['crop_id']));
    _warehouse = await app.db.byId('warehouses', s(t['warehouse_id']));
    _box = await app.accounts.cashBox(s(t['cash_box_id']));
    _origPartyId = s(t['party_id']);
    _origPartyEffect = isSale
        ? n(t['party_total']) - n(t['paid_amount'])
        : n(t['paid_amount']) - n(t['party_total']);
    await _setParty(_origPartyId!);
  }

  Future<void> _setParty(String id) async {
    final p = await app.accounts.party(id);
    _party = p;
    _partyBalance = n(p?['balance']);
    // Without this trade, when editing it.
    if (id == _origPartyId) _partyBalance -= _origPartyEffect;
    if (mounted) setState(() {});
  }

  void _setCrop(DbRow c) {
    final changed = _crop?['id'] != c['id'];
    _crop = c;
    _unitName = s(c['unit_name']);
    _kgPerUnit = n(c['kg_per_unit']);
    // Today's price from the price board (أسعار النهارده), for new trades.
    final price = n(c[isSale ? 'sell_price' : 'buy_price']);
    if (widget.id == null && price > 0 && (changed || _price.text.trim().isEmpty)) {
      _price.text = numText(price);
    }
  }

  Future<void> _refreshStock() async {
    if (_crop == null) return;
    _costPerKg = await app.crops.costPerKg(s(_crop!['id']));
    if (_warehouse != null) {
      _available = await app.crops.stockAt(s(_crop!['id']), s(_warehouse!['id']), excludeDocId: widget.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    final c = calc;
    final formOk = _form.currentState!.validate();
    final needsBox = c.paid > 0 || c.expenses > 0;
    if (!formOk || _party == null || _crop == null || _warehouse == null || (needsBox && _box == null)) {
      toast(context, 'كمّل البيانات المطلوبة', error: true);
      return;
    }
    if (c.netKg <= 0) {
      toast(context, 'الوزن الصافي لازم يكون أكبر من صفر', error: true);
      return;
    }
    if (isSale && c.stockKg > _available + 0.001) {
      final ok = await confirmDialog(
        context,
        title: 'الكمية أكبر من المخزون',
        message: 'المتاح في ${s(_warehouse!['name'])}: ${kgWithUnits(_available, _unitName, _kgPerUnit)}\n'
            'الكمية الخارجة: ${kgWithUnits(c.stockKg, _unitName, _kgPerUnit)}\nتكمل الحفظ؟',
        ok: 'احفظ',
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    await app.prefs.set('weigh_mode', _mode);
    final id = await app.crops.saveTrade({
      'kind': widget.kind,
      'date': _date,
      'party_id': _party!['id'],
      'crop_id': _crop!['id'],
      'warehouse_id': _warehouse!['id'],
      'cash_box_id': _box?['id'],
      'unit_name': _unitName,
      'kg_per_unit': _kgPerUnit,
      'weigh_mode': _mode,
      'gross_kg': c.grossKg,
      'tare_kg': c.tareKg,
      'sack_weights': _sacksList && _sackWeights.isNotEmpty ? sackWeightsJson(_sackWeights) : null,
      'bags_count': c.bagsCount,
      'bag_weight_kg': c.bagWeightKg,
      'moisture_kg': c.moistureKg,
      'impurities_kg': c.impuritiesKg,
      'moisture_pct': 0,
      'impurities_pct': 0,
      'other_deduction_kg': c.otherDeductionKg,
      'net_kg': c.netKg,
      'stock_kg': c.stockKg,
      'price_per_unit': c.pricePerUnit,
      'subtotal': c.subtotal,
      'freight': c.freight,
      'loading': c.loading,
      'other_expenses': c.otherExpenses,
      'expenses_on_party': _expensesOnParty,
      'party_total': c.partyTotal,
      'paid_amount': roundMoney(c.paid),
      'ticket_no': _ticket.text.trim(),
      'vehicle': _vehicle.text.trim(),
      'notes': _notes.text.trim(),
    }, id: widget.id);
    if (!mounted) return;
    if (widget.id == null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CropTradeDetailScreen(tradeId: id, justSaved: true)));
    } else {
      Navigator.pop(context);
    }
  }

  void _changed([String? _]) => setState(() {});

  Future<void> _editSacks({required bool photo}) async {
    final r = await push<List<double>>(context, SackWeightsScreen(initial: _sackWeights, startWithPhoto: photo));
    if (r != null) setState(() => _sackWeights = r);
  }

  Widget _pair(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)],
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(text, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
      );

  /// Something was written on this trade and not saved yet.
  bool get _dirty =>
      !_busy && widget.id == null && (_party != null || parseNum(_gross.text) > 0 || parseNum(_bags.text) > 0);

  @override
  Widget build(BuildContext context) {
    final c = calc;
    final after = _partyBalance + _effect(c);
    final unit = _unitName;
    return UnsavedGuard(
      dirty: () => _dirty,
      message: 'العملية اللي بتكتبها هتضيع من غير حفظ.',
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.id != null ? 'تعديل العملية' : (isSale ? 'بيع محصول' : 'توريد محصول (شراء)')),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            DateField(label: 'التاريخ', value: _date, onChanged: (v) => setState(() => _date = v)),
            const Gap(),
            PickField(
              label: isSale ? 'التاجر / المصنع' : 'الفلاح / المورد',
              value: _party == null ? null : s(_party!['name']),
              icon: Icons.person_outline,
              errorText: _submitted && _party == null ? 'اختار الاسم' : null,
              helper: _party == null ? null : 'رصيده الحالي: ${balanceInfo(_partyBalance).text}',
              onTap: () async {
                final p = await pickParty(
                  context,
                  title: isSale ? 'اختار التاجر' : 'اختار الفلاح',
                  preferKinds: isSale ? const ['trader'] : const ['farmer'],
                  newKind: isSale ? 'trader' : 'farmer',
                );
                if (p != null) await _setParty(s(p['id']));
              },
            ),
            const Gap(),
            PickField(
              label: 'المحصول',
              value: _crop == null ? null : '${s(_crop!['name'])} (ال$unit = ${qty(_kgPerUnit)} كجم)',
              icon: Icons.grass,
              errorText: _submitted && _crop == null ? 'اختار المحصول' : null,
              onTap: () async {
                final r = await pickCrop(context);
                if (r == null) return;
                setState(() => _setCrop(r));
                await _refreshStock();
              },
            ),
            const Gap(),
            PickField(
              label: 'المخزن / الشونة',
              value: _warehouse == null ? null : s(_warehouse!['name']),
              icon: Icons.warehouse_outlined,
              errorText: _submitted && _warehouse == null ? 'اختار المخزن' : null,
              helper: isSale && _crop != null && _warehouse != null
                  ? 'المتاح: ${kgWithUnits(_available, unit, _kgPerUnit)}'
                  : null,
              onTap: () async {
                final r = await pickWarehouse(context);
                if (r == null) return;
                setState(() => _warehouse = r);
                await _refreshStock();
              },
            ),
            _label('الوزن'),
            Box(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Choice<String>(
                    options: const {'scale': 'باسكول (قايم وفارغ)', 'sacks': 'بالشكارة'},
                    value: _mode,
                    onChanged: (v) => setState(() => _mode = v),
                  ),
                  const Gap(),
                  if (_mode == 'scale') ...[
                    _pair(
                      NumField(
                        controller: _gross,
                        label: 'القايم (محمّل)',
                        suffix: 'كجم',
                        validator: positiveNumber,
                        onChanged: _changed,
                      ),
                      NumField(
                        controller: _tare,
                        label: 'الفارغ (فاضي)',
                        suffix: 'كجم',
                        validator: (v) => parseNum(v) >= parseNum(_gross.text) && parseNum(v) > 0 ? 'أكبر من القايم' : null,
                        onChanged: _changed,
                      ),
                    ),
                    InfoRow('وزن الحمولة (القايم - الفارغ)', '${qty(c.loadKg)} كجم', bold: true),
                    const Gap(),
                    _pair(
                      NumField(controller: _bags, label: 'عدد الشكاير (لو في)', onChanged: _changed),
                      NumField(controller: _bagWeight, label: 'وزن الشكارة الفاضية', suffix: 'كجم', onChanged: _changed),
                    ),
                  ] else ...[
                    if (!_sacksByTotal) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Icon(Icons.scale_outlined, color: AppColors.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _sackWeights.isEmpty
                                    ? 'لسه مكتبتش أوزان الشكاير'
                                    : '${intf(_sackWeights.length)} شكارة • ${qty(c.grossKg)} كجم',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Gap(8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => _editSacks(photo: false),
                              icon: const Icon(Icons.edit_note),
                              label: Text(_sackWeights.isEmpty ? 'اكتب وزن كل شكارة' : 'عدّل الأوزان'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => _editSacks(photo: true),
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('صوّر من الدفتر'),
                            ),
                          ),
                        ],
                      ),
                    ] else
                      _pair(
                        NumField(controller: _bags, label: 'عدد الشكاير', validator: positiveNumber, onChanged: _changed),
                        NumField(
                          controller: _gross,
                          label: 'الوزن الكلي',
                          suffix: 'كجم',
                          validator: positiveNumber,
                          onChanged: _changed,
                        ),
                      ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _sacksByTotal = !_sacksByTotal),
                        icon: Icon(_sacksByTotal ? Icons.list_alt : Icons.functions, size: 18),
                        label: Text(_sacksByTotal ? 'اكتب وزن كل شكارة لوحدها' : 'اكتب الإجمالي مرة واحدة بس'),
                      ),
                    ),
                    NumField(controller: _bagWeight, label: 'وزن الشكارة الفاضية (بيتخصم)', suffix: 'كجم', onChanged: _changed),
                  ],
                  const Gap(),
                  const Text('الخصومات بالكيلو', style: TextStyle(fontWeight: FontWeight.w700)),
                  const Gap(8),
                  _pair(
                    NumField(controller: _moisture, label: 'خصم رطوبة', suffix: 'كجم', onChanged: _changed),
                    NumField(controller: _impurities, label: 'خصم شوائب', suffix: 'كجم', onChanged: _changed),
                  ),
                  const Gap(),
                  NumField(controller: _otherDeduction, label: 'خصم تاني', suffix: 'كجم', onChanged: _changed),
                  const Gap(8),
                  const Divider(),
                  if (_mode == 'sacks') InfoRow('وزن الشكاير (${qty(c.bagsCount)})', '${qty(c.grossKg)} كجم'),
                  if (c.bagsKg > 0) InfoRow('خصم الشكاير الفاضية', '${qty(c.bagsKg)} كجم'),
                  if (c.qualityDeductionKg > 0) InfoRow('خصم الرطوبة والشوائب', '${qty(c.qualityDeductionKg)} كجم'),
                  if (c.otherDeductionKg > 0) InfoRow('خصم تاني', '${qty(c.otherDeductionKg)} كجم'),
                  InfoRow(
                    'الوزن الصافي',
                    unitsOf(c.netKg, unit, _kgPerUnit),
                    sub: _kgPerUnit == 1 ? null : '${qty(c.netKg)} كجم',
                    bold: true,
                    big: true,
                  ),
                ],
              ),
            ),
            _label('السعر'),
            Box(
              child: Column(
                children: [
                  NumField(
                    controller: _price,
                    label: 'سعر ال$unit',
                    suffix: currency,
                    validator: positiveNumber,
                    helper: _kgPerUnit > 1 && c.pricePerUnit > 0 ? 'سعر الكيلو: ${money(c.pricePerUnit / _kgPerUnit)}' : null,
                    onChanged: _changed,
                  ),
                  const Gap(8),
                  InfoRow('قيمة المحصول', egp(c.subtotal), bold: true, big: true),
                ],
              ),
            ),
            _label('المصاريف'),
            Box(
              child: Column(
                children: [
                  _pair(
                    NumField(controller: _freight, label: 'نولون', suffix: currency, onChanged: _changed),
                    NumField(controller: _loading, label: 'عتالة وتحميل', suffix: currency, onChanged: _changed),
                  ),
                  const Gap(),
                  NumField(controller: _otherExpenses, label: 'مصاريف أخرى', suffix: currency, onChanged: _changed),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _expensesOnParty,
                    onChanged: (v) => setState(() => _expensesOnParty = v),
                    title: Text(isSale ? 'المصاريف على التاجر' : 'المصاريف على الفلاح'),
                    subtitle: Text(
                      isSale ? 'تتضاف على حساب التاجر' : 'تتخصم من حساب الفلاح',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  if (c.expenses > 0)
                    const Text(
                      'المصاريف بتتدفع من الخزنة المختارة تحت.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                ],
              ),
            ),
            _label('الدفع'),
            Box(
              child: Column(
                children: [
                  PickField(
                    label: 'الخزنة',
                    value: _box == null ? null : '${s(_box!['name'])} (${egp(n(_box!['balance']))})',
                    icon: Icons.account_balance_wallet_outlined,
                    errorText: _submitted && _box == null && (c.paid > 0 || c.expenses > 0) ? 'اختار الخزنة' : null,
                    onTap: () async {
                      final b = await pickCashBox(context);
                      if (b != null) setState(() => _box = b);
                    },
                  ),
                  const Gap(),
                  Row(
                    children: [
                      Expanded(
                        child: NumField(
                          controller: _paid,
                          label: isSale ? 'المقبوض من التاجر الآن' : 'المدفوع للفلاح الآن',
                          suffix: currency,
                          onChanged: _changed,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => setState(() => _paid.text = numText(c.partyTotal)),
                        child: const Text('الكل'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Gap(16),
            Box(
              color: AppColors.cropsSoft,
              child: Column(
                children: [
                  InfoRow('صافي حساب ${isSale ? 'التاجر' : 'الفلاح'}', egp(c.partyTotal), bold: true, big: true),
                  InfoRow(isSale ? 'المقبوض' : 'المدفوع', egp(c.paid)),
                  if (c.remaining.abs() > 0.009)
                    InfoRow(
                      c.remaining > 0 ? (isSale ? 'الباقي على التاجر' : 'الباقي للفلاح') : 'مدفوع زيادة',
                      egp(c.remaining.abs()),
                      color: AppColors.bad,
                    ),
                  if (_party != null) InfoRow('رصيده بعد العملية', balanceInfo(after).text, color: balanceInfo(after).color),
                  if (!isSale && c.netKg > 0) InfoRow('تكلفة ال$unit علينا', egp(c.costPerKg * _kgPerUnit)),
                  if (isSale && c.netKg > 0 && _costPerKg > 0)
                    InfoRow(
                      'المكسب التقديري',
                      egp(c.netRevenue - c.stockKg * _costPerKg),
                      color: c.netRevenue - c.stockKg * _costPerKg >= 0 ? AppColors.good : AppColors.bad,
                    ),
                ],
              ),
            ),
            _label('بيانات إضافية'),
            TextF(controller: _ticket, label: 'رقم الكارتة / بون الميزان', icon: Icons.confirmation_number_outlined),
            const Gap(),
            TextF(controller: _vehicle, label: 'العربية / السواق', icon: Icons.local_shipping_outlined),
            const Gap(),
            TextF(controller: _notes, label: 'ملاحظات', maxLines: 3),
          ],
        ),
      ),
      bottomNavigationBar: SaveBar(onSave: _save, busy: _busy),
      ),
    );
  }
}
