import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/appliances_repo.dart';
import '../../data/labels.dart';
import '../../data/permissions.dart';
import '../../ui/pickers.dart';
import '../../ui/share.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../appliances/invoice_detail.dart';
import '../appliances/invoice_form.dart';
import '../appliances/product_detail.dart';
import '../appliances/product_form.dart';
import '../appliances/quick_edit.dart';
import '../common/pdf_docs.dart';
import '../settings/sync_screen.dart';
import 'barcode_scan.dart';
import 'pos_cart.dart';

/// الكاشير: quick retail sales. Tap products (or scan their barcode) to fill
/// the basket, take the money, done — stock goes down automatically.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final cart = PosCart.instance;
  final _searchCtrl = TextEditingController();

  /// A barcode reader types the code then Enter. When the user is writing in
  /// the search box the box gets it; otherwise [_scannerKeys] picks it up.
  final _searchFocus = FocusNode();
  final _scannerFocus = FocusNode();
  String _search = '';
  String _category = '';

  /// What a reader has typed so far, and when the last key came in.
  String _typed = '';
  DateTime _lastKey = DateTime.now();

  @override
  void initState() {
    super.initState();
    // A basket left open on this phone (even after the app was closed).
    cart.restore();
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _scannerFocus.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Keys that nothing else took: only a reader types this fast, so a person
  /// pressing keys by accident never turns into a sale.
  KeyEventResult _scannerKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _searchFocus.hasFocus) return KeyEventResult.ignored;
    final now = DateTime.now();
    if (now.difference(_lastKey).inMilliseconds > 120) _typed = '';
    _lastKey = now;
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _typed;
      _typed = '';
      if (code.length >= 3) {
        _onCode(code);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final ch = event.character;
    if (ch == null || ch.trim().isEmpty) return KeyEventResult.ignored;
    _typed += ch;
    return KeyEventResult.handled;
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    await _onCode(code);
  }

  /// A code from the camera, from a barcode reader, or typed by hand: the
  /// product number on its own, or a whole label (number + price).
  Future<void> _onCode(String code) async {
    final clean = normalizeDigits(code.trim());
    if (clean.isEmpty) return;
    final hit = await app.appliances.productByScan(clean);
    if (!mounted) return;
    if (hit != null) {
      setState(() {
        _searchCtrl.clear();
        _search = '';
      });
      _addToCart(hit.product);
      // The box is still carrying a label from before the price changed.
      final onLabel = hit.labelPrice;
      final now = cart.priceOf(hit.product);
      if (onLabel != null && (onLabel - now).abs() > 0.009 && mounted) {
        toast(context, 'الملصق مكتوب عليه ${money(onLabel)} والسعر دلوقتي ${money(now)}. اطبعله ملصق جديد.');
      }
      _searchFocus.requestFocus();
      return;
    }
    // Not a code we know. Registering it is the storekeeper's job, so a
    // cashier is only told that the code is not in yet.
    if (!app.can(Perm.stock)) {
      toast(context, 'الكود $clean مش متسجل على أي صنف. قول للمسؤول عن المخزن.', error: true);
      return;
    }
    final add = await confirmDialog(
      context,
      title: 'مفيش صنف بالكود ده',
      message: 'الكود $clean مش متسجل على أي صنف. تضيفه صنف جديد؟',
      ok: 'إضافة صنف',
    );
    if (!add || !mounted) return;
    final row = await push<DbRow>(context, ProductFormScreen(barcode: clean));
    if (row != null && mounted) {
      setState(() {
        _searchCtrl.clear();
        _search = '';
      });
      _addToCart(row);
    }
  }

  /// One tap sells one piece at the price set on the product.
  void _addToCart(DbRow product) {
    final left = n(product['stock']) - cart.qtyOf(s(product['id']));
    if (left <= 0) {
      toast(context, 'الصنف "${s(product['name'])}" خلصان من المخزن', error: true);
      return;
    }
    cart.add(product);
    HapticFeedback.lightImpact();
  }

  /// Long press: quantity and price of this line before it goes in.
  Future<void> _openProductSheet(DbRow product) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductSheet(product: product),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _scannerFocus,
        onKeyEvent: _scannerKeys,
        autofocus: true,
        child: Scaffold(
        appBar: AppBar(
          title: const Text('الكاشير'),
          actions: [
            IconButton(tooltip: 'قراءة باركود', onPressed: _scan, icon: const Icon(Icons.qr_code_scanner)),
            const SyncButton(),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                // A barcode reader types the number then Enter.
                onSubmitted: _onCode,
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'دور بالاسم أو الموديل، أو امسح الباركود',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () => setState(() {
                            _searchCtrl.clear();
                            _search = '';
                          }),
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            DbBuilder<List<String>>(
              query: app.appliances.categories,
              builder: (context, cats) => cats.isEmpty
                  ? const SizedBox.shrink()
                  : ChipsBar<String>(
                      options: {'': 'الكل', for (final c in cats) c: c},
                      value: _category,
                      onChanged: (v) => setState(() => _category = v),
                    ),
            ),
            Expanded(
              child: DbBuilder<List<DbRow>>(
                queryKey: (_search, _category),
                query: () => app.appliances.products(search: _search, category: _category.isEmpty ? null : _category),
                builder: (context, rows) {
                  if (rows.isEmpty) {
                    return EmptyView(
                      icon: Icons.inventory_2_outlined,
                      text: _search.isEmpty ? 'مفيش أصناف لسه. ضيف الأصناف من تبويب المخزن.' : 'مفيش صنف بالاسم ده',
                      actionLabel: 'صنف جديد',
                      onAction: () => push(context, const ProductFormScreen()),
                    );
                  }
                  return ListenableBuilder(
                    listenable: cart,
                    builder: (context, _) => GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 230,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.45,
                      ),
                      itemCount: rows.length,
                      itemBuilder: (context, i) => _ProductCard(
                        product: rows[i],
                        inCart: cart.qtyOf(s(rows[i]['id'])),
                        // Tap asks how many pieces first; the scanner is the
                        // fast path that puts one straight in the basket.
                        onTap: () => _openProductSheet(rows[i]),
                        // A cashier sells; he does not get a way into the
                        // product's own page from here.
                        onLongPress: app.can(Perm.stock)
                            ? () => push(context, ProductDetailScreen(productId: s(rows[i]['id'])))
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: cart,
          builder: (context, _) => cart.isEmpty ? const SizedBox.shrink() : _CartBar(cart: cart),
        ),
      ),
      );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.inCart, required this.onTap, required this.onLongPress});

  final DbRow product;
  final double inCart;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cart = PosCart.instance;
    final stock = n(product['stock']) - inCart;
    final out = stock <= 0;
    return Opacity(
      opacity: out && inCart <= 0 ? 0.55 : 1,
      child: Material(
      color: inCart > 0 ? AppColors.primarySoft : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: inCart > 0 ? AppColors.primary : AppColors.border, width: inCart > 0 ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(s(product['name']),
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
                  ),
                  if (inCart > 0)
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: AppColors.primary,
                      child: Text(qty(inCart), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
              Text(
                [s(product['brand']), s(product['model'])].where((x) => x.isNotEmpty).join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(egp(cart.priceOf(product)),
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary)),
                    ),
                  ),
                  Pill(out ? 'خلص' : 'متاح ${qty(stock)}', color: out ? AppColors.bad : AppColors.good),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({required this.cart});

  final PosCart cart;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${qty(cart.count)} قطعة • ${cart.lines.length} صنف', style: const TextStyle(color: AppColors.muted)),
                    Text(egp(cart.total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => showCartSheet(context),
                icon: const Icon(Icons.shopping_basket_outlined),
                label: const Text('الدفع'),
              ),
            ],
          ),
        ),
      );
}

