import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common/excel_export.dart';
import '../pos/barcode_scan.dart';
import '../settings/sync_screen.dart';
import '../stock/stocktake_screen.dart';
import 'labels_screen.dart';
import 'product_detail.dart';
import 'product_form.dart';
import 'quick_edit.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, this.lowOnly = false, this.asTab = false});

  final bool lowOnly;

  /// Shown as the "المخزن" tab of the showroom (no back button).
  final bool asTab;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _search = '';
  String _category = '';
  late bool _lowOnly = widget.lowOnly;

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final p = await app.appliances.productByBarcode(code);
    if (!mounted) return;
    if (p != null) {
      push(context, ProductDetailScreen(productId: s(p['id'])));
      return;
    }
    final add = await confirmDialog(
      context,
      title: 'صنف مش متسجل',
      message: 'الباركود $code مش متسجل على أي صنف. تضيفه صنف جديد؟',
      ok: 'إضافة',
    );
    if (add && mounted) push(context, ProductFormScreen(barcode: code));
  }

  /// Gives the products that have no number one, and offers to re-number the
  /// short ones left from an older version so every label reads the same.
  Future<void> _fixCodes() async {
    final state = await app.appliances.productCodeState();
    if (!mounted) return;
    if (state.missing == 0 && state.short == 0) {
      toast(context, 'كل الأصناف ليها أرقام بنفس الطول');
      return;
    }
    final unify = state.short > 0 &&
        await confirmDialog(
          context,
          title: 'أرقام الأصناف',
          message: '${state.short} صنف رقمه قصير من نسخة قديمة'
              '${state.missing > 0 ? '، و${state.missing} صنف من غير رقم' : ''}.\n\n'
              'نديهم أرقام جديدة بنفس الطول (4 أرقام)؟ لو طبعت ملصقات للأصناف دي قبل كده '
              'هتحتاج تطبعها تاني.',
          ok: 'إديهم أرقام جديدة',
        );
    if (!mounted) return;
    final count = await app.appliances.codeAllProducts(unify: unify);
    if (!mounted) return;
    toast(context, count == 0 ? 'مفيش حاجة اتغيرت' : 'اتعمل رقم لـ $count صنف');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.asTab ? 'المخزن' : 'الأصناف والمخزون'),
          automaticallyImplyLeading: !widget.asTab,
          actions: [
            ExcelButton(title: 'أصناف المعرض', sheets: () async => [await ExcelExport.products()]),
            IconButton(tooltip: 'دور بالباركود', onPressed: _scan, icon: const Icon(Icons.qr_code_scanner)),
            PopupMenuButton<String>(
              tooltip: 'المزيد',
              onSelected: (v) async {
                switch (v) {
                  case 'labels':
                    await push(context, const LabelsScreen());
                  case 'stocktake':
                    await push(context, const StocktakeScreen());
                  case 'codes':
                    await _fixCodes();
                }
                if (mounted) setState(() {});
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'labels',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.local_offer_outlined),
                    title: Text('ملصقات الأسعار والباركود'),
                  ),
                ),
                PopupMenuItem(
                  value: 'stocktake',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.fact_check_outlined),
                    title: Text('جرد المخزن'),
                  ),
                ),
                PopupMenuItem(
                  value: 'codes',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.pin_outlined),
                    title: Text('أرقام الأصناف'),
                  ),
                ),
              ],
            ),
            if (widget.asTab) const SyncButton(),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => push(context, const ProductFormScreen()),
          icon: const Icon(Icons.add),
          label: const Text('صنف جديد'),
        ),
        body: Column(
          children: [
            SearchField(onChanged: (v) => setState(() => _search = v), hint: 'بحث بالاسم أو الماركة أو الموديل أو الكود'),
            DbBuilder<List<String>>(
              query: app.appliances.categories,
              builder: (context, cats) => ChipsBar<String>(
                options: {
                  '': 'الكل',
                  '!low': 'قربت تخلص',
                  for (final c in cats) c: c,
                },
                value: _lowOnly ? '!low' : _category,
                onChanged: (v) => setState(() {
                  _lowOnly = v == '!low';
                  _category = _lowOnly ? '' : v;
                }),
              ),
            ),
            Expanded(
              child: DbBuilder<List<DbRow>>(
                queryKey: (_search, _category, _lowOnly),
                query: () => app.appliances.products(
                  search: _search,
                  category: _category.isEmpty ? null : _category,
                  lowOnly: _lowOnly,
                  activeOnly: false,
                ),
                builder: (context, rows) {
                  if (rows.isEmpty) {
                    return EmptyView(
                      icon: Icons.inventory_2_outlined,
                      text: _lowOnly ? 'مفيش أصناف قربت تخلص' : 'مفيش أصناف لسه',
                    );
                  }
                  final value = rows.fold<double>(0, (a, r) => a + (n(r['stock']) > 0 ? n(r['stock']) * n(r['unit_cost']) : 0));
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 90),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          children: [
                            Text('${rows.length} صنف', style: const TextStyle(color: AppColors.muted)),
                            const Spacer(),
                            Text('قيمة المخزون: ${egp(value)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      TileGroup(children: [for (final r in rows) ProductTile(r)]),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
}

class ProductTile extends StatelessWidget {
  const ProductTile(this.r, {super.key});

  final DbRow r;

  @override
  Widget build(BuildContext context) {
    final stock = n(r['stock']);
    final low = n(r['min_qty']) > 0 && stock <= n(r['min_qty']);
    final inactive = n(r['active']) != 1;
    final code = s(r['barcode']);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: stock <= 0 ? AppColors.badSoft : (low ? AppColors.warnSoft : AppColors.appliancesSoft),
        child: Text(
          qty(stock),
          style: TextStyle(
            color: stock <= 0 ? AppColors.bad : (low ? AppColors.warn : AppColors.appliances),
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
      title: Text('${s(r['name'])}${inactive ? ' (موقوف)' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (code.isNotEmpty) 'كود $code', s(r['brand']), s(r['model']), s(r['category'])]
            .where((x) => x.isNotEmpty)
            .join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(egp(n(r['retail_price'])), style: const TextStyle(fontWeight: FontWeight.w700)),
          if (n(r['wholesale_price']) > 0)
            Text('جملة ${money(n(r['wholesale_price']))}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ),
      onTap: () => push(context, ProductDetailScreen(productId: s(r['id']))),
      onLongPress: () => showProductActions(context, r),
    );
  }
}
