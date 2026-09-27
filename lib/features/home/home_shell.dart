import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../ui/widgets.dart';
import '../accounts/parties_screen.dart';
import '../appliances/products_screen.dart';
import '../crops/crop_stock_screen.dart';
import '../crops/crop_trades_screen.dart';
import '../more/more_screen.dart';
import '../pos/pos_screen.dart';
import 'dashboard_screen.dart';

/// Selected bottom tab; screens can switch tabs (e.g. the dashboard opens the
/// cashier).
final homeTab = ValueNotifier<String>('home');

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.page);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  @override
  void initState() {
    super.initState();
    homeTab.value = 'home';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notice = app.takeNotice();
      if (notice != null && mounted) toast(context, notice);
    });
  }

  Map<String, _Tab> get _tabs => app.isCrops
      ? const {
          'home': _Tab('الرئيسية', Icons.space_dashboard_outlined, Icons.space_dashboard, DashboardScreen()),
          'ops': _Tab('العمليات', Icons.local_shipping_outlined, Icons.local_shipping, CropTradesScreen(asTab: true)),
          'stock': _Tab('المخزن', Icons.warehouse_outlined, Icons.warehouse, CropStockScreen()),
          'accounts': _Tab('الحسابات', Icons.menu_book_outlined, Icons.menu_book, PartiesScreen(asTab: true)),
          'more': _Tab('المزيد', Icons.grid_view_outlined, Icons.grid_view_rounded, MoreScreen()),
        }
      : const {
          'home': _Tab('الرئيسية', Icons.space_dashboard_outlined, Icons.space_dashboard, DashboardScreen()),
          'pos': _Tab('الكاشير', Icons.point_of_sale_outlined, Icons.point_of_sale, PosScreen()),
          'stock': _Tab('المخزن', Icons.inventory_2_outlined, Icons.inventory_2, ProductsScreen(asTab: true)),
          'accounts': _Tab('الحسابات', Icons.menu_book_outlined, Icons.menu_book, PartiesScreen(asTab: true)),
          'more': _Tab('المزيد', Icons.grid_view_outlined, Icons.grid_view_rounded, MoreScreen()),
        };

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: homeTab,
        builder: (context, current, _) {
          final tabs = _tabs;
          final key = tabs.containsKey(current) ? current : 'home';
          final keys = tabs.keys.toList();
          return PopScope(
            // Back on another tab goes to the dashboard first.
            canPop: key == 'home',
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) homeTab.value = 'home';
            },
            child: Scaffold(
              body: KeyedSubtree(key: ValueKey(key), child: tabs[key]!.page),
              bottomNavigationBar: NavigationBar(
                selectedIndex: keys.indexOf(key),
                onDestinationSelected: (i) => homeTab.value = keys[i],
                destinations: [
                  for (final t in tabs.values)
                    NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label),
                ],
              ),
            ),
          );
        },
      );
}