Future<void> showCartSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CartSheet(),
    );

class _CartSheet extends StatefulWidget {
  const _CartSheet();

  @override
  State<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<_CartSheet> {
  final cart = PosCart.instance;
  late final _discount = TextEditingController(text: numText(cart.discount));
  final _paid = TextEditingController();
  String _payment = 'cash';
  bool _busy = false;

  Future<void> _editLine(CartLine line) async {
    final q = TextEditingController(text: numText(line.qty));
    final p = TextEditingController(text: numText(line.price));
    final listed = cart.priceOf(line.product);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s(line.product['name'])),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: NumField(controller: q, label: 'الكمية')),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: NumField(controller: p, label: 'السعر في البيعة دي', suffix: currency)),
              ],
            ),
            const Gap(8),
            // The price of the goods on the shelf stays where it is: what is
            // typed here is what this customer pays today, nothing more.
            Text(
              'سعر الصنف المسجل ${money(listed)}، وهيفضل زي ما هو.',
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
            ),
            if (listed > 0)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => p.text = numText(listed),
                  child: const Text('رجّع السعر المسجل'),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تمام')),
        ],
      ),
    );
    if (ok != true) return;
    cart.setPrice(line, parseNum(p.text));
    final newQty = parseNum(q.text);
    if (newQty > line.stock) {
      if (mounted) toast(context, 'الكمية المتاحة ${qty(line.stock)} بس', error: true);
      cart.setQty(line, line.stock);
    } else {
      cart.setQty(line, newQty);
    }
  }

  Future<void> _complete() async {
    if (cart.isEmpty) return;
    if (_payment == 'credit' && cart.customer == null) {
      toast(context, 'اختار العميل علشان البيع الآجل يتسجل على حسابه', error: true);
      return;
    }
    if (_payment == 'installment') {
      final lines = [
        for (final l in cart.lines)
          InvoiceLineDraft(productId: l.productId, name: s(l.product['name']), unit: s(l.product['unit']), qty: l.qty, price: l.price),
      ];
      final party = cart.customer?['id'] as String?;
      final level = cart.priceLevel;
      final discount = cart.discount;
      final nav = Navigator.of(context);
      nav.pop();
      // The basket stays as it is until the installment invoice is really
      // saved: going back from it must never lose the sale.
      nav.push(MaterialPageRoute<void>(
        builder: (_) => InvoiceForm(
          kind: 'sale',
          initialLines: lines,
          initialPartyId: party,
          initialPriceLevel: level,
          initialPaymentType: 'installment',
          initialDiscount: discount,
          onSaved: cart.clear,
        ),
      ));
      return;
    }
    final warehouses = await app.crops.warehouses();
    final boxes = await app.accounts.cashBoxes();
    if (!mounted) return;
    if (warehouses.isEmpty || boxes.isEmpty) {
      toast(context, 'لازم يبقى في مخزن وخزنة الأول', error: true);
      return;
    }
    // One last look before the sale is written: the goods, the money, and
    // what the customer takes back.
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SaleReview(
        payment: _payment,
        given: roundMoney(parseNum(_paid.text)),
      ),
    );
    if (confirmed != true || !mounted) return;
    final short = cart.lines.where((l) => l.qty > l.stock + 0.0001).toList();
    if (short.isNotEmpty) {
      toast(
        context,
        'مينفعش تبيع أكتر من اللي في المخزن:\n${short.map((l) => '${s(l.product['name'])}: المتاح ${qty(l.stock)}').join('\n')}',
        error: true,
      );
      return;
    }
    setState(() => _busy = true);
    final total = cart.total;
    final given = roundMoney(parseNum(_paid.text));
    final paid = _payment == 'cash' ? total : min(given, total);
    final change = _payment == 'cash' && given > total ? roundMoney(given - total) : 0.0;
    final customer = cart.customer;
    final String id;
    try {
      id = await app.appliances.saveInvoice(
        header: {
          'kind': 'sale',
          'date': todayStr(),
          'party_id': customer?['id'],
          'customer_name': customer == null ? 'زبون' : null,
          'warehouse_id': warehouses.first['id'],
          'cash_box_id': boxes.first['id'],
          'price_level': cart.priceLevel,
          'payment_type': _payment,
          'subtotal': cart.subtotal,
          'discount': cart.discount,
          'total': total,
          'grand_total': total,
          'paid_amount': paid,
          'source': 'pos',
        },
        lines: [
          for (final l in cart.lines)
            InvoiceLineDraft(productId: l.productId, name: s(l.product['name']), qty: l.qty, price: l.price),
        ],
      );
    } on OutOfStock catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, e.toString(), error: true);
      return;
    }
    cart.clear();
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    await showModalBottomSheet<void>(
      context: nav.context,
      builder: (_) => _SaleDone(invoiceId: id, total: total, change: change, customer: customer, paid: paid),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.88,
          child: ListenableBuilder(
            listenable: cart,
            builder: (context, _) {
              final total = cart.total;
              final given = parseNum(_paid.text);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('السلة (${cart.lines.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        ),
                        TextButton.icon(
                          onPressed: cart.isEmpty
                              ? null
                              : () async {
                                  final ok = await confirmDialog(context, title: 'تفريغ السلة', message: 'تشيل كل الأصناف؟', ok: 'تفريغ', danger: true);
                                  if (ok) {
                                    cart.clear();
                                    if (context.mounted) Navigator.pop(context);
                                  }
                                },
                          icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.bad),
                          label: const Text('تفريغ', style: TextStyle(color: AppColors.bad)),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final l in cart.lines) _lineTile(l),
                        const Gap(10),
                        NumField(
                          controller: _discount,
                          label: 'خصم على الفاتورة',
                          suffix: currency,
                          onChanged: (v) => cart.setDiscount(parseNum(v)),
                        ),
                        const Gap(),
                        PickField(
                          label: 'العميل ${_payment == 'cash' ? '(اختياري)' : ''}',
                          value: cart.customer == null ? null : s(cart.customer!['name']),
                          icon: Icons.person_outline,
                          onTap: () async {
                            final p = await pickParty(context, title: 'اختار العميل', preferKinds: const ['customer']);
                            if (p != null) cart.setCustomer(p);
                          },
                          onClear: () => cart.setCustomer(null),
                        ),
                        const Gap(),
                        Choice<String>(
                          options: const {'cash': 'كاش', 'credit': 'آجل', 'installment': 'تقسيط'},
                          value: _payment,
                          onChanged: (v) => setState(() => _payment = v),
                        ),
                        const Gap(),
                        if (_payment == 'cash') ...[
                          NumField(controller: _paid, label: 'الزبون دفع كام؟', suffix: currency, onChanged: (_) => setState(() {})),
                          const Gap(6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final v in _quickAmounts(total))
                                ActionChip(label: Text(money(v)), onPressed: () => setState(() => _paid.text = numText(v))),
                            ],
                          ),
                          if (given > total)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: InfoRow('الباقي للزبون', egp(given - total), bold: true, big: true, color: AppColors.good),
                            ),
                          if (given > 0 && given < total)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('المبلغ أقل من الإجمالي. لو هيدفع الباقي بعدين اختار "آجل".',
                                  style: TextStyle(color: AppColors.warn)),
                            ),
                        ] else if (_payment == 'credit') ...[
                          NumField(controller: _paid, label: 'دفع كام دلوقتي؟ (اختياري)', suffix: currency, onChanged: (_) => setState(() {})),
                          const Gap(6),
                          InfoRow('هيتبقى على حسابه', egp(max(0, total - given)), bold: true, color: AppColors.bad),
                        ] else
                          const Text(
                            'هتكمل في فاتورة التقسيط: المقدم، عدد الشهور، نسبة الزيادة والضامن.',
                            style: TextStyle(color: AppColors.muted, height: 1.5),
                          ),
                        const Gap(16),
                      ],
                    ),
                  ),
                  SaveBar(
                    busy: _busy,
                    label: _payment == 'installment' ? 'كمّل التقسيط' : 'إتمام البيع ${egp(total)}',
                    onSave: cart.isEmpty ? null : _complete,
                  ),
                ],
              );
            },
          ),
        ),
      );

  List<double> _quickAmounts(double total) {
    if (total <= 0) return const [];
    final out = <double>{total};
    for (final step in [50.0, 100.0, 500.0, 1000.0]) {
      final v = (total / step).ceil() * step;
      if (v > total) out.add(v);
    }
    return out.take(4).toList();
  }

  Widget _lineTile(CartLine l) {
    final over = l.qty > l.stock;
    return Dismissible(
      key: ValueKey('cart-${l.productId}'),
      direction: DismissDirection.startToEnd,
      background: Container(
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: AppColors.badSoft,
        child: const Icon(Icons.delete_outline, color: AppColors.bad),
      ),
      onDismissed: (_) => cart.remove(l),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _editLine(l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s(l.product['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${money(l.price)} للقطعة', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    if (cart.priceOf(l.product) > 0 && l.price != cart.priceOf(l.product))
                      Text(
                        'سعر خاص • المسجل ${money(cart.priceOf(l.product))}',
                        style: const TextStyle(color: AppColors.warn, fontSize: 12),
                      ),
                    if (over)
                      Text('المتاح ${qty(l.stock)} بس', style: const TextStyle(color: AppColors.bad, fontSize: 12.5)),
                  ],
                ),
              ),
            ),
            IconButton.outlined(
              visualDensity: VisualDensity.compact,
              onPressed: () => cart.setQty(l, l.qty - 1),
              icon: const Icon(Icons.remove, size: 18),
            ),
            SizedBox(
              width: 36,
              child: Text(qty(l.qty), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            IconButton.outlined(
              visualDensity: VisualDensity.compact,
              onPressed: () {
                if (l.qty + 1 > l.stock) {
                  toast(context, 'الكمية المتاحة ${qty(l.stock)} بس', error: true);
                } else {
                  cart.setQty(l, l.qty + 1);
                }
              },
              icon: const Icon(Icons.add, size: 18),
            ),
            SizedBox(
              width: 86,
              child: Text(money(l.total), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleDone extends StatelessWidget {
  const _SaleDone({required this.invoiceId, required this.total, required this.change, required this.paid, this.customer});

  final String invoiceId;
  final double total;
  final double change;
  final double paid;
  final DbRow? customer;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle, color: AppColors.good, size: 64),
              const Gap(8),
              const Text('تم البيع', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text(egp(total), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: AppColors.muted)),
              if (customer != null && paid < total - 0.009)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.badSoft, borderRadius: BorderRadius.circular(12)),
                  child: Text('اتسجل على حساب ${s(customer!['name'])}: ${egp(total - paid)}',
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.bad)),
                ),
              if (change > 0)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.goodSoft, borderRadius: BorderRadius.circular(12)),
                  child: Text('الباقي للزبون: ${egp(change)}',
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.good)),
                ),
              const Gap(16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      // Opens the receipt on screen first, then printing or
                      // saving it is one more tap.
                      onPressed: () => printPdf(context, () => PdfDocs.receipt(invoiceId), 'إيصال'),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('الإيصال'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final nav = Navigator.of(context);
                        nav.pop();
                        nav.push(MaterialPageRoute<void>(builder: (_) => InvoiceDetailScreen(invoiceId: invoiceId)));
                      },
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('الفاتورة'),
                    ),
                  ),
                ],
              ),
              const Gap(10),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('بيع جديد'),
              ),
            ],
          ),
        ),
      );
}

