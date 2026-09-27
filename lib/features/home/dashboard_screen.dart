import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../data/permissions.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/appliances_repo.dart';
import '../../ui/mini_chart.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../accounts/parties_screen.dart';
import '../accounts/party_detail.dart';
import '../accounts/voucher_form.dart';
import '../appliances/installments_screen.dart';
import '../appliances/invoice_form.dart';
import '../appliances/invoices_screen.dart';
import '../appliances/products_screen.dart';
import '../cash/daily_cash_screen.dart';
import '../common/person_chip.dart';
import '../crops/crop_detail.dart';
import '../crops/crop_stock_screen.dart';
import '../crops/crop_trade_form.dart';
import '../notes/notes_screen.dart';
import '../settings/sync_screen.dart';
import 'home_shell.dart';

class _Dash {
  double cash = 0;
  double cashIn = 0;
  double cashOut = 0;
  double receivable = 0;
  double payable = 0;
  List<DbRow> notes = const [];
  List<DbRow> collections = const [];
  List<({String date, double a, double b})> series = const [];

  // المعرض
  DbRow salesToday = const {};
  List<InstallmentRow> dueInstallments = const [];
  int lowStock = 0;

  // التجارة
  DbRow cropsToday = const {};
  List<DbRow> crops = const [];

  static Future<_Dash> load() async {
    final d = _Dash();
    final today = todayStr();
    d.cash = await app.reports.cashTotal();
    final day = await app.accounts.cashDay(today);
    for (final r in day.rows) {
      final k = s(r['kind']);
      if (k == 'transfer' || k == 'transfer_in') continue;
      d.cashIn += n(r['amount_in']);
      d.cashOut += n(r['amount_out']);
    }
    final rp = await app.reports.receivablesPayables();
    d.receivable = rp.receivable;
    d.payable = rp.payable;
    d.notes = await app.notes.list(done: false);
    d.collections = await app.accounts.dueCollections(today);
    d.series = await app.reports.dailySeries(7);
    if (app.isCrops) {
      d.cropsToday = await app.reports.cropsActivity(today, today);
      d.crops = (await app.crops.crops()).where((c) => n(c['stock_kg']).abs() > 0.0005).toList();
    } else {
      d.salesToday = await app.appliances.salesSummary(today, today);
      d.dueInstallments = await app.appliances.openInstallments(until: today);
      d.lowStock = await app.appliances.lowStockCount();
    }
    return d;
  }
}

