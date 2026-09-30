import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/label_queue.dart';
import '../../core/util/format.dart';
import '../../data/calc.dart';
import '../../ui/pickers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../pos/barcode_scan.dart';

/// Add or edit a product. Pops with the saved row.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.id, this.barcode});

  final String? id;

  /// Barcode of a new product (scanned at the cashier).
  final String? barcode;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _barcode = TextEditingController();
  final _unit = TextEditingController(text: 'قطعة');
  final _cost = TextEditingController();
  final _profitPct = TextEditingController();
  final _retail = TextEditingController();
  final _wholesale = TextEditingController();
  final _minQty = TextEditingController();
  final _initialStock = TextEditingController();
  final _notes = TextEditingController();
  bool _active = true;
  bool _busy = false;
  String _saved = '';
  DbRow? _warehouse;
  List<String> _categories = const [];
  List<String> _brands = const [];

  static const _defaultCategories = [
    'ثلاجات',
    'غسالات',
    'بوتاجازات',
    'شاشات',
    'تكييفات',
    'سخانات',
    'مراوح',
    'أجهزة صغيرة',
    'أدوات مطبخ',
    'مفروشات',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final cats = await app.appliances.categories();
    final brands = await app.appliances.brands();
    _categories = {...cats, ..._defaultCategories}.toList();
    _brands = brands;
    // Load default warehouse for initial stock.
    final ws = await app.crops.warehouses();
    if (ws.isNotEmpty) _warehouse = ws.first;
    if (widget.barcode != null) _barcode.text = widget.barcode!;
    if (widget.id != null) {
      final p = await app.db.byId('products', widget.id);
      if (p != null) {
        _name.text = s(p['name']);
        _category.text = s(p['category']);
        _brand.text = s(p['brand']);
        _model.text = s(p['model']);
        _barcode.text = s(p['barcode']);
        _unit.text = s(p['unit']);
        _cost.text = numText(n(p['cost_price']));
        _retail.text = numText(n(p['retail_price']));
        _wholesale.text = numText(n(p['wholesale_price']));
        _minQty.text = numText(n(p['min_qty']));
        _notes.text = s(p['notes']);
        _active = n(p['active']) == 1;
      }
    } else {
      // New product: give it the next free number to print on its label.
      if (_barcode.text.isEmpty) {
        _barcode.text = await app.appliances.nextProductCode();
      }
      if (app.defaultProfitPct > 0) _profitPct.text = numText(app.defaultProfitPct);
    }
    _saved = _signature();
    if (mounted) setState(() {});
  }

  /// Everything typed on the form, to tell a touched form from an untouched
  /// one without watching every field.
  String _signature() => [
        _name.text, _category.text, _brand.text, _model.text, _barcode.text, _unit.text,
        _cost.text, _profitPct.text, _retail.text, _wholesale.text, _minQty.text,
        _initialStock.text, _notes.text, '$_active',
      ].join('|');

  bool get _dirty => !_busy && _signature() != _saved;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final code = normalizeDigits(_barcode.text.trim());
    if (code.isNotEmpty) {
      final other = await app.appliances.productByBarcode(code);
      if (!mounted) return;
      if (other != null && other['id'] != widget.id) {
        toast(context, 'الباركود ده متسجل على صنف تاني: ${s(other['name'])}', error: true);
        return;
      }
    }
    setState(() => _busy = true);
    final id = await app.appliances.saveProduct({
      'name': _name.text.trim(),
      'category': _category.text.trim(),
      'brand': _brand.text.trim(),
      'model': _model.text.trim(),
      'barcode': normalizeDigits(_barcode.text.trim()),
      'unit': _unit.text.trim().isEmpty ? 'قطعة' : _unit.text.trim(),
      'cost_price': parseNum(_cost.text),
      'retail_price': parseNum(_retail.text),
      'wholesale_price': parseNum(_wholesale.text),
      'min_qty': parseNum(_minQty.text),
      'notes': _notes.text.trim(),
      'active': _active,
    }, id: widget.id);
    final initQty = parseNum(_initialStock.text);
    if (widget.id == null && initQty > 0 && _warehouse != null) {
      await app.crops.saveStockMove({
        'kind': 'adjust',
        'date': todayStr(),
        'item_type': 'product',
        'item_id': id,
        'warehouse_id': _warehouse!['id'],
        'qty': initQty,
        'notes': 'رصيد أول المدة',
      });
    }

    // A new product needs a sticker on the box, so it goes into the labels
    // list by itself — wherever it was added from (المخزن، الكاشير، من جوه
    // الفاتورة). One label for every piece that came in.
    if (widget.id == null) {
      await LabelQueue.add(id, initQty >= 1 ? initQty.round() : 1);
    }

    final row = await app.appliances.product(id);
    if (!mounted) return;
    if (widget.id == null) {
      toast(context, 'اتسجل الصنف، وهتلاقيه في قايمة ملصقات الأسعار');
    }
    Navigator.pop(context, row);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: 'حذف الصنف', message: 'حذف "${_name.text}"؟', ok: 'حذف', danger: true);
    if (!ok) return;
    final err = await app.appliances.deleteProduct(widget.id!);
    if (!mounted) return;
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    // The form is gone with the product, so the unsaved-work guard must not
    // stand in the way of leaving it.
    setState(() => _busy = true);
    Navigator.of(context)
      ..pop()
      ..maybePop();
  }

  /// "مكسب 350 (23%)" under a selling price.
  String? _margin(TextEditingController price) {
    final cost = parseNum(_cost.text), p = parseNum(price.text);
    if (cost <= 0 || p <= 0) return null;
    return 'مكسب ${money(p - cost)} (${intf(((p - cost) / cost * 100).round())}%)';
  }

  /// Typing a margin fills the selling price, rounded up to the shop's step.
  void _onProfitPctChanged(String v) {
    final pct = parseNum(v);
    final cost = parseNum(_cost.text);
    if (pct > 0 && cost > 0) {
      _retail.text = numText(ceilToStep(cost * (1 + pct / 100), app.priceStep));
    }
    setState(() {});
  }

  Widget _suggestions(List<String> items, TextEditingController c) => items.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final x in items)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ActionChip(
                      label: Text(x),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => c.text = x),
                    ),
                  ),
              ],
            ),
          ),
        );

  @override
  Widget build(BuildContext context) => UnsavedGuard(
        dirty: () => _dirty,
        message: 'بيانات الصنف اللي كتبتها هتضيع من غير حفظ.',
        child: Scaffold(
        appBar: AppBar(
          title: Text(widget.id == null ? 'صنف جديد' : 'تعديل الصنف'),
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
              TextF(controller: _name, label: 'اسم الصنف', validator: requiredText, hint: 'مثلاً: ثلاجة 16 قدم نوفروست'),
              const Gap(),
              TextF(controller: _category, label: 'القسم'),
              _suggestions(_categories, _category),
              const Gap(),
              Row(
                children: [
                  Expanded(child: TextF(controller: _brand, label: 'الماركة')),
                  const SizedBox(width: 10),
                  Expanded(child: TextF(controller: _model, label: 'الموديل')),
                ],
              ),
              _suggestions(_brands, _brand),
              const Gap(),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextF(
                      controller: _barcode,
                      label: 'رقم الصنف (الكود)',
                      keyboard: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      helper: 'بيتطبع باركود على الملصق ويتقرا بالقارئ',
                    ),
                  ),
                  IconButton(
                    tooltip: 'امسح كود موجود بالكاميرا',
                    onPressed: () async {
                      final code = await scanBarcode(context);
                      if (code != null) setState(() => _barcode.text = code);
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                  Expanded(flex: 2, child: TextF(controller: _unit, label: 'الوحدة')),
                ],
              ),
              const Gap(16),
              Box(
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: NumField(
                            controller: _cost,
                            label: 'سعر الشراء (التكلفة)',
                            suffix: currency,
                            onChanged: (_) {
                              _onProfitPctChanged(_profitPct.text);
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: NumField(
                            controller: _profitPct,
                            label: 'نسبة المكسب',
                            suffix: '%',
                            helper: 'يحسب البيع',
                            onChanged: _onProfitPctChanged,
                          ),
                        ),
                      ],
                    ),
                    const Gap(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: NumField(
                            controller: _retail,
                            label: 'سعر القطاعي',
                            suffix: currency,
                            helper: _margin(_retail),
                            onChanged: (_) => setState(() => _profitPct.clear()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: NumField(
                            controller: _wholesale,
                            label: 'سعر الجملة',
                            suffix: currency,
                            helper: _margin(_wholesale),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(),
              NumField(controller: _minQty, label: 'حد الطلب (نبهني لما المخزون يوصل)', helper: 'سيبه فاضي لو مش عايز تنبيه'),
              if (widget.id == null) ...[
                const Gap(16),
                Box(
                  color: AppColors.goodSoft,
                  child: Column(
                    children: [
                      NumField(
                        controller: _initialStock,
                        label: 'الكمية الموجودة في المخزن حالياً',
                        helper: 'سيبه فاضي لو مفيش رصيد أول',
                      ),
                      const Gap(),
                      PickField(
                        label: 'المخزن',
                        value: _warehouse == null ? null : s(_warehouse!['name']),
                        icon: Icons.warehouse_outlined,
                        onTap: () async {
                          final w = await pickWarehouse(context);
                          if (w != null) setState(() => _warehouse = w);
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const Gap(),
              TextF(controller: _notes, label: 'ملاحظات', maxLines: 2),
              if (widget.id != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('صنف شغال'),
                  subtitle: const Text('الأصناف الموقوفة مش بتظهر في الفواتير'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              const Gap(8),
              Text(
                widget.id == null
                    ? 'المخزون بعد كده بيتحسب لوحده من فواتير الشراء والبيع والكاشير.'
                    : 'علشان تغير الكمية الموجودة، افتح الصنف ودوس "تعديل الكمية".',
                style: const TextStyle(color: AppColors.muted, height: 1.5, fontSize: 13),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SaveBar(onSave: _save, busy: _busy),
        ),
      );
}
