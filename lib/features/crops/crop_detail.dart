import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/labels.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common/open_doc.dart';
import '../common/stock_move_form.dart';
import 'crop_trade_form.dart';

/// Stock of one crop per warehouse and all its movements.
class CropDetailScreen extends StatelessWidget {
  const CropDetailScreen({super.key, required this.cropId});

  final String cropId;

  Future<({DbRow? crop, double costPerKg, List<DbRow> byWarehouse, List<DbRow> moves})> _load() async => (
        crop: (await app.crops.crops(activeOnly: false)).where((c) => c['id'] == cropId).firstOrNull,
        costPerKg: await app.crops.costPerKg(cropId),
        byWarehouse: await app.crops.stockByWarehouse(cropId: cropId),
        moves: await app.crops.cropMoves(cropId),
      );

  @override
  Widget build(BuildContext context) => DbBuilder(
        query: _load,
        builder: (context, d) {
          final c = d.crop;
          if (c == null) return Scaffold(appBar: AppBar(), body: const SizedBox());
          final unit = s(c['unit_name']);
          final kpu = n(c['kg_per_unit']);
          final stock = n(c['stock_kg']);
          return Scaffold(
            appBar: AppBar(title: Text(s(c['name']))),
            body: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                CardRow(children: [
                  StatCard(
                    label: 'المخزون',
                    value: unitsOf(stock, unit, kpu),
                    subtitle: '${qty(stock)} كجم',
                    icon: Icons.inventory_2_outlined,
                    color: AppColors.crops,
                  ),
                  StatCard(
                    label: 'متوسط التكلفة لل$unit',
                    value: egp(d.costPerKg * kpu),
                    subtitle: 'قيمة المخزون ${egp(stock > 0 ? stock * d.costPerKg : 0)}',
                    icon: Icons.price_change_outlined,
                    color: AppColors.crops,
                  ),
                ]),
                const Gap(12),
                ActionGrid(columns: 4, children: [
                  ActionTile(
                    icon: Icons.move_to_inbox_outlined,
                    label: 'توريد',
                    color: AppColors.crops,
                    onTap: () => push(context, CropTradeForm(kind: 'purchase', cropId: cropId)),
                  ),
                  ActionTile(
                    icon: Icons.local_shipping_outlined,
                    label: 'بيع',
                    color: AppColors.crops,
                    onTap: () => push(context, CropTradeForm(kind: 'sale', cropId: cropId)),
                  ),
                  ActionTile(
                    icon: Icons.swap_horiz,
                    label: 'تحويل',
                    color: AppColors.appliances,
                    onTap: () => push(context, StockMoveForm(itemType: 'crop', kind: 'transfer', itemId: cropId)),
                  ),
                  ActionTile(
                    icon: Icons.tune,
                    label: 'تسوية / هالك',
                    color: AppColors.warn,
                    onTap: () => push(context, StockMoveForm(itemType: 'crop', kind: 'adjust', itemId: cropId)),
                  ),
                ]),
                const SectionTitle('حسب المخزن'),
                if (d.byWarehouse.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('مفيش مخزون', style: TextStyle(color: AppColors.muted)),
                  )
                else
                  TileGroup(children: [
                    for (final w in d.byWarehouse)
                      ListTile(
                        leading: const Icon(Icons.warehouse_outlined),
                        title: Text(s(w['warehouse_name'])),
                        trailing: Text(kgWithUnits(n(w['kg']), unit, kpu), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                  ]),
                const SectionTitle('الحركات'),
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
                        subtitle: Text('${showDate(m['date'])} • ${s(m['warehouse_name'])}'),
                        trailing: Text(
                          unitsOf(n(m['qty']), unit, kpu),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: n(m['qty']) < 0 ? AppColors.bad : AppColors.good,
                          ),
                        ),
                      ),
                  ]),
              ],
            ),
          );
        },
      );
}