/// Home of the open division: today's numbers, quick actions, reminders and
/// who has to pay today.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: RefreshIndicator(
          onRefresh: () async => app.sync?.syncNow(),
          child: DbBuilder<_Dash>(
            query: _Dash.load,
            builder: (context, d) => ListView(
              padding: EdgeInsets.zero,
              children: [
                _hero(context, d),
                const _OldVersionCard(),
                if (!app.isCrops && app.can(Perm.pos)) _posButton(),
                if (_quickActions(context).isNotEmpty) ...[
                  const SectionTitle('عمليات سريعة'),
                  ActionGrid(columns: 4, children: _quickActions(context)),
                ],
                ..._notesSection(context, d),
                if (app.can(Perm.accounts) || app.can(Perm.sales)) ..._collectionsSection(context, d),
                if (app.can(Perm.stock) || app.can(Perm.sales) || app.can(Perm.reports))
                  if (app.isCrops) ..._tradeSection(context, d) else ..._showroomSection(context, d),
                if (app.can(Perm.accounts)) ...[
                const SectionTitle('الحسابات'),
                CardRow(children: [
                  StatCard(
                    label: 'لينا عند الناس',
                    value: egp(d.receivable),
                    icon: Icons.call_received,
                    color: AppColors.good,
                    onTap: () => push(context, const PartiesScreen(balanceFilter: 1)),
                  ),
                  StatCard(
                    label: 'علينا للناس',
                    value: egp(d.payable),
                    icon: Icons.call_made,
                    color: AppColors.bad,
                    onTap: () => push(context, const PartiesScreen(balanceFilter: -1)),
                  ),
                ]),
                ],
                ..._chart(d),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      );

  // ---------------------------------------------------------------- header

  Widget _hero(BuildContext context, _Dash d) {
    final todayLabel = app.isCrops ? 'توريد النهارده' : 'مبيعات النهارده';
    final todayValue = app.isCrops
        ? egp(n(d.cropsToday['bought_amount']))
        : egp(n(d.salesToday['sales']) - n(d.salesToday['returns']));
    final todaySub = app.isCrops
        ? '${intf(n(d.cropsToday['bought_count']))} نقلة • ${qty(n(d.cropsToday['bought_kg']))} كجم'
        : '${intf(n(d.salesToday['sales_count']))} فاتورة';
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => HeroHeader(
        title: app.companyName,
        subtitle: '${app.divisionName} • ${longDate(DateTime.now())}',
        trailing: const SyncButton(light: true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PersonChip(light: true),
            const SizedBox(height: 12),
            Row(
              children: [
                // What is in the till is for whoever handles the money.
                if (app.can(Perm.money)) ...[
                  Expanded(
                    child: _GlassNumber(
                      label: 'في الخزنة',
                      value: egp(d.cash),
                      sub: 'دخل ${money(d.cashIn)} • خرج ${money(d.cashOut)}',
                      onTap: () => push(context, const DailyCashScreen()),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: _GlassNumber(
                    label: todayLabel,
                    value: todayValue,
                    sub: todaySub,
                    onTap: () => homeTab.value = app.isCrops ? 'ops' : 'pos',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _posButton() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: BigActionButton(
          label: 'بيع جديد (الكاشير)',
          icon: Icons.point_of_sale,
          color: AppColors.accent,
          onTap: () => homeTab.value = 'pos',
        ),
      );

  // ---------------------------------------------------------------- actions

  /// The quick actions this person may use. A cashier ends up with the
  /// cashier and the reminder, and nothing that touches money or purchases.
  List<Widget> _quickActions(BuildContext context) =>
      (app.isCrops ? _tradeActions(context) : _showroomActions(context))
          .where((a) => a.$1)
          .map((a) => a.$2)
          .toList();

  List<(bool, Widget)> _showroomActions(BuildContext context) => [
        (
          app.can(Perm.sales),
          ActionTile(
            icon: Icons.receipt_long_outlined,
            label: 'فاتورة بيع',
            onTap: () => push(context, const InvoiceForm(kind: 'sale')),
          )
        ),
        (
          app.can(Perm.money),
          ActionTile(
            icon: Icons.south_west,
            label: 'استلمت فلوس',
            color: AppColors.good,
            onTap: () => push(context, const VoucherForm(kind: 'receipt')),
          )
        ),
        (
          app.can(Perm.money),
          ActionTile(
            icon: Icons.north_east,
            label: 'دفعت فلوس',
            color: AppColors.bad,
            onTap: () => push(context, const VoucherForm(kind: 'payment')),
          )
        ),
        (
          app.can(Perm.money),
          ActionTile(
            icon: Icons.shopping_bag_outlined,
            label: 'مصروف',
            color: AppColors.warn,
            onTap: () => push(context, const VoucherForm(kind: 'expense')),
          )
        ),
        (
          app.can(Perm.sales),
          ActionTile(
            icon: Icons.event_available_outlined,
            label: 'تحصيل قسط',
            color: AppColors.appliances,
            onTap: () => push(context, const InstallmentsScreen()),
          )
        ),
        (
          app.can(Perm.sales),
          ActionTile(
            icon: Icons.add_shopping_cart,
            label: 'بضاعة جت',
            color: AppColors.crops,
            onTap: () => push(context, const InvoiceForm(kind: 'purchase')),
          )
        ),
        (
          true,
          ActionTile(
            icon: Icons.sticky_note_2_outlined,
            label: 'تذكرة جديدة',
            color: AppColors.accounts,
            onTap: () => showNoteSheet(context),
          )
        ),
        (
          !app.can(Perm.sales) && app.can(Perm.pos),
          ActionTile(
            icon: Icons.receipt_outlined,
            label: 'فواتيري',
            color: AppColors.appliances,
            onTap: () => push(context, const InvoicesScreen(mineOnly: true)),
          )
        ),
        (
          app.can(Perm.money),
          ActionTile(
            icon: Icons.today_outlined,
            label: 'يومية الخزنة',
            color: AppColors.muted,
            onTap: () => push(context, const DailyCashScreen()),
          )
        ),
      ];

  List<(bool, Widget)> _tradeActions(BuildContext context) => [
        (
          app.can(Perm.sales),
          ActionTile(
            icon: Icons.move_to_inbox_outlined,
            label: 'توريد محصول',
            onTap: () => push(context, const CropTradeForm(kind: 'purchase')),
          )
        ),
        (
          app.can(Perm.sales),
          ActionTile(
            icon: Icons.local_shipping_outlined,
            label: 'بيع محصول',
            color: AppColors.appliances,
            onTap: () => push(context, const CropTradeForm(kind: 'sale')),
          )
        ),
        (
          app.can(Perm.money),
          ActionTile(
            icon: Icons.volunteer_activism_outlined,
            label: 'سلفة لفلاح',
            color: AppColors.accent,
            onTap: () => push(context, const VoucherForm(kind: 'advance')),
          )
        ),
        (
          app.can(Perm.money),
          ActionTile(
            icon: Icons.shopping_bag_outlined,
            label: 'مصروف',
            color: AppColors.warn,
            onTap: () => push(context, const VoucherForm(kind: 'expense')),
          )
        ),
        (
          app.can(Perm.money),
          ActionTile(
            icon: Icons.south_west,
            label: 'استلمت فلوس',
            color: AppColors.good,
            onTap: () => push(context, const VoucherForm(kind: 'receipt')),
          )
        ),
        (
          app.can(Perm.money),
          ActionTile(
            icon: Icons.north_east,
            label: 'دفعت فلوس',
            color: AppColors.bad,
            onTap: () => push(context, const VoucherForm(kind: 'payment')),
          )
        ),
        (
          true,
          ActionTile(
            icon: Icons.sticky_note_2_outlined,
            label: 'تذكرة جديدة',
            color: AppColors.accounts,
            onTap: () => showNoteSheet(context),
          )
        ),
        (
          app.can(Perm.stock),
          ActionTile(
            icon: Icons.price_change_outlined,
            label: 'أسعار النهارده',
            color: AppColors.muted,
            onTap: () => push(context, const CropPricesScreen()),
          )
        ),
      ];

  // ---------------------------------------------------------------- sections

  List<Widget> _notesSection(BuildContext context, _Dash d) => [
        SectionTitle(
          d.notes.isEmpty ? 'التذكرة' : 'التذكرة (${d.notes.length})',
          action: d.notes.isEmpty ? null : 'عرض الكل',
          onAction: () => push(context, const NotesScreen()),
        ),
        if (d.notes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: AppColors.accountsSoft,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => showNoteSheet(context),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.sticky_note_2_outlined, color: AppColors.accounts),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'مفيش تذكرة مفتوحة. حد ساب فلوس لحد؟ أو في حاجة متتنسيش؟ اكتبها هنا وكله هيشوفها.',
                          style: TextStyle(height: 1.5),
                        ),
                      ),
                      Icon(Icons.add_circle, color: AppColors.accounts),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          for (final r in d.notes.take(3))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: NoteCard(r, compact: true),
            ),
      ];

  List<Widget> _collectionsSection(BuildContext context, _Dash d) {
    if (d.collections.isEmpty) return const [];
    final total = d.collections.fold<double>(0, (a, r) => a + n(r['balance']));
    return [
      SectionTitle('مواعيد تحصيل (${egp(total)})'),
      TileGroup(children: [
        for (final r in d.collections.take(6))
          ListTile(
            leading: LetterAvatar(s(r['name']), color: AppColors.good),
            title: Text(s(r['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              s(r['collect_on']) == todayStr() ? 'ميعاده النهارده' : 'ميعاده كان ${showDate(r['collect_on'])}',
              style: TextStyle(color: s(r['collect_on']) == todayStr() ? AppColors.warn : AppColors.bad),
            ),
            trailing: Text(egp(n(r['balance'])), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.good)),
            onTap: () => push(context, PartyDetailScreen(partyId: s(r['id']))),
          ),
      ]),
    ];
  }

  List<Widget> _showroomSection(BuildContext context, _Dash d) {
    final dueAmount = d.dueInstallments.fold<double>(0, (a, r) => a + r.status.remaining);
    final overdue = d.dueInstallments.where((r) => r.status.dueDate.compareTo(todayStr()) < 0).length;
    return [
      const SectionTitle('المعرض'),
      CardRow(children: [
        StatCard(
          label: 'أقساط مستحقة (${d.dueInstallments.length})',
          value: egp(dueAmount),
          subtitle: overdue > 0 ? 'منهم $overdue متأخر' : 'مفيش متأخرات',
          icon: Icons.event_busy_outlined,
          color: d.dueInstallments.isEmpty ? AppColors.good : AppColors.bad,
          onTap: () => push(context, const InstallmentsScreen()),
        ),
        StatCard(
          label: 'أصناف قربت تخلص',
          value: '${d.lowStock} صنف',
          subtitle: d.lowStock == 0 ? 'المخزن تمام' : 'محتاجة طلبية',
          icon: Icons.inventory_2_outlined,
          color: d.lowStock == 0 ? AppColors.good : AppColors.warn,
          onTap: () => push(context, const ProductsScreen(lowOnly: true)),
        ),
      ]),
      if (d.dueInstallments.isNotEmpty) ...[
        SectionTitle('أقساط مستحقة', action: 'عرض الكل', onAction: () => push(context, const InstallmentsScreen())),
        TileGroup(children: [
          for (final r in d.dueInstallments.take(4))
            ListTile(
              leading: LetterAvatar(s(r.invoice['party_name']), color: AppColors.bad),
              title: Text(s(r.invoice['party_name'])),
              subtitle: Text('قسط ${r.status.seq} • ${showDate(r.status.dueDate)}'),
              trailing: Text(
                egp(r.status.remaining),
                style: const TextStyle(color: AppColors.bad, fontWeight: FontWeight.w700),
              ),
              onTap: () => push(context, const InstallmentsScreen()),
            ),
        ]),
      ],
    ];
  }

  List<Widget> _tradeSection(BuildContext context, _Dash d) {
    final t = d.cropsToday;
    return [
      const SectionTitle('المحاصيل النهارده'),
      CardRow(children: [
        StatCard(
          label: 'توريد (${intf(n(t['bought_count']))})',
          value: '${qty(n(t['bought_kg']))} كجم',
          subtitle: egp(n(t['bought_amount'])),
          icon: Icons.move_to_inbox_outlined,
          color: AppColors.crops,
          onTap: () => homeTab.value = 'ops',
        ),
        StatCard(
          label: 'بيع (${intf(n(t['sold_count']))})',
          value: '${qty(n(t['sold_kg']))} كجم',
          subtitle: egp(n(t['sold_amount'])),
          icon: Icons.local_shipping_outlined,
          color: AppColors.appliances,
          onTap: () => homeTab.value = 'ops',
        ),
      ]),
      if (d.crops.isNotEmpty) ...[
        SectionTitle('في المخزن', action: 'التفاصيل', onAction: () => homeTab.value = 'stock'),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: d.crops.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final c = d.crops[i];
              final sell = n(c['sell_price']);
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => push(context, CropDetailScreen(cropId: s(c['id']))),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.cropsSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(s(c['name']), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.crops)),
                      Text(
                        unitsOf(n(c['stock_kg']), s(c['unit_name']), n(c['kg_per_unit'])),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      if (sell > 0)
                        Text('بيع ${money(sell)}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ];
  }

  List<Widget> _chart(_Dash d) {
    if (d.series.every((e) => e.a == 0 && e.b == 0)) return const [];
    return [
      SectionTitle(app.isCrops ? 'آخر 7 أيام' : 'مبيعات آخر 7 أيام'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (app.isCrops)
                const Row(
                  children: [
                    _Legend(color: AppColors.crops, text: 'توريد'),
                    SizedBox(width: 14),
                    _Legend(color: AppColors.appliances, text: 'بيع'),
                  ],
                ),
              if (app.isCrops) const SizedBox(height: 10),
              MiniBarChart(
                dates: [for (final e in d.series) e.date],
                a: [for (final e in d.series) app.isCrops ? e.b : e.a],
                b: app.isCrops ? [for (final e in d.series) e.a] : null,
                colorA: app.isCrops ? AppColors.crops : AppColors.primary,
                colorB: AppColors.appliances,
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

/// Records from the first version of the app: keep them or delete them.
class _OldVersionCard extends StatelessWidget {
  const _OldVersionCard();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (app.oldVersionRecords == 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.warnSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.warn.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'لقينا بيانات من النسخة القديمة من الأبلكيشن (${app.oldVersionRecords} حركة)',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'لو كانت تجارب امسحها وابدأ على نضيف. لو كانت بيانات حقيقية انقلها هنا وهتترفع على السيرفر.',
                    style: TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.bad),
                          onPressed: () async {
                            final ok = await confirmDialog(
                              context,
                              title: 'مسح بيانات النسخة القديمة',
                              message: 'البيانات القديمة هتتمسح من الموبايل ده ومش هترجع. متأكد؟',
                              ok: 'امسحها',
                              danger: true,
                            );
                            if (ok) await app.discardOldVersion();
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('امسحها'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            final n = await app.importOldVersion();
                            if (context.mounted) toast(context, 'اتنقل $n حاجة من النسخة القديمة');
                          },
                          icon: const Icon(Icons.move_down),
                          label: const Text('انقلها'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _GlassNumber extends StatelessWidget {
  const _GlassNumber({required this.label, required this.value, this.sub, this.onTap});

  final String label;
  final String value;
  final String? sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                ),
                if (sub != null)
                  Text(
                    sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      );
}
