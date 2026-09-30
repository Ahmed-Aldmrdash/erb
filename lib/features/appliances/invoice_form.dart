import 'package:flutter/material.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/label_queue.dart';
import '../../core/util/format.dart';
import '../../data/appliances_repo.dart';
import '../../data/calc.dart';
import '../../data/labels.dart';
import '../../ui/pickers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'invoice_detail.dart';
import 'price_update_sheet.dart';

/// Sale, purchase and return invoices of the appliances division. Sales can
/// be cash, on account (آجل) or installments with a down payment, markup,
/// monthly schedule and guarantor.
class InvoiceForm extends StatefulWidget {
  const InvoiceForm({
    super.key,
    required this.kind,
    this.id,
    this.returnOfId,
    this.initialLines,
    this.initialPartyId,
    this.initialPriceLevel,
    this.initialPaymentType,
    this.initialDiscount,
    this.onSaved,
  });

  final String kind;
  final String? id;

  /// Pre-fill a return from this invoice.
  final String? returnOfId;

  /// A new invoice started somewhere else (e.g. an installment sale from the
  /// cashier's cart).
  final List<InvoiceLineDraft>? initialLines;
  final String? initialPartyId;
  final String? initialPriceLevel;
  final String? initialPaymentType;
  final double? initialDiscount;

  /// Called once the invoice is written. Whoever opened the form (the
  /// cashier) holds on to what it sent until then, so going back loses
  /// nothing.
  final VoidCallback? onSaved;

  @override
  State<InvoiceForm> createState() => _InvoiceFormState();
}

class _InvoiceFormState extends State<InvoiceForm> {
  final _form = GlobalKey<FormState>();
  final _customerName = TextEditingController();
  final _discount = TextEditingController();
  final _paid = TextEditingController();
  final _markupPct = TextEditingController();
  final _months = TextEditingController(text: '12');
  final _guarantorName = TextEditingController();
  final _guarantorPhone = TextEditingController();
  final _notes = TextEditingController();

  String _date = todayStr();
  String _firstDue = dateStr(addMonths(DateTime.now(), 1));
  DbRow? _party;
  double _partyBalance = 0;
  DbRow? _warehouse;
  DbRow? _box;
  String _priceLevel = 'retail';
  late String _paymentType = 'cash';
  final List<InvoiceLineDraft> _lines = [];
  final Map<String, double> _stock = {};
  String? _refInvoiceId;
  String? _origPartyId;
  double _origPartyEffect = 0;
  bool _showSchedule = false;
  bool _submitted = false;
  bool _busy = false;

  final FlutterNativeContactPicker _contactPicker = FlutterNativeContactPicker();

  String get kind => widget.kind;
  bool get isSale => kind == 'sale';
  bool get isReturn => kind.endsWith('return');

  /// Lines leave the warehouse (need stock).
  bool get isOutgoing => kind == 'sale' || kind == 'purchase_return';

  /// Priced with the purchase cost instead of the selling price.
  bool get usesCost => kind == 'purchase' || kind == 'purchase_return';
  bool get isInstallment => isSale && _paymentType == 'installment';

  Map<String, String> get _paymentOptions => switch (kind) {
        'sale' => const {'cash': 'كاش', 'credit': 'آجل', 'installment': 'تقسيط'},
        'purchase' => const {'cash': 'كاش', 'credit': 'آجل'},
        _ => const {'cash': 'رد نقدي', 'credit': 'خصم من الحساب'},
      };

  double get _subtotal => roundMoney(_lines.fold<double>(0, (a, l) => a + l.total));
  double get _total => InvoiceTotals(subtotal: _subtotal, discount: parseNum(_discount.text)).total;

  InstallmentPlan get _plan => InstallmentPlan(
        total: _total,
        downPayment: parseNum(_paid.text),
        markupPct: parseNum(_markupPct.text),
        months: parseNum(_months.text).round(),
        firstDue: parseDate(_firstDue) ?? DateTime.now(),
      );

  double get _grandTotal => isInstallment ? _plan.grandTotal : _total;
  double get _paidNow => _paymentType == 'cash' ? _grandTotal : roundMoney(parseNum(_paid.text));

  /// Change of the party balance (+: owes us more).
  double get _effect {
    final g = _grandTotal, p = _paidNow;
    return (kind == 'sale' || kind == 'purchase_return') ? g - p : p - g;
  }

