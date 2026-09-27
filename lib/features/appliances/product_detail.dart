import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/barcode.dart';
import '../../data/labels.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common/open_doc.dart';
import 'labels_screen.dart';
import 'product_form.dart';
import 'quick_edit.dart';

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  Future<({DbRow? p, List<DbRow> byWarehouse, List<DbRow> moves})> _load() async => (
        p: await app.appliances.product(productId),
        byWarehouse: await app.appliances.productStockByWarehouse(productId),
        moves: await app.appliances.productMoves(productId),
      );

  @override
  Widget build(BuildContext context) => DbBuilder(
        query: _load,
        builder: (context, d) {
          final p = d.p;
          if (p == null || n(p['deleted']) == 1) {
            return Scaffold(appBar: AppBar(), body: const EmptyView(icon: Icons.inventory_2_outlined, text: 'الصنف ده اتحذف'));
          }
          final stock = n(p['stock']);
          final unitCost = n(p['unit_cost']);
          final retail = n(p['retail_price']);
          final code = s(p['barcode']);
          return Scaffold(
            appBar: AppBar(
              title: Text(s(p['name'])),
              actions: [
                IconButton(
                  onPressed: () => push(context, ProductFormScreen(id: productId)),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (code.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Box(
                      color: AppColors.primarySoft,
                      child: Row(
                        children: [
                          Icon(Icons.qr_code, size: 32, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('رقم الصنف', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                                Text(code, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary)),
                                if (retail > 0)
                                  Text(
                                    'على الملصق: ${ProductCode.printed(code, retail)}',
                                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => addToLabels(context, p),
                            icon: const Icon(Icons.local_offer_outlined),
                            label: const Text('ملصق'),
                          ),
                        ],
                      ),
                    ),
                  ),
                CardRow(children: [
                  StatCard(
                    label: 'المخزون',
                    value: '${qty(stock)} ${s(p['unit'])}',
                    icon: Icons.inventory_2_outlined,
                    color: stock <= 0 ? AppColors.bad : AppColors.appliances,
                  ),
                  StatCard(
                    label: 'متوسط التكلفة',
                    value: egp(unitCost),
                    subtitle: retail > 0 && unitCost > 0
                        ? 'مكسب القطاعي ${intf(((retail - unitCost) / unitCost * 100).round())}%'
                        : null,
                    icon: Icons.price_change_outlined,
                    color: AppColors.appliances,
                  ),
                ]),
                const Gap(12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => editProductPrices(context, p),
                          icon: const Icon(Icons.price_change_outlined),
                          label: const Text('تعديل السعر'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => editProductStock(context, p),
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('تعديل الكمية'),
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Box(
                    child: Column(
                      children: [
                        InfoRow('سعر القطاعي', egp(retail), bold: true),
                        InfoRow('سعر الجملة', egp(n(p['wholesale_price']))),
                        InfoRow('سعر الشراء المسجل', egp(n(p['cost_price']))),
                        if (s(p['brand']).isNotEmpty) InfoRow('الماركة', s(p['brand'])),
                        if (s(p['model']).isNotEmpty) InfoRow('الموديل', s(p['model'])),
                        if (s(p['category']).isNotEmpty) InfoRow('القسم', s(p['category'])),
                        if (s(p['barcode']).isNotEmpty) InfoRow('الكود', s(p['barcode'])),
                        if (n(p['min_qty']) > 0) InfoRow('حد الطلب', qty(n(p['min_qty']))),
                      ],
                    ),
                  ),
                ),

                if (d.byWarehouse.length > 1) ...[
                  const SectionTitle('حسب المخزن'),
                  TileGroup(children: [
                    for (final w in d.byWarehouse)
                      ListTile(
                        leading: const Icon(Icons.warehouse_outlined),
                        title: Text(s(w['warehouse_name'])),
                        trailing: Text(qty(n(w['qty'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ]),
                ],
                const SectionTitle('حركة الصنف'),
                if (d.moves.isEmpty)
                  const EmptyView(icon: Icons.inbox_outlined, text: 'مفيش حركات')
                else
                  TileGroup(children: [
                    for (final m in d.moves.take(200))
                      ListTile(
                        onTap: () => openDoc(context, s(m['doc_type']), s(m['doc_id'])),
                        title: Text(
                          [docLabel(s(m['doc_type']), s(m['kind'])), s(m['party_name'])].where((x) => x.isNotEmpty).join(' • '),
                        ),
                        subtitle: Text(
                          [
                            showDate(m['date']),
                            if (s(m['number']).isNotEmpty) s(m['number']),
                            if (m['price'] != null) 'بسعر ${money(n(m['price']))}',
                          ].join(' • '),
                        ),
                        trailing: Text(
                          qty(n(m['qty'])),
                          style: TextStyle(fontWeight: FontWeight.w700, color: n(m['qty']) < 0 ? AppColors.bad : AppColors.good),
                        ),
                      ),
                  ]),
              ],
            ),
          );
        },
      );
}