/// Long press on a product: how many pieces, at what price, and the quick
/// ways to fix the product itself.
class _ProductSheet extends StatefulWidget {
  const _ProductSheet({required this.product});

  final DbRow product;

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  final cart = PosCart.instance;
  late DbRow _p = widget.product;
  late double _qty = cart.qtyOf(s(_p['id'])) > 0 ? cart.qtyOf(s(_p['id'])) : 1;
  late final _price = TextEditingController(text: numText(_lineOrListPrice));

  double get _lineOrListPrice {
    final line = cart.lines.where((l) => l.productId == s(_p['id'])).firstOrNull;
    return line?.price ?? cart.priceOf(_p);
  }

  double get _stock => n(_p['stock']);

  Future<void> _reload() async {
    final p = await app.appliances.product(s(_p['id']));
    if (p != null && mounted) {
      setState(() {
        _p = p;
        _price.text = numText(cart.priceOf(p));
      });
    }
  }

  void _apply() {
    final price = parseNum(_price.text);
    final line = cart.lines.where((l) => l.productId == s(_p['id'])).firstOrNull;
    if (line == null) {
      cart.add(_p, _qty);
      cart.setPrice(cart.lines.last, price);
    } else {
      cart.setQty(line, _qty);
      cart.setPrice(line, price);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final out = _stock <= 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s(_p['name']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          Text(
            [
              if (s(_p['barcode']).isNotEmpty) 'كود ${s(_p['barcode'])}',
              'المتاح ${qty(_stock)} ${s(_p['unit'])}',
            ].join(' • '),
            textAlign: TextAlign.center,
            style: TextStyle(color: out ? AppColors.bad : AppColors.muted),
          ),
          const Gap(12),
          Row(
            children: [
              Expanded(
                child: NumField(
                  controller: _price,
                  label: 'السعر في البيعة دي',
                  suffix: currency,
                  onChanged: (_) => setState(() {}),
                  helper: parseNum(_price.text) == cart.priceOf(_p)
                      ? 'سعر الصنف المسجل'
                      : 'المسجل ${money(cart.priceOf(_p))} • التغيير للبيعة دي بس',
                ),
              ),
              const SizedBox(width: 10),
              Column(
                children: [
                  const Text('الكمية', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  Row(
                    children: [
                      IconButton.outlined(
                        visualDensity: VisualDensity.compact,
                        onPressed: _qty > 1 ? () => setState(() => _qty -= 1) : null,
                        icon: const Icon(Icons.remove, size: 18),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(qty(_qty), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      ),
                      IconButton.outlined(
                        visualDensity: VisualDensity.compact,
                        onPressed: _qty + 1 > _stock ? null : () => setState(() => _qty += 1),
                        icon: const Icon(Icons.add, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const Gap(8),
          InfoRow('الإجمالي', egp(parseNum(_price.text) * _qty), bold: true, big: true),
          const Gap(8),
          FilledButton.icon(
            onPressed: out ? null : _apply,
            icon: const Icon(Icons.add_shopping_cart),
            label: Text(
              out
                  ? 'خلصان من المخزن'
                  : cart.qtyOf(s(_p['id'])) > 0
                      ? 'خلي الكمية ${qty(_qty)} في السلة'
                      : 'ضيف ${qty(_qty)} للسلة',
            ),
          ),
          // Changing the product itself, and its page, are the storekeeper's.
          if (app.can(Perm.stock)) ...[
            const Gap(6),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () async {
                      await editProductPrices(context, _p);
                      await _reload();
                    },
                    icon: const Icon(Icons.price_change_outlined),
                    label: const Text('غيّر سعر الصنف نفسه'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      push(context, ProductDetailScreen(productId: s(_p['id'])));
                    },
                    icon: const Icon(Icons.info_outline),
                    label: const Text('تفاصيل الصنف'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The last look before a sale is written: what is being sold, for how much,
/// how it is paid, and what goes back to the customer. Nothing is saved until
/// "تمام، احفظ البيع" is pressed.
class _SaleReview extends StatelessWidget {
  const _SaleReview({required this.payment, required this.given});

  final String payment;

  /// What the customer handed over (cash), or what is being paid now (credit).
  final double given;

  @override
  Widget build(BuildContext context) {
    final cart = PosCart.instance;
    final total = cart.total;
    final paid = payment == 'cash' ? total : min(given, total);
    final change = payment == 'cash' && given > total ? roundMoney(given - total) : 0.0;
    final onAccount = roundMoney(total - paid);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('راجع البيع قبل ما تحفظه', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            children: [
              Box(
                child: Column(
                  children: [
                    for (final l in cart.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                s(l.product['name']),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text('${qty(l.qty)} × ${money(l.price)}', style: const TextStyle(color: AppColors.muted)),
                            SizedBox(
                              width: 90,
                              child: Text(money(l.total), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Gap(),
              Box(
                child: Column(
                  children: [
                    InfoRow('عدد القطع', qty(cart.count)),
                    if (cart.discount > 0) ...[
                      InfoRow('الإجمالي', egp(cart.subtotal)),
                      InfoRow('الخصم', '- ${egp(cart.discount)}', color: AppColors.bad),
                    ],
                    InfoRow('المطلوب', egp(total), bold: true, big: true),
                    const Divider(),
                    InfoRow('طريقة الدفع', paymentTypes[payment] ?? payment),
                    InfoRow('العميل', cart.customer == null ? 'زبون' : s(cart.customer!['name'])),
                    if (payment == 'cash' && given > 0) InfoRow('الزبون دفع', egp(given)),
                    if (change > 0) InfoRow('الباقي للزبون', egp(change), bold: true, color: AppColors.good),
                    if (onAccount > 0.009)
                      InfoRow('هيتسجل على حسابه', egp(onAccount), bold: true, color: AppColors.bad),
                  ],
                ),
              ),
              const Gap(),
            ],
          ),
        ),
        SaveBar(
          label: 'تمام، احفظ البيع',
          onSave: () => Navigator.pop(context, true),
          extra: OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع للتعديل'),
          ),
        ),
      ],
    );
  }
}
