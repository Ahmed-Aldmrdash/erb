import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../core/util/uuid.dart';
import '../../data/reports_repo.dart';
import '../../data/seasons.dart';
import '../../ui/share.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../accounts/party_detail.dart';
import '../common/pdf_docs.dart';

/// تقرير الموسم: what was bought and sold in a season, per crop, per farmer
/// and per trader, with deductions, advances, expenses and profit.
class SeasonReportScreen extends StatefulWidget {
  const SeasonReportScreen({super.key});

  @override
  State<SeasonReportScreen> createState() => _SeasonReportScreenState();
}

class _SeasonReportScreenState extends State<SeasonReportScreen> {
  late Period _period;
  String? _seasonId;
  String? _cropId;
  String _cropName = '';

  List<Season> get _seasons => seasonsOf(app.settings);

  @override
  void initState() {
    super.initState();
    final seasons = _seasons;
    if (seasons.isNotEmpty) {
      _seasonId = seasons.first.id;
      _period = Period(seasons.first.from, seasons.first.to, seasons.first.name);
    } else {
      _period = Period.thisYear();
    }
  }

  String get _title => _period.label;

  Future<void> _addSeason() async {
    final year = DateTime.now().year;
    final name = TextEditingController();
    var from = '$year-04-01', to = '$year-07-31';
    final r = await showDialog<Season>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('موسم جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in seasonPresets(year))
                      ActionChip(
                        label: Text(p.name),
                        onPressed: () => setD(() {
                          name.text = p.name;
                          from = p.from;
                          to = p.to;
                        }),
                      ),
                  ],
                ),
                const Gap(),
                TextF(controller: name, label: 'اسم الموسم', icon: Icons.label_outline),
                const Gap(),
                DateField(label: 'من', value: from, onChanged: (v) => setD(() => from = v)),
                const Gap(),
                DateField(label: 'لحد', value: to, onChanged: (v) => setD(() => to = v)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty || from.compareTo(to) > 0) return;
                Navigator.pop(c, Season(id: newId(), name: name.text.trim(), from: from, to: to));
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (r == null) return;
    await app.accounts.saveSettings({'seasons': seasonsJson([..._seasons, r])});
    if (!mounted) return;
    setState(() {
      _seasonId = r.id;
      _period = Period(r.from, r.to, r.name);
    });
  }

  Future<void> _deleteSeason(Season x) async {
    final ok = await confirmDialog(context, title: 'حذف الموسم', message: 'تحذف "${x.name}" من القائمة؟ (العمليات نفسها مش هتتمسح)', ok: 'حذف', danger: true);
    if (!ok) return;
    await app.accounts.saveSettings({'seasons': seasonsJson(_seasons.where((e) => e.id != x.id).toList())});
    if (!mounted) return;
    setState(() {
      if (_seasonId == x.id) {
        _seasonId = null;
        _period = Period.thisYear();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('تقرير الموسم')),
        body: Column(
          children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  for (final x in _seasons)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: GestureDetector(
                        onLongPress: () => _deleteSeason(x),
                        child: ChoiceChip(
                          label: Text(x.name),
                          selected: _seasonId == x.id,
                          showCheckmark: false,
                          onSelected: (_) => setState(() {
                            _seasonId = x.id;
                            _period = Period(x.from, x.to, x.name);
                          }),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                      label: const Text('السنة دي'),
                      selected: _seasonId == null && _period == Period.thisYear(),
                      showCheckmark: false,
                      onSelected: (_) => setState(() {
                        _seasonId = null;
                        _period = Period.thisYear();
                      }),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ActionChip(
                      avatar: const Icon(Icons.date_range, size: 18),
                      label: Text(_seasonId == null && _period != Period.thisYear() ? _period.rangeText : 'فترة محددة'),
                      onPressed: () async {
                        final r = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2015),
                          lastDate: DateTime(2100),
                          initialDateRange: DateTimeRange(start: parseDate(_period.from)!, end: parseDate(_period.to)!),
                        );
                        if (r != null) {
                          setState(() {
                            _seasonId = null;
                            _period = Period(dateStr(r.start), dateStr(r.end), 'فترة محددة');
                          });
                        }
                      },
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('موسم جديد'),
                    onPressed: _addSeason,
                  ),
                ],
              ),
            ),
            DbBuilder<List<DbRow>>(
              query: app.crops.crops,
              builder: (context, crops) => ChipsBar<String>(
                options: {'': 'كل المحاصيل', for (final c in crops) s(c['id']): s(c['name'])},
                value: _cropId ?? '',
                onChanged: (v) => setState(() {
                  _cropId = v.isEmpty ? null : v;
                  _cropName = v.isEmpty ? '' : s(crops.firstWhere((c) => c['id'] == v)['name']);
                }),
              ),
            ),
            Expanded(
              child: DbBuilder<SeasonReport>(
                queryKey: (_period, _cropId),
                query: () => app.reports.season(_period.from, _period.to, cropId: _cropId),
                builder: (context, r) => _body(context, r),
              ),
            ),
          ],
        ),
      );

  Widget _body(BuildContext context, SeasonReport r) {
    if (r.purchases.isEmpty && r.sales.isEmpty && r.advances.isEmpty) {
      return EmptyView(icon: Icons.grass, text: 'مفيش عمليات في ${_title.isEmpty ? 'الفترة دي' : _title}');
    }
    final names = <String, DbRow>{
      for (final x in [...r.purchases, ...r.sales]) s(x['crop_id']): x,
    };
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            '$_title${_cropName.isEmpty ? '' : ' • $_cropName'} • ${_period.rangeText}',
            style: const TextStyle(color: AppColors.muted),
          ),
        ),
        const Gap(8),
        CardRow(children: [
          StatCard(
            label: 'التوريد (${intf(r.tripsIn)} نقلة)',
            value: '${qty(r.boughtKg)} كجم',
            subtitle: egp(r.boughtAmount),
            icon: Icons.move_to_inbox_outlined,
            color: AppColors.crops,
          ),
          StatCard(
            label: 'البيع (${intf(r.tripsOut)} نقلة)',
            value: '${qty(r.soldKg)} كجم',
            subtitle: egp(r.soldAmount),
            icon: Icons.local_shipping_outlined,
            color: AppColors.appliances,
          ),
        ]),
        const Gap(10),
        CardRow(children: [
          StatCard(
            label: r.netProfit >= 0 ? 'صافي المكسب' : 'صافي الخسارة',
            value: egp(r.netProfit.abs()),
            subtitle: _cropId == null ? 'بعد المصاريف' : 'قبل المصاريف العامة',
            icon: r.netProfit >= 0 ? Icons.trending_up : Icons.trending_down,
            color: r.netProfit >= 0 ? AppColors.good : AppColors.bad,
          ),
          StatCard(
            label: 'اتخصم في التوريد',
            value: '${qty(r.deductedKg)} كجم',
            subtitle: 'شكاير ورطوبة وشوائب',
            icon: Icons.content_cut,
            color: AppColors.warn,
          ),
        ]),
        const SectionTitle('حسب المحصول'),
        for (final e in names.entries) _cropCard(r, e.key, e.value),
        if (r.farmers.isNotEmpty) ...[
          SectionTitle('الفلاحين والموردين (${r.farmers.length})'),
          TileGroup(children: [for (final p in r.farmers) _partyTile(context, p)]),
        ],
        if (r.traders.isNotEmpty) ...[
          SectionTitle('التجار والمصانع (${r.traders.length})'),
          TileGroup(children: [for (final p in r.traders) _partyTile(context, p)]),
        ],
        if (r.advances.isNotEmpty) ...[
          SectionTitle('السلف (${egp(r.advancesTotal)})'),
          TileGroup(children: [
            for (final a in r.advances)
              ListTile(
                title: Text(s(a['name'])),
                subtitle: Text('${intf(n(a['cnt']))} سلفة'),
                trailing: Text(egp(n(a['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => push(context, PartyDetailScreen(partyId: s(a['party_id']))),
              ),
          ]),
        ],
        if (r.expenses.isNotEmpty) ...[
          SectionTitle('المصروفات (${egp(r.otherExpenses)})'),
          TileGroup(children: [
            for (final e in r.expenses)
              ListTile(
                dense: true,
                title: Text(s(e['category'])),
                trailing: Text(egp(n(e['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ]),
        ],
        if (r.stock.isNotEmpty) ...[
          const SectionTitle('في المخزن دلوقتي'),
          TileGroup(children: [
            for (final c in r.stock)
              ListTile(
                dense: true,
                title: Text(s(c['name'])),
                trailing: Text(
                  unitsOf(n(c['stock_kg']), s(c['unit_name']), n(c['kg_per_unit'])),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ]),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => openWhatsApp(context, null, _summary(r)),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('ملخص واتساب'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => sharePdf(
                    context,
                    () => PdfDocs.season(r, title: _title, from: _period.from, to: _period.to, cropName: _cropName),
                    'تقرير $_title.pdf',
                  ),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('التقرير PDF'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cropCard(SeasonReport r, String cropId, DbRow info) {
    final unit = s(info['unit_name']);
    final kpu = n(info['kg_per_unit']);
    final buy = r.purchases.where((x) => x['crop_id'] == cropId).firstOrNull;
    final sell = r.sales.where((x) => x['crop_id'] == cropId).firstOrNull;
    final profit = r.profit.where((x) => x['id'] == cropId).firstOrNull;
    String avg(DbRow x) {
      final units = kpu > 0 ? n(x['net_kg']) / kpu : 0;
      return units > 0 ? egp(n(x['value']) / units) : '-';
    }

    Widget side(String title, DbRow x, Color color) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
              InfoRow('النقلات', intf(n(x['cnt']))),
              InfoRow('الصافي', unitsOf(n(x['net_kg']), unit, kpu), sub: '${qty(n(x['net_kg']))} كجم'),
              if (n(x['deducted_kg']) > 0) InfoRow('اتخصم', '${qty(n(x['deducted_kg']))} كجم'),
              InfoRow('متوسط السعر لل$unit', avg(x)),
              InfoRow('القيمة', egp(n(x['party_total'])), bold: true),
              if (n(x['expenses']) > 0) InfoRow('نولون وعتالة', egp(n(x['expenses']))),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Box(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.grass, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(s(info['name']), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                if (profit != null)
                  Pill(
                    '${n(profit['profit']) >= 0 ? 'مكسب' : 'خسارة'} ${money(n(profit['profit']).abs())}',
                    color: n(profit['profit']) >= 0 ? AppColors.good : AppColors.bad,
                  ),
              ],
            ),
            if (buy != null) side('توريد', buy, AppColors.crops),
            if (buy != null && sell != null) const Divider(height: 18),
            if (sell != null) side('بيع', sell, AppColors.appliances),
          ],
        ),
      ),
    );
  }

  Widget _partyTile(BuildContext context, DbRow p) {
    final b = balanceInfo(n(p['balance']));
    return ListTile(
      title: Text(s(p['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${intf(n(p['cnt']))} نقلة • ${qty(n(p['net_kg']))} كجم • ${egp(n(p['party_total']))}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(b.amount, style: TextStyle(color: b.color, fontWeight: FontWeight.w800)),
          Text(b.word, style: TextStyle(color: b.color, fontSize: 11.5)),
        ],
      ),
      onTap: () => push(context, PartyDetailScreen(partyId: s(p['party_id']))),
    );
  }

  String _summary(SeasonReport r) => [
        '*تقرير ${_title.isEmpty ? 'الموسم' : _title}*${_cropName.isEmpty ? '' : ' - $_cropName'}',
        '${app.companyName} - ${app.divisionName}',
        'من ${showDate(_period.from)} لحد ${showDate(_period.to)}',
        '',
        '🌾 التوريد: ${intf(r.tripsIn)} نقلة • ${qty(r.boughtKg)} كجم • ${egp(r.boughtAmount)}',
        '🚚 البيع: ${intf(r.tripsOut)} نقلة • ${qty(r.soldKg)} كجم • ${egp(r.soldAmount)}',
        '✂️ اتخصم في التوريد: ${qty(r.deductedKg)} كجم',
        if (r.advancesTotal > 0) '💵 السلف: ${egp(r.advancesTotal)}',
        if (r.otherExpenses > 0) '🧾 المصروفات: ${egp(r.otherExpenses)}',
        '*${r.netProfit >= 0 ? 'صافي المكسب' : 'صافي الخسارة'}: ${egp(r.netProfit.abs())}*',
      ].join('\n');
}
