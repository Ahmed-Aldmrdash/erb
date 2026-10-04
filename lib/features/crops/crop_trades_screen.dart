import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/labels.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common/excel_export.dart';
import '../settings/sync_screen.dart';
import 'crop_trade_detail.dart';
import 'crop_trade_form.dart';

class CropTradesScreen extends StatefulWidget {
  const CropTradesScreen({super.key, this.kind = '', this.asTab = false});

  final String kind;

  /// Shown as the "العمليات" tab of the trade (no back button).
  final bool asTab;

  @override
  State<CropTradesScreen> createState() => _CropTradesScreenState();
}

class _CropTradesScreenState extends State<CropTradesScreen> {
  late String _kind = widget.kind;
  Period _period = Period.thisMonth();
  String _search = '';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.asTab ? 'العمليات' : 'عمليات المحاصيل'),
          automaticallyImplyLeading: !widget.asTab,
          actions: [
            ExcelButton(title: 'التوريد والبيع', sheets: () async => [await ExcelExport.cropTrades()]),
            if (widget.asTab) const SyncButton(),
          ],
        ),
        floatingActionButton: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_kind != 'sale')
              FloatingActionButton.extended(
                heroTag: 'buy',
                onPressed: () => push(context, const CropTradeForm(kind: 'purchase')),
                icon: const Icon(Icons.move_to_inbox_outlined),
                label: const Text('توريد'),
              ),
            if (_kind == '') const SizedBox(width: 10),
            if (_kind != 'purchase')
              FloatingActionButton.extended(
                heroTag: 'sell',
                backgroundColor: AppColors.appliances,
                foregroundColor: Colors.white,
                onPressed: () => push(context, const CropTradeForm(kind: 'sale')),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('بيع'),
              ),
          ],
        ),
        body: Column(
          children: [
            SearchField(onChanged: (v) => setState(() => _search = v), hint: 'بحث بالاسم أو رقم العملية أو الكارتة'),
            ChipsBar<String>(
              options: const {'': 'الكل', 'purchase': 'التوريد (شراء)', 'sale': 'البيع'},
              value: _kind,
              onChanged: (v) => setState(() => _kind = v),
            ),
            PeriodBar(value: _period, onChanged: (p) => setState(() => _period = p)),
            Expanded(
              child: DbBuilder<List<DbRow>>(
                queryKey: (_kind, _period, _search),
                query: () => app.crops.trades(
                  kind: _kind.isEmpty ? null : _kind,
                  from: _period.from,
                  to: _period.to,
                  search: _search,
                ),
                builder: (context, rows) {
                  if (rows.isEmpty) return const EmptyView(icon: Icons.grass, text: 'مفيش عمليات في الفترة دي');
                  double boughtKg = 0, boughtAmount = 0, soldKg = 0, soldAmount = 0;
                  for (final r in rows) {
                    if (r['kind'] == 'sale') {
                      soldKg += n(r['net_kg']);
                      soldAmount += n(r['party_total']);
                    } else {
                      boughtKg += n(r['net_kg']);
                      boughtAmount += n(r['party_total']);
                    }
                  }
                  return TileListView(
                    itemCount: rows.length,
                    itemBuilder: (context, i) => CropTradeTile(rows[i]),
                    header: Column(
                      children: [
                        CardRow(children: [
                          if (_kind != 'sale')
                            StatCard(label: 'توريد', value: '${qty(boughtKg)} كجم', subtitle: egp(boughtAmount), color: AppColors.crops),
                          if (_kind != 'purchase')
                            StatCard(label: 'بيع', value: '${qty(soldKg)} كجم', subtitle: egp(soldAmount), color: AppColors.appliances),
                        ]),
                        const Gap(10),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
}

class CropTradeTile extends StatelessWidget {
  const CropTradeTile(this.r, {super.key});

  final DbRow r;

  @override
  Widget build(BuildContext context) {
    final isSale = r['kind'] == 'sale';
    final by = s(r['created_by_name']);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isSale ? AppColors.appliancesSoft : AppColors.cropsSoft,
        child: Icon(
          isSale ? Icons.local_shipping_outlined : Icons.move_to_inbox_outlined,
          color: isSale ? AppColors.appliances : AppColors.crops,
          size: 20,
        ),
      ),
      title: Text('${s(r['party_name'])} • ${s(r['crop_name'])}', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${cropTradeKinds[r['kind']]} ${s(r['number'])} • ${showDate(r['date'])}\n'
        '${kgWithUnits(n(r['net_kg']), s(r['unit_name']), n(r['kg_per_unit']))}${by.isEmpty ? '' : ' • $by'}',
      ),
      isThreeLine: true,
      trailing: Text(egp(n(r['party_total'])), style: const TextStyle(fontWeight: FontWeight.w700)),
      onTap: () => push(context, CropTradeDetailScreen(tradeId: s(r['id']))),
    );
  }
}
