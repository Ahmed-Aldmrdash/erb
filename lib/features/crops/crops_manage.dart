import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Crop types and their trading unit (ardeb, ton, kantar...).
class CropsScreen extends StatelessWidget {
  const CropsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('أصناف المحاصيل')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showCropForm(context),
          icon: const Icon(Icons.add),
          label: const Text('محصول جديد'),
        ),
        body: DbBuilder<List<DbRow>>(
          query: () => app.crops.crops(activeOnly: false),
          builder: (context, rows) {
            if (rows.isEmpty) return const EmptyView(icon: Icons.grass, text: 'مفيش محاصيل');
            return ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 90),
              children: [
                TileGroup(children: [
                  for (final c in rows)
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.cropsSoft,
                        child: Icon(Icons.grass, color: AppColors.crops),
                      ),
                      title: Text('${s(c['name'])}${n(c['active']) == 1 ? '' : ' (موقوف)'}'),
                      subtitle: Text('ال${s(c['unit_name'])} = ${qty(n(c['kg_per_unit']))} كجم'),
                      trailing: Text(unitsOf(n(c['stock_kg']), s(c['unit_name']), n(c['kg_per_unit']))),
                      onTap: () => showCropForm(context, crop: c),
                    ),
                ]),
              ],
            );
          },
        ),
      );
}

const _unitPresets = <String, double>{
  'أردب': 150,
  'طن': 1000,
  'قنطار': 157.5,
  'ضريبة': 945,
  'شكارة': 50,
  'كيلو': 1,
};

Future<void> showCropForm(BuildContext context, {DbRow? crop}) async {
  final name = TextEditingController(text: s(crop?['name']));
  final unit = TextEditingController(text: crop == null ? 'أردب' : s(crop['unit_name']));
  final kg = TextEditingController(text: crop == null ? '150' : numText(n(crop['kg_per_unit'])));
  var active = crop == null || n(crop['active']) == 1;
  final formKey = GlobalKey<FormState>();
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(crop == null ? 'محصول جديد' : 'تعديل المحصول'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextF(controller: name, label: 'اسم المحصول', validator: requiredText),
                const Gap(),
                const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('وحدة البيع والشراء', style: TextStyle(color: AppColors.muted)),
                ),
                const Gap(6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in _unitPresets.entries)
                      ChoiceChip(
                        label: Text(e.key),
                        selected: unit.text == e.key,
                        showCheckmark: false,
                        onSelected: (_) => setState(() {
                          unit.text = e.key;
                          kg.text = numText(e.value);
                        }),
                      ),
                  ],
                ),
                const Gap(),
                Row(
                  children: [
                    Expanded(child: TextF(controller: unit, label: 'اسم الوحدة', validator: requiredText)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: NumField(controller: kg, label: 'الوحدة كام كيلو', suffix: 'كجم', validator: positiveNumber),
                    ),
                  ],
                ),
                const Gap(6),
                const Text(
                  'مثلاً: أردب القمح 150 كجم، أردب الذرة 140 كجم، أردب الفول 155 كجم.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
                if (crop != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('شغال'),
                    value: active,
                    onChanged: (v) => setState(() => active = v),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (crop != null)
            TextButton(
              onPressed: () async {
                final err = await app.crops.deleteCrop(s(crop['id']));
                if (!c.mounted) return;
                if (err != null) {
                  toast(c, err, error: true);
                } else {
                  Navigator.pop(c);
                }
              },
              child: const Text('حذف', style: TextStyle(color: AppColors.bad)),
            ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await app.crops.saveCrop({
                'name': name.text.trim(),
                'unit_name': unit.text.trim(),
                'kg_per_unit': parseNum(kg.text),
                'active': active,
              }, id: crop == null ? null : s(crop['id']));
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
}

/// Warehouses of the open division (shonas for the trade, stores for the
/// showroom).
class WarehousesScreen extends StatelessWidget {
  const WarehousesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(app.isCrops ? 'المخازن والشون' : 'المخازن والفروع')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showForm(context),
          icon: const Icon(Icons.add),
          label: const Text('مخزن جديد'),
        ),
        body: DbBuilder<List<DbRow>>(
          query: () => app.crops.warehouses(activeOnly: false),
          builder: (context, rows) {
            if (rows.isEmpty) return const EmptyView(icon: Icons.warehouse_outlined, text: 'مفيش مخازن');
            return ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 90),
              children: [
                TileGroup(children: [
                  for (final w in rows)
                    ListTile(
                      leading: const Icon(Icons.warehouse_outlined),
                      title: Text('${s(w['name'])}${n(w['active']) == 1 ? '' : ' (موقوف)'}'),
                      subtitle: s(w['notes']).isEmpty ? null : Text(s(w['notes'])),
                      onTap: () => _showForm(context, w: w),
                    ),
                ]),
              ],
            );
          },
        ),
      );

  Future<void> _showForm(BuildContext context, {DbRow? w}) async {
    final name = TextEditingController(text: s(w?['name']));
    final notes = TextEditingController(text: s(w?['notes']));
    var active = w == null || n(w['active']) == 1;
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(w == null ? 'مخزن جديد' : 'تعديل المخزن'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextF(controller: name, label: 'الاسم', validator: requiredText),
                const Gap(),
                TextF(controller: notes, label: 'العنوان / ملاحظات'),
                if (w != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('شغال'),
                    value: active,
                    onChanged: (v) => setState(() => active = v),
                  ),
              ],
            ),
          ),
          actions: [
            if (w != null)
              TextButton(
                onPressed: () async {
                  final err = await app.crops.deleteWarehouse(s(w['id']));
                  if (!c.mounted) return;
                  if (err != null) {
                    toast(c, err, error: true);
                  } else {
                    Navigator.pop(c);
                  }
                },
                child: const Text('حذف', style: TextStyle(color: AppColors.bad)),
              ),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                await app.crops.saveWarehouse({
                  'name': name.text.trim(),
                  'notes': notes.text.trim(),
                  'active': active,
                }, id: w == null ? null : s(w['id']));
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
