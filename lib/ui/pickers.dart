import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/db/app_db.dart';
import '../core/util/format.dart';
import '../data/labels.dart';
import '../data/permissions.dart';
import '../features/accounts/party_form.dart';
import '../features/appliances/product_form.dart';
import 'theme.dart';
import 'widgets.dart';

/// Searchable bottom sheet list. Returns the chosen row.
Future<DbRow?> showPicker(
  BuildContext context, {
  required String title,
  required Future<List<DbRow>> Function(String search) load,
  required String Function(DbRow r) titleOf,
  String Function(DbRow r)? subtitleOf,
  Widget Function(DbRow r)? trailingOf,
  Future<DbRow?> Function(BuildContext context)? onAdd,
  String addLabel = 'إضافة جديد',
  bool searchable = true,
}) =>
    showModalBottomSheet<DbRow>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PickerSheet(
        title: title,
        load: load,
        titleOf: titleOf,
        subtitleOf: subtitleOf,
        trailingOf: trailingOf,
        onAdd: onAdd,
        addLabel: addLabel,
        searchable: searchable,
      ),
    );

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.load,
    required this.titleOf,
    required this.subtitleOf,
    required this.trailingOf,
    required this.onAdd,
    required this.addLabel,
    required this.searchable,
  });

  final String title;
  final Future<List<DbRow>> Function(String search) load;
  final String Function(DbRow r) titleOf;
  final String Function(DbRow r)? subtitleOf;
  final Widget Function(DbRow r)? trailingOf;
  final Future<DbRow?> Function(BuildContext context)? onAdd;
  final String addLabel;
  final bool searchable;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(hintText: 'بحث...', prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
            if (widget.onAdd != null)
              ListTile(
                leading: Icon(Icons.add_circle, color: AppColors.primary),
                title: Text(widget.addLabel, style: TextStyle(color: AppColors.primary)),
                onTap: () async {
                  final r = await widget.onAdd!(context);
                  if (r != null && context.mounted) Navigator.pop(context, r);
                },
              ),
            const Divider(height: 1),
            Expanded(
              child: DbBuilder<List<DbRow>>(
                queryKey: _search,
                query: () => widget.load(_search),
                builder: (context, rows) {
                  if (rows.isEmpty) {
                    return const EmptyView(icon: Icons.search_off, text: 'مفيش نتائج');
                  }
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final sub = widget.subtitleOf?.call(r);
                      return ListTile(
                        title: Text(widget.titleOf(r)),
                        subtitle: sub == null || sub.isEmpty ? null : Text(sub),
                        trailing: widget.trailingOf?.call(r),
                        onTap: () => Navigator.pop(context, r),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _join(List<String?> parts) => parts.where((p) => p != null && p.isNotEmpty).join(' • ');

/// Accounts of the open division; [preferKinds] first (e.g. farmers when
/// buying crops).
Future<DbRow?> pickParty(
  BuildContext context, {
  String title = 'اختار الاسم',
  List<String>? preferKinds,
  String? newKind,
}) =>
    showPicker(
      context,
      title: title,
      load: (q) async {
        final rows = await app.accounts.parties(search: q);
        if (preferKinds == null) return rows;
        final first = rows.where((r) => preferKinds.contains(r['kind'])).toList();
        final rest = rows.where((r) => !preferKinds.contains(r['kind'])).toList();
        return [...first, ...rest];
      },
      titleOf: (r) => s(r['name']),
      subtitleOf: (r) => _join([partyKinds[r['kind']], s(r['phone'])]),
      trailingOf: (r) => BalanceText(n(r['balance']), size: 12.5),
      onAdd: (c) => push<DbRow>(c, PartyFormScreen(defaultKind: newKind ?? partyKindsFor(app.division).keys.first)),
      addLabel: 'إضافة اسم جديد',
    );

Future<DbRow?> pickCrop(BuildContext context) => showPicker(
      context,
      title: 'اختار المحصول',
      searchable: false,
      load: (_) => app.crops.crops(),
      titleOf: (r) => s(r['name']),
      subtitleOf: (r) => 'الوحدة: ${s(r['unit_name'])} = ${qty(n(r['kg_per_unit']))} كجم',
      trailingOf: (r) => Text(
        unitsOf(n(r['stock_kg']), s(r['unit_name']), n(r['kg_per_unit'])),
        style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
      ),
    );

Future<DbRow?> pickWarehouse(BuildContext context) => showPicker(
      context,
      title: app.isCrops ? 'اختار المخزن / الشونة' : 'اختار المخزن',
      searchable: false,
      load: (_) => app.crops.warehouses(),
      titleOf: (r) => s(r['name']),
    );

Future<DbRow?> pickCashBox(BuildContext context) => showPicker(
      context,
      title: 'اختار الخزنة',
      searchable: false,
      load: (_) => app.accounts.cashBoxes(),
      titleOf: (r) => s(r['name']),
      trailingOf: (r) => Text(egp(n(r['balance'])), style: const TextStyle(fontWeight: FontWeight.w600)),
    );

Future<DbRow?> pickProduct(BuildContext context, {bool forPurchase = false, String? boughtBy}) =>
    showPicker(
      context,
      title: boughtBy != null ? 'اختار صنف من مشتريات العميل' : 'اختار الصنف',
      load: (q) => app.appliances.products(search: q, boughtBy: boughtBy),
      titleOf: (r) => s(r['name']),
      subtitleOf: (r) => _join([s(r['brand']), s(r['model']), 'متاح: ${qty(n(r['stock']))}']),
      trailingOf: (r) {
        final price = forPurchase ? n(r['cost_price']) : n(r['retail_price']);
        return Text(egp(price), style: const TextStyle(fontWeight: FontWeight.w700));
      },
      // Creating a product from inside an invoice is still creating a
      // product: not for an account that may only sell.
      onAdd: boughtBy != null || !app.can(Perm.stock)
          ? null
          : (c) => push<DbRow>(c, const ProductFormScreen()),
      addLabel: 'إضافة صنف جديد',
    );
