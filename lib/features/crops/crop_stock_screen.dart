import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common/excel_export.dart';
import '../common/stock_move_form.dart';
import '../settings/sync_screen.dart';
import 'crop_detail.dart';
import 'crops_manage.dart';

/// Stock of the trade: every crop with its quantity per warehouse, average
/// cost and today's prices.
class CropStockScreen extends StatelessWidget {
  const CropStockScreen({super.key});

  Future<({List<DbRow> crops, List<DbRow> byWarehouse, double value})> _load() async => (
        crops: await app.crops.crops(),
        byWarehouse: await app.crops.stockByWarehouse(),
        value: await app.crops.stockValue(),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('المخزن'),
          actions: [
            ExcelButton(title: 'مخزن المحاصيل', sheets: () async => [await ExcelExport.crops()]),
            const SyncButton(),
          ],
        ),
        body: DbBuilder(
          query: _load,
          builder: (context, d) => ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Box(
                  color: AppColors.primarySoft,
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, color: AppColors.primary),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('قيمة المخزون بالتكلفة', style: TextStyle(color: AppColors.muted))),
                      Text(egp(d.value), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              ActionGrid(columns: 3, children: [
                ActionTile(
                  icon: Icons.price_change_outlined,
                  label: 'أسعار النهارده',
                  color: AppColors.accent,
                  onTap: () => push(context, const CropPricesScreen()),
                ),
                ActionTile(
                  icon: Icons.swap_horiz,
                  label: 'تحويل بين المخازن',
                  color: AppColors.appliances,
                  onTap: () => push(context, const StockMoveForm(itemType: 'crop', kind: 'transfer')),
                ),
                ActionTile(
                  icon: Icons.tune,
                  label: 'تسوية / هالك',
                  color: AppColors.warn,
                  onTap: () => push(context, const StockMoveForm(itemType: 'crop', kind: 'adjust')),
                ),
                ActionTile(
                  icon: Icons.grass,
                  label: 'أصناف المحاصيل',
                  onTap: () => push(context, const CropsScreen()),
                ),
                ActionTile(
                  icon: Icons.warehouse_outlined,
                  label: 'المخازن والشون',
                  onTap: () => push(context, const WarehousesScreen()),
                ),
                ActionTile(
                  icon: Icons.history,
                  label: 'حركات المخزن',
                  color: AppColors.accounts,
                  onTap: () => push(context, const StockMovesScreen(itemType: 'crop')),
                ),
              ]),
              const SectionTitle('المحاصيل'),
              // Crops in stock first.
              for (final c in [
                ...d.crops.where((c) => n(c['stock_kg']).abs() > 0.0005),
                ...d.crops.where((c) => n(c['stock_kg']).abs() <= 0.0005),
              ])
                _cropCard(context, c, d.byWarehouse.where((w) => w['crop_id'] == c['id']).toList()),
            ],
          ),
        ),
      );

  Widget _cropCard(BuildContext context, DbRow c, List<DbRow> warehouses) {
    final unit = s(c['unit_name']);
    final kpu = n(c['kg_per_unit']);
    final stock = n(c['stock_kg']);
    final buy = n(c['buy_price']);
    final sell = n(c['sell_price']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => push(context, CropDetailScreen(cropId: s(c['id']))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(backgroundColor: AppColors.primarySoft, child: Icon(Icons.grass, color: AppColors.primary)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s(c['name']), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          Text('ال$unit = ${qty(kpu)} كجم', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(unitsOf(stock, unit, kpu),
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: stock < 0 ? AppColors.bad : AppColors.text)),
                        Text('${qty(stock)} كجم', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                if (warehouses.length > 1 || (warehouses.length == 1 && stock.abs() > 0.0005)) ...[
                  const Divider(height: 18),
                  for (final w in warehouses)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.warehouse_outlined, size: 16, color: AppColors.muted),
                          const SizedBox(width: 6),
                          Expanded(child: Text(s(w['warehouse_name']), style: const TextStyle(color: AppColors.muted))),
                          Text(unitsOf(n(w['kg']), unit, kpu), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
                const Divider(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (n(c['cost_per_kg']) > 0) Pill('متوسط التكلفة ${money(n(c['cost_per_kg']) * kpu)}', color: AppColors.muted),
                    Pill(buy > 0 ? 'شراء النهارده ${money(buy)}' : 'سعر الشراء مش متحدد', color: AppColors.good),
                    Pill(sell > 0 ? 'بيع النهارده ${money(sell)}' : 'سعر البيع مش متحدد', color: AppColors.appliances),
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

/// Board of today's buying and selling price per crop.
class CropPricesScreen extends StatefulWidget {
  const CropPricesScreen({super.key});

  @override
  State<CropPricesScreen> createState() => _CropPricesScreenState();
}

class _CropPricesScreenState extends State<CropPricesScreen> {
  final Map<String, (TextEditingController, TextEditingController)> _ctrls = {};
  List<DbRow> _crops = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    app.crops.crops().then((rows) {
      if (!mounted) return;
      setState(() {
        _crops = rows;
        for (final c in rows) {
          _ctrls[s(c['id'])] = (
            TextEditingController(text: numText(n(c['buy_price']))),
            TextEditingController(text: numText(n(c['sell_price']))),
          );
        }
      });
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    for (final c in _crops) {
      final (buy, sell) = _ctrls[s(c['id'])]!;
      final b = parseNum(buy.text), sl = parseNum(sell.text);
      if (b != n(c['buy_price']) || sl != n(c['sell_price'])) {
        await app.crops.saveCropPrices(s(c['id']), b, sl);
      }
    }
    if (!mounted) return;
    toast(context, 'اتحفظت الأسعار');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('أسعار النهارده')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'السعر هنا لكل وحدة (أردب / طن / قنطار). بيتكتب لوحده في التوريد والبيع وتقدر تغيره وقتها.',
              style: TextStyle(color: AppColors.muted, height: 1.6),
            ),
            const Gap(12),
            for (final c in _crops)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Box(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${s(c['name'])} (بال${s(c['unit_name'])})', style: const TextStyle(fontWeight: FontWeight.w800)),
                      const Gap(8),
                      Row(
                        children: [
                          Expanded(child: NumField(controller: _ctrls[s(c['id'])]!.$1, label: 'سعر الشراء', suffix: currency)),
                          const SizedBox(width: 10),
                          Expanded(child: NumField(controller: _ctrls[s(c['id'])]!.$2, label: 'سعر البيع', suffix: currency)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SaveBar(onSave: _save, busy: _busy, label: 'حفظ الأسعار'),
      );
}