  String get _title => switch (kind) {
        'sale' => 'فاتورة بيع',
        'purchase' => 'فاتورة شراء',
        'sale_return' => 'مرتجع بيع',
        _ => 'مرتجع شراء',
      };

  @override
  void initState() {
    super.initState();
    _markupPct.text = app.settings['default_markup_pct'] ?? '';
    _init();
  }

  Future<void> _init() async {
    final warehouses = await app.crops.warehouses();
    if (warehouses.isNotEmpty) _warehouse = warehouses.first;
    _box = await app.accounts.defaultCashBox();
    if (widget.id != null) {
      await _loadInvoice(widget.id!, editing: true);
    } else if (widget.returnOfId != null) {
      await _loadInvoice(widget.returnOfId!, editing: false);
      _refInvoiceId = widget.returnOfId;
      _paymentType = 'credit';
    } else {
      if (widget.initialLines != null) _lines.addAll(widget.initialLines!);
      if (widget.initialPriceLevel != null) _priceLevel = widget.initialPriceLevel!;
      if (widget.initialPaymentType != null) _paymentType = widget.initialPaymentType!;
      if ((widget.initialDiscount ?? 0) > 0) _discount.text = numText(widget.initialDiscount);
      if (widget.initialPartyId != null) await _setParty(widget.initialPartyId!);
    }
    await _refreshStock();
    if (mounted) setState(() {});
  }

  Future<void> _loadInvoice(String id, {required bool editing}) async {
    final inv = await app.appliances.invoice(id);
    if (inv == null) return;
    final lines = await app.appliances.invoiceLines(id);
    _lines
      ..clear()
      ..addAll([
        for (final l in lines)
          InvoiceLineDraft(
            productId: s(l['product_id']),
            name: s(l['product_name']),
            unit: s(l['unit']),
            qty: n(l['qty']),
            price: n(l['price']),
            notes: s(l['notes']),
          ),
      ]);
    _warehouse = await app.db.byId('warehouses', s(inv['warehouse_id'])) ?? _warehouse;
    _customerName.text = s(inv['customer_name']);
    _priceLevel = s(inv['price_level']);
    if (!editing) {
      if (inv['party_id'] != null) await _setParty(s(inv['party_id']));
      return;
    }
    _date = s(inv['date']);
    _paymentType = s(inv['payment_type']);
    _discount.text = numText(n(inv['discount']));
    _paid.text = numText(n(inv['paid_amount']));
    _markupPct.text = numText(n(inv['markup_pct']));
    if (ni(inv['inst_months']) > 0) _months.text = '${ni(inv['inst_months'])}';
    if (s(inv['inst_first_due']).isNotEmpty) _firstDue = s(inv['inst_first_due']);
    _guarantorName.text = s(inv['guarantor_name']);
    _guarantorPhone.text = s(inv['guarantor_phone']);
    _notes.text = s(inv['notes']);
    _refInvoiceId = inv['ref_invoice_id'] as String?;
    final box = await app.accounts.cashBox(s(inv['cash_box_id']));
    if (box != null) _box = box;
    if (inv['party_id'] != null) {
      _origPartyId = s(inv['party_id']);
      final g = n(inv['grand_total']), p = n(inv['paid_amount']);
      _origPartyEffect = (kind == 'sale' || kind == 'purchase_return') ? g - p : p - g;
      await _setParty(_origPartyId!);
    }
  }

  Future<void> _setParty(String id) async {
    final p = await app.accounts.party(id);
    _party = p;
    _partyBalance = n(p?['balance']);
    if (id == _origPartyId) _partyBalance -= _origPartyEffect;
    if (mounted) setState(() {});
  }

  Future<void> _refreshStock() async {
    _stock.clear();
    for (final l in _lines) {
      _stock[l.productId] = await app.appliances.stockAt(
        l.productId,
        _warehouse?['id'] as String?,
        excludeInvoiceId: widget.id,
      );
    }
    if (mounted) setState(() {});
  }

  double _priceOf(DbRow product) => usesCost
      ? n(product['cost_price'])
      : n(product[_priceLevel == 'wholesale' ? 'wholesale_price' : 'retail_price']);

