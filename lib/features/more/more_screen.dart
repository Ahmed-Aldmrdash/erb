import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/schema.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../accounts/cash_boxes.dart';
import '../accounts/parties_screen.dart';
import '../accounts/vouchers_screen.dart';
import '../activity/activity_screen.dart';
import '../appliances/installments_screen.dart';
import '../appliances/invoices_screen.dart';
import '../appliances/labels_screen.dart';
import '../appliances/products_screen.dart';
import '../cash/daily_cash_screen.dart';
import '../common/excel_export.dart';
import '../common/stock_move_form.dart';
import '../crops/crop_trades_screen.dart';
import '../crops/crops_manage.dart';
import '../notes/notes_screen.dart';
import '../reports/reports_screen.dart';
import '../reports/season_report_screen.dart';
import '../settings/backup_screen.dart';
import '../settings/company_settings.dart';
import '../settings/sync_screen.dart';
import '../stock/stocktake_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المزيد'), actions: const [SyncButton()]),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _accountCard(context),
            const SectionTitle('المتابعة'),
            ActionGrid(columns: 4, children: [
              DbBuilder<int>(
                query: app.notes.openCount,
                builder: (context, open) => ActionTile(
                  icon: Icons.sticky_note_2_outlined,
                  label: 'التذكرة',
                  color: AppColors.accounts,
                  badge: open,
                  onTap: () => push(context, const NotesScreen()),
                ),
              ),
              ActionTile(
                icon: Icons.history,
                label: 'سجل العمليات',
                color: AppColors.muted,
                onTap: () => push(context, const ActivityScreen()),
              ),
              ActionTile(
                icon: Icons.insights_outlined,
                label: 'التقارير والأرباح',
                color: AppColors.good,
                onTap: () => push(context, const ReportsScreen()),
              ),
              ActionTile(
                icon: Icons.call_received,
                label: 'المديونيات',
                color: AppColors.good,
                onTap: () => push(context, const PartiesScreen(balanceFilter: 1)),
              ),
            ]),
            const SectionTitle('الفلوس'),
            ActionGrid(columns: 4, children: [
              ActionTile(
                icon: Icons.account_balance_wallet_outlined,
                label: 'الخزن',
                onTap: () => push(context, const CashBoxesScreen()),
              ),
              ActionTile(
                icon: Icons.today_outlined,
                label: 'يومية الخزنة',
                color: AppColors.appliances,
                onTap: () => push(context, const DailyCashScreen()),
              ),
              ActionTile(
                icon: Icons.shopping_bag_outlined,
                label: 'المصروفات',
                color: AppColors.warn,
                onTap: () => push(context, const VouchersScreen(kinds: ['expense'], title: 'المصروفات')),
              ),
              ActionTile(
                icon: Icons.swap_vert,
                label: 'كل حركات الفلوس',
                color: AppColors.accounts,
                onTap: () => push(context, const VouchersScreen(title: 'حركات الفلوس')),
              ),
            ]),
            if (app.isCrops) ..._trade(context) else ..._showroom(context),
            const SectionTitle('الإعدادات'),
            TileGroup(children: [
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('بيانات المؤسسة والفاتورة'),
                subtitle: Text('الاسم والعنوان والتليفون في ${app.divisionName}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => push(context, const CompanySettingsScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.table_view_outlined, color: ExcelExport.green),
                title: const Text('تنزيل كل البيانات (Excel)'),
                subtitle: Text(app.isCrops
                    ? 'المحاصيل والتوريد والبيع والحسابات والخزن في ملف واحد'
                    : 'الأصناف والفواتير والأقساط والحسابات والخزن في ملف واحد'),
                trailing: const Icon(Icons.download_rounded),
                onTap: () => ExcelExport.export(context, 'بيانات ${app.divisionName}', ExcelExport.everything),
              ),
              ListTile(
                leading: Icon(Icons.shield_outlined, color: AppColors.primary),
                title: const Text('نسخة احتياطية'),
                subtitle: const Text('احفظ نسخة من كل البيانات، أو رجّع نسخة قديمة'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => push(context, const BackupScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('الحساب والمزامنة'),
                subtitle: Text(app.isCloud ? 'كلمات المرور، تسجيل الخروج' : 'شغال على الموبايل ده بس'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => push(context, const AccountScreen()),
              ),
              if (app.isManager)
                ListTile(
                  leading: Icon(Icons.swap_horiz, color: app.isCrops ? AppColors.appliances : AppColors.crops),
                  title: Text('افتح ${Division.names[_other]}'),
                  subtitle: const Text('الإدارة بتشوف القسمين'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => app.switchDivision(_other),
                ),
            ]),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'الدمرداش - الإصدار 2.4',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          ],
        ),
      );

  String get _other => app.isCrops ? Division.appliances : Division.crops;

  Widget _accountCard(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Material(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => push(context, const AccountScreen()),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: ListenableBuilder(
                listenable: app,
                builder: (context, _) => Row(
                  children: [
                    LetterAvatar(app.person, radius: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(app.person.isEmpty ? 'مين معايا؟' : app.person,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          Text(
                            app.isCloud ? '${app.departmentName} • ${app.divisionName}' : '${app.divisionName} • بدون سيرفر',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  List<Widget> _showroom(BuildContext context) => [
        const SectionTitle('البيع والشراء'),
        ActionGrid(columns: 4, children: [
          ActionTile(
            icon: Icons.receipt_long_outlined,
            label: 'فواتير البيع',
            onTap: () => push(context, const InvoicesScreen(kind: 'sale')),
          ),
          ActionTile(
            icon: Icons.add_shopping_cart,
            label: 'فواتير الشراء',
            color: AppColors.crops,
            onTap: () => push(context, const InvoicesScreen(kind: 'purchase')),
          ),
          ActionTile(
            icon: Icons.assignment_return_outlined,
            label: 'المرتجعات',
            color: AppColors.warn,
            onTap: () => push(context, const InvoicesScreen(kind: 'sale_return')),
          ),
          ActionTile(
            icon: Icons.event_available_outlined,
            label: 'الأقساط',
            color: AppColors.appliances,
            onTap: () => push(context, const InstallmentsScreen()),
          ),
        ]),
        const SectionTitle('المخزن'),
        ActionGrid(columns: 4, children: [
          ActionTile(
            icon: Icons.inventory_2_outlined,
            label: 'الأصناف',
            onTap: () => push(context, const ProductsScreen()),
          ),
          ActionTile(
            icon: Icons.local_offer_outlined,
            label: 'ملصقات الأسعار',
            color: AppColors.appliances,
            onTap: () => push(context, const LabelsScreen()),
          ),
          ActionTile(
            icon: Icons.fact_check_outlined,
            label: 'جرد المخزن',
            color: AppColors.good,
            onTap: () => push(context, const StocktakeScreen()),
          ),
          ActionTile(
            icon: Icons.swap_horiz,
            label: 'حركات المخزن',
            color: AppColors.accounts,
            onTap: () => push(context, const StockMovesScreen(itemType: 'product')),
          ),
          ActionTile(
            icon: Icons.warehouse_outlined,
            label: 'المخازن',
            color: AppColors.muted,
            onTap: () => push(context, const WarehousesScreen()),
          ),
        ]),
      ];

  List<Widget> _trade(BuildContext context) => [
        const SectionTitle('المحاصيل'),
        ActionGrid(columns: 4, children: [
          ActionTile(
            icon: Icons.summarize_outlined,
            label: 'تقرير الموسم',
            color: AppColors.good,
            onTap: () => push(context, const SeasonReportScreen()),
          ),
          ActionTile(
            icon: Icons.move_to_inbox_outlined,
            label: 'التوريدات',
            onTap: () => push(context, const CropTradesScreen(kind: 'purchase')),
          ),
          ActionTile(
            icon: Icons.local_shipping_outlined,
            label: 'المبيعات',
            color: AppColors.appliances,
            onTap: () => push(context, const CropTradesScreen(kind: 'sale')),
          ),
          ActionTile(
            icon: Icons.volunteer_activism_outlined,
            label: 'السلف',
            color: AppColors.accent,
            onTap: () => push(context, const VouchersScreen(kinds: ['advance'], title: 'سلف الفلاحين')),
          ),
          ActionTile(
            icon: Icons.agriculture_outlined,
            label: 'الفلاحين',
            color: AppColors.crops,
            onTap: () => push(context, const PartiesScreen(kind: 'farmer')),
          ),
          ActionTile(
            icon: Icons.grass,
            label: 'أصناف المحاصيل',
            color: AppColors.good,
            onTap: () => push(context, const CropsScreen()),
          ),
          ActionTile(
            icon: Icons.warehouse_outlined,
            label: 'المخازن والشون',
            color: AppColors.muted,
            onTap: () => push(context, const WarehousesScreen()),
          ),
          ActionTile(
            icon: Icons.swap_horiz,
            label: 'حركات المخزن',
            color: AppColors.accounts,
            onTap: () => push(context, const StockMovesScreen(itemType: 'crop')),
          ),
          ActionTile(
            icon: Icons.factory_outlined,
            label: 'التجار والمصانع',
            color: AppColors.appliances,
            onTap: () => push(context, const PartiesScreen(kind: 'trader')),
          ),
        ]),
      ];
}
