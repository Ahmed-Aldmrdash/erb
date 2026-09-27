import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../ui/pickers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// جرد: count what is really on the shelves; every difference with the system
/// becomes a stock adjustment signed by whoever did the count.
class StocktakeScreen extends StatefulWidget {
  const StocktakeScreen({super.key});

  @override
  State<StocktakeScreen> createState() => _StocktakeScreenState();
}

class _StocktakeScreenState extends State<StocktakeScreen> {
  DbRow? _warehouse;
  String _search = '';
  final Map<String, TextEditingController> _counted = {};
  final Map<String, double> _system = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    app.crops.warehouses().then((ws) {
      if (mounted && ws.isNotEmpty) setState(() => _warehouse = ws.first);
    });
  }

  @override
  void dispose() {
    for (final c in _counted.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String id) => _counted.putIfAbsent(id, TextEditingController.new);

  int get _entered => _counted.values.where((c) => c.text.trim().isNotEmpty).length;

  Future<void> _save() async {
    final lines = [
      for (final e in _counted.entries)
        if (e.value.text.trim().isNotEmpty)
          (itemId: e.key, system: _system[e.key] ?? 0, counted: parseNum(e.value.text)),
    ];
    if (lines.isEmpty) {
      toast(context, 'اكتب الكمية الموجودة لصنف واحد على الأقل', error: true);
      return;
    }
    final diffs = lines.where((l) => (l.counted - l.system).abs() >= 0.0005).length;
    final ok = await confirmDialog(
      context,
      title: 'حفظ الجرد',
      message: 'اتجرد ${lines.length} صنف، منهم $diffs مختلف عن السيستم وهيتعملهم تسوية. تكمل؟',
      ok: 'حفظ',
    );
    if (!ok) return;
    setState(() => _busy = true);
    final n = await app.crops.saveStocktake(
      itemType: 'product',
      warehouseId: s(_warehouse!['id']),
      date: todayStr(),
      lines: lines,
    );
    if (!mounted) return;
    toast(context, n == 0 ? 'كل الأصناف مظبوطة، مفيش تسوية' : 'اتعمل تسوية لـ $n صنف');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('جرد المخزن')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: PickField(
                label: 'المخزن',
                value: _warehouse == null ? null : s(_warehouse!['name']),
                icon: Icons.warehouse_outlined,
                onTap: () async {
                  final w = await pickWarehouse(context);
                  if (w != null) {
                    setState(() {
                      _warehouse = w;
                      _counted.clear();
                    });
                  }
                },
              ),
            ),
            SearchField(onChanged: (v) => setState(() => _search = v), hint: 'دور على صنف'),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text('اكتب العدد الموجود فعلاً قدام كل صنف. اللي تسيبه فاضي مش هيتغير.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ),
            Expanded(
              child: _warehouse == null
                  ? const EmptyView(icon: Icons.warehouse_outlined, text: 'اختار المخزن')
                  : DbBuilder<List<DbRow>>(
                      queryKey: (_warehouse!['id'], _search),
                      query: () => app.appliances.productsAtWarehouse(s(_warehouse!['id']), search: _search),
                      builder: (context, rows) {
                        for (final r in rows) {
                          _system[s(r['id'])] = n(r['stock']);
                        }
                        if (rows.isEmpty) return const EmptyView(icon: Icons.inventory_2_outlined, text: 'مفيش أصناف');
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final r = rows[i];
                            final ctrl = _ctrl(s(r['id']));
                            final sys = n(r['stock']);
                            final entered = ctrl.text.trim().isNotEmpty;
                            final diff = parseNum(ctrl.text) - sys;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(s(r['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                                        Text('على السيستم: ${qty(sys)} ${s(r['unit'])}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                                        if (entered && diff.abs() >= 0.0005)
                                          Text(
                                            diff > 0 ? 'زيادة ${qty(diff)}' : 'عجز ${qty(-diff)}',
                                            style: TextStyle(color: diff > 0 ? AppColors.good : AppColors.bad, fontWeight: FontWeight.w700, fontSize: 12.5),
                                          )
                                        else if (entered)
                                          const Text('مظبوط', style: TextStyle(color: AppColors.good, fontSize: 12.5)),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: 100,
                                    child: NumField(controller: ctrl, label: 'الموجود', onChanged: (_) => setState(() {})),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
        bottomNavigationBar: SaveBar(
          busy: _busy,
          label: 'حفظ الجرد ($_entered صنف)',
          onSave: _warehouse == null ? null : _save,
        ),
      );
}