  Future<void> _addLine() async {
    final boughtBy = widget.kind == 'sale_return' && _party != null ? s(_party!['id']) : null;
    final p = await pickProduct(context, priceLevel: _priceLevel, forPurchase: usesCost, boughtBy: boughtBy);
    if (p == null || !mounted) return;
    final available = await app.appliances.stockAt(s(p['id']), _warehouse?['id'] as String?, excludeInvoiceId: widget.id);
    // Block adding out-of-stock products to sale invoices.
    if (isOutgoing && available <= 0) {
      if (mounted) toast(context, 'الصنف "${s(p['name'])}" خلصان من المخزن. مينفعش يتباع.', error: true);
      return;
    }
    final existing = _lines.where((l) => l.productId == p['id']).firstOrNull;
    final line = existing ??
        InvoiceLineDraft(
          productId: s(p['id']),
          name: s(p['name']),
          unit: s(p['unit']),
          qty: 1,
          price: _priceOf(p),
        );
    _stock[line.productId] = available;
    if (!mounted) return;
    final edited = await _editLine(line, isNew: existing == null);
    if (edited == null) return;
    setState(() {
      if (existing == null) _lines.add(edited);
    });
  }

  Future<InvoiceLineDraft?> _editLine(InvoiceLineDraft line, {bool isNew = false}) async {
    final q = TextEditingController(text: numText(line.qty));
    final pr = TextEditingController(text: numText(line.price));
    final sell = TextEditingController(text: line.sellPrice == null ? '' : numText(line.sellPrice));
    final notes = TextEditingController(text: line.notes);
    final available = _stock[line.productId];
    // What the showroom sells it for today, to show under the selling price
    // box: for goods that have been here since before anybody wrote down
    // what they cost, there is no old margin to work from.
    final product = kind == 'purchase' ? await app.db.byId('products', line.productId) : null;
    final oldRetail = n(product?['retail_price']);
    final oldCost = n(product?['cost_price']);
    if (!mounted) return null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) {
          final total = roundMoney(parseNum(q.text) * parseNum(pr.text));
          final over = isOutgoing && available != null && parseNum(q.text) > available;
          return AlertDialog(
            title: Text(line.name),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (available != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'المتاح في المخزن: ${qty(available)} ${line.unit}',
                        style: TextStyle(color: over ? AppColors.bad : AppColors.muted),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: NumField(controller: q, label: 'الكمية', autofocus: true, onChanged: (_) => setState(() {})),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: NumField(controller: pr, label: 'السعر', suffix: currency, onChanged: (_) => setState(() {})),
                      ),
                    ],
                  ),
                  if (kind == 'purchase') ...[
                    const Gap(),
                    NumField(
                      controller: sell,
                      label: 'سعر البيع بعد الشراء (اختياري)',
                      suffix: currency,
                      onChanged: (_) => setState(() {}),
                      helper: _sellHelp(
                        typed: parseNum(sell.text),
                        cost: parseNum(pr.text),
                        oldRetail: oldRetail,
                        oldCost: oldCost,
                      ),
                    ),
                  ],
                  const Gap(),
                  TextF(controller: notes, label: 'سيريال / ملاحظات'),
                  const Gap(),
                  InfoRow('الإجمالي', egp(total), bold: true),
                  if (over)
                    const Text('الكمية أكبر من المتاح في المخزن', style: TextStyle(color: AppColors.bad)),
                ],
              ),
            ),
            actions: [
              if (!isNew)
                TextButton(
                  onPressed: () {
                    this.setState(() => _lines.remove(line));
                    Navigator.pop(c, false);
                  },
                  child: const Text('حذف', style: TextStyle(color: AppColors.bad)),
                ),
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
              FilledButton(
                onPressed: parseNum(q.text) > 0 ? () => Navigator.pop(c, true) : null,
                child: const Text('تمام'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return null;
    line
      ..qty = parseNum(q.text)
      ..price = parseNum(pr.text)
      ..sellPrice = parseNum(sell.text) > 0 ? parseNum(sell.text) : null
      ..notes = notes.text.trim();
    setState(() {});
    return line;
  }

  /// The line under the selling price box: what it means to leave it empty,
  /// which depends on whether the old purchase price is known.
  String _sellHelp({
    required double typed,
    required double cost,
    required double oldRetail,
    required double oldCost,
  }) {
    if (typed > 0) {
      return cost > 0 && typed > cost ? 'مكسب ${money(typed - cost)}' : 'أقل من سعر الشراء!';
    }
    if (oldRetail <= 0) return 'مفيش سعر بيع مسجل. اكتبه هنا.';
    if (oldCost <= 0) {
      return 'السعر الحالي ${money(oldRetail)}. مفيش سعر شراء قديم، فسيبه فاضي يفضل زي ما هو.';
    }
    return 'سيبه فاضي وسعر البيع هيزيد بنفس النسبة (دلوقتي ${money(oldRetail)}).';
  }

  Future<void> _changePriceLevel(String level) async {
    setState(() => _priceLevel = level);
    for (final l in _lines) {
      final p = await app.db.byId('products', l.productId);
      if (p != null) l.price = _priceOf(p);
    }
    if (mounted) setState(() {});
  }

  bool get _needsParty => _paymentType != 'cash';

  Future<void> _pickGuarantorContact() async {
    try {
      final contact = await _contactPicker.selectContact();
      if (contact != null) {
        setState(() {
          if (contact.phoneNumbers != null && contact.phoneNumbers!.isNotEmpty) {
            _guarantorPhone.text = contact.phoneNumbers!.first;
          }
          if (_guarantorName.text.isEmpty && contact.fullName != null) {
            _guarantorName.text = contact.fullName!;
          }
        });
      }
    } catch (e) {
      if (mounted) toast(context, 'حصل مشكلة في فتح جهات الاتصال', error: true);
    }
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!_form.currentState!.validate()) return;
    if (_lines.isEmpty) {
      toast(context, 'ضيف صنف واحد على الأقل', error: true);
      return;
    }
    if (_needsParty && _party == null) {
      toast(context, 'اختار ${usesCost ? 'المورد' : 'العميل'} (مطلوب في ${paymentTypes[_paymentType]})', error: true);
      return;
    }
    if (_warehouse == null) {
      toast(context, 'اختار المخزن', error: true);
      return;
    }
    if (_paidNow > 0 && _box == null) {
      toast(context, 'اختار الخزنة', error: true);
      return;
    }
    if (isInstallment && (_plan.months <= 0 || _plan.toCollect <= 0)) {
      toast(context, 'راجع بيانات التقسيط (عدد الشهور والمقدم)', error: true);
      return;
    }
    if (isOutgoing) {
      final short = _lines.where((l) => l.qty > (_stock[l.productId] ?? 0) + 0.0001).toList();
      if (short.isNotEmpty) {
        toast(
          context,
          'مينفعش تبيع أصناف مش موجودة في المخزن:\n${short.map((l) => '${l.name}: المتاح ${qty(_stock[l.productId] ?? 0)}').join('\n')}',
          error: true,
        );
        return;
      }
    }
    // A purchase teaches the showroom the new cost: the selling prices follow
    // it by the same ratio, and the user sees them before anything is saved.
    var priceUpdates = const <PriceUpdate>[];
    if (kind == 'purchase') {
      final suggested = await app.appliances.suggestPriceUpdates(
        _lines,
        step: app.priceStep,
        marginPct: app.defaultProfitPct,
      );
      if (!mounted) return;
      if (suggested.isNotEmpty) {
        final confirmed = await showPriceUpdateSheet(context, suggested);
        if (!mounted) return;
        if (confirmed == null) return; // cancelled: nothing saved
        priceUpdates = confirmed;
      }
    }
    setState(() => _busy = true);
    final plan = _plan;
    final header = <String, Object?>{
      'kind': kind,
      'date': _date,
      'party_id': _party?['id'],
      'customer_name': _party == null ? _customerName.text.trim() : null,
      'warehouse_id': _warehouse!['id'],
      'cash_box_id': _box?['id'],
      'price_level': _priceLevel,
      'payment_type': _paymentType,
      'subtotal': _subtotal,
      'discount': roundMoney(parseNum(_discount.text)),
      'total': _total,
      'markup_pct': isInstallment ? plan.markupPct : 0,
      'markup_amount': isInstallment ? plan.markup : 0,
      'grand_total': _grandTotal,
      'paid_amount': _paidNow,
      'inst_months': isInstallment ? plan.months : 0,
      'inst_first_due': isInstallment ? _firstDue : null,
      'guarantor_name': isInstallment ? _guarantorName.text.trim() : null,
      'guarantor_phone': isInstallment ? normalizeDigits(_guarantorPhone.text.trim()) : null,
      'ref_invoice_id': _refInvoiceId,
      'notes': _notes.text.trim(),
    };
    final String id;
    try {
      id = await app.appliances.saveInvoice(
        header: header,
        lines: _lines,
        schedule: isInstallment ? plan.schedule : const [],
        priceUpdates: priceUpdates,
        id: widget.id,
      );
    } on OutOfStock catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _refreshStock();
      if (mounted) toast(context, e.toString(), error: true);
      return;
    }
    // Goods that just arrived need stickers with today's price, one for every
    // piece, without anybody having to go and ask for them.
    if (kind == 'purchase' && widget.id == null) {
      for (final l in _lines) {
        await LabelQueue.add(l.productId, l.qty >= 1 ? l.qty.round() : 1);
      }
    }
    widget.onSaved?.call();
    if (!mounted) return;
    if (widget.id == null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, justSaved: true)));
    } else {
      Navigator.pop(context);
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(text, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final after = _partyBalance + _effect;
    final partyLabel = usesCost ? 'المورد' : 'العميل';
    return Scaffold(
      appBar: AppBar(title: Text(widget.id == null ? _title : 'تعديل $_title')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            DateField(label: 'التاريخ', value: _date, onChanged: (v) => setState(() => _date = v)),
            const Gap(),
            Choice<String>(
              options: _paymentOptions,
              value: _paymentType,
              onChanged: (v) => setState(() => _paymentType = v),
            ),
            const Gap(),
            PickField(
              label: _needsParty ? partyLabel : '$partyLabel (اختياري في الكاش)',
              value: _party == null ? null : s(_party!['name']),
              icon: Icons.person_outline,
              errorText: _submitted && _needsParty && _party == null ? 'مطلوب' : null,
              helper: _party == null ? null : 'رصيده الحالي: ${balanceInfo(_partyBalance).text}',
              onTap: () async {
                final p = await pickParty(
                  context,
                  title: 'اختار $partyLabel',
                  preferKinds: usesCost ? const ['supplier'] : const ['customer'],
                  newKind: usesCost ? 'supplier' : 'customer',
                );
                if (p != null) await _setParty(s(p['id']));
              },
              onClear: _needsParty
                  ? null
                  : () => setState(() {
                        _party = null;
                        _partyBalance = 0;
                      }),
            ),
            if (_party == null && !_needsParty) ...[
              const Gap(),
              TextF(controller: _customerName, label: 'اسم ${partyLabel == 'العميل' ? 'الزبون' : 'المورد'} (اختياري)'),
            ],
            const Gap(),
            PickField(
              label: 'المخزن',
              value: _warehouse == null ? null : s(_warehouse!['name']),
              icon: Icons.warehouse_outlined,
              onTap: () async {
                final w = await pickWarehouse(context);
                if (w == null) return;
                setState(() => _warehouse = w);
                await _refreshStock();
              },
            ),
            if (isSale) ...[
              const Gap(),
              Choice<String>(options: priceLevels, value: _priceLevel, onChanged: _changePriceLevel),
            ],
            _label('الأصناف'),
            Box(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final l in _lines)
                    ListTile(
                      title: Text(l.name),
                      subtitle: Text(
                        '${qty(l.qty)} × ${money(l.price)}${l.notes.isNotEmpty ? ' • ${l.notes}' : ''}'
                        '${isOutgoing && l.qty > (_stock[l.productId] ?? double.infinity) ? '\nالمتاح ${qty(_stock[l.productId] ?? 0)} بس' : ''}',
                        style: TextStyle(
                          color: isOutgoing && l.qty > (_stock[l.productId] ?? double.infinity) ? AppColors.bad : null,
                        ),
                      ),
                      trailing: Text(egp(l.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => _editLine(l),
                    ),
                  if (_lines.isNotEmpty) const Divider(),
                  TextButton.icon(
                    onPressed: _addLine,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('إضافة صنف'),
                  ),
                ],
              ),
            ),
            if (_submitted && _lines.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('ضيف صنف واحد على الأقل', style: TextStyle(color: AppColors.bad)),
              ),
            _label('الحساب'),
            Box(
              child: Column(
                children: [
                  InfoRow('الإجمالي', egp(_subtotal)),
                  const Gap(6),
                  NumField(controller: _discount, label: 'خصم', suffix: currency, onChanged: (_) => setState(() {})),
                  const Gap(6),
                  InfoRow('الصافي', egp(_total), bold: true, big: true),
                ],
              ),
            ),
            if (isInstallment) ..._installmentSection(plan),
            _label('الدفع'),
            Box(
              child: Column(
                children: [
                  if (isInstallment)
                    InfoRow('المقدم', egp(_paidNow), bold: true)
                  else if (_paymentType != 'cash') ...[
                    NumField(
                      controller: _paid,
                      label: isReturn ? 'المبلغ المردود نقدي' : 'المدفوع الآن',
                      suffix: currency,
                      onChanged: (_) => setState(() {}),
                    ),
                    const Gap(),
                  ] else
                    InfoRow(
                      kind == 'sale' || kind == 'purchase_return' ? 'المقبوض' : 'المدفوع',
                      egp(_paidNow),
                      bold: true,
                    ),
                  if (_paidNow > 0)
                    PickField(
                      label: 'الخزنة',
                      value: _box == null ? null : s(_box!['name']),
                      icon: Icons.account_balance_wallet_outlined,
                      errorText: _submitted && _box == null ? 'اختار الخزنة' : null,
                      onTap: () async {
                        final b = await pickCashBox(context);
                        if (b != null) setState(() => _box = b);
                      },
                    ),
                  if (_party != null) ...[
                    const Gap(8),
                    InfoRow('رصيد $partyLabel بعد الفاتورة', balanceInfo(after).text, color: balanceInfo(after).color),
                  ],
                ],
              ),
            ),
            const Gap(),
            TextF(controller: _notes, label: 'ملاحظات', maxLines: 2),
          ],
        ),
      ),
      bottomNavigationBar: SaveBar(onSave: _save, busy: _busy, label: 'حفظ ${egp(_grandTotal)}'),
    );
  }

  List<Widget> _installmentSection(InstallmentPlan plan) {
    final schedule = plan.schedule;
    return [
      _label('التقسيط'),
      Box(
        color: AppColors.appliancesSoft,
        child: Column(
          children: [
            NumField(controller: _paid, label: 'المقدم', suffix: currency, onChanged: (_) => setState(() {})),
            const Gap(),
            Row(
              children: [
                Expanded(child: NumField(controller: _markupPct, label: 'نسبة الزيادة', suffix: '%', onChanged: (_) => setState(() {}))),
                const SizedBox(width: 10),
                Expanded(child: NumField(controller: _months, label: 'عدد الشهور', onChanged: (_) => setState(() {}))),
              ],
            ),
            const Gap(),
            DateField(label: 'تاريخ أول قسط', value: _firstDue, onChanged: (v) => setState(() => _firstDue = v)),
            const Gap(),
            TextF(controller: _guarantorName, label: 'اسم الضامن (اختياري)', icon: Icons.shield_outlined),
            const Gap(),
            TextF(
              controller: _guarantorPhone,
              label: 'تليفون الضامن',
              icon: Icons.phone_outlined,
              keyboard: TextInputType.phone,
              suffixIcon: IconButton(
                icon: Icon(Icons.contacts_outlined, color: AppColors.primary),
                onPressed: _pickGuarantorContact,
                tooltip: 'اختيار من جهات الاتصال',
              ),
            ),
            const Gap(8),
            const Divider(),
            InfoRow('المبلغ المقسط (بعد المقدم)', egp(plan.financed)),
            InfoRow('قيمة الزيادة', egp(plan.markup)),
            InfoRow('إجمالي الأقساط', egp(plan.toCollect), bold: true),
            if (schedule.isNotEmpty) InfoRow('القسط الشهري', egp(schedule.first.amount), bold: true, big: true),
            InfoRow('إجمالي الفاتورة بالتقسيط', egp(plan.grandTotal)),
            if (schedule.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => _showSchedule = !_showSchedule),
                child: Text(_showSchedule ? 'إخفاء جدول الأقساط' : 'عرض جدول الأقساط'),
              ),
            if (_showSchedule)
              for (final it in schedule)
                InfoRow('القسط ${it.seq} - ${showDate(dateStr(it.dueDate))}', egp(it.amount)),
          ],
        ),
      ),
    ];
  }
}
