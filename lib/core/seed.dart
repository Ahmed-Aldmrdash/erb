import 'db/app_db.dart';
import 'db/schema.dart';

const defaultCompanyName = 'مؤسسة الدمرداش';

/// Starter data of a division. The ids are fixed, so several phones seeding
/// at the same time create the same rows instead of duplicates. In cloud mode
/// this runs after the first download, so it never overwrites server data.
Future<void> seedDefaults(AppDb db) async {
  if (await db.getMeta('seeded') == '1') return;
  final d = db.division;
  await db.write((w) async {
    if (d == Division.crops) {
      const crops = [
        ['5eed0000-0000-4000-8000-000000000001', 'قمح', 'أردب', 150],
        ['5eed0000-0000-4000-8000-000000000002', 'ذرة شامية', 'أردب', 140],
        ['5eed0000-0000-4000-8000-000000000003', 'أرز شعير', 'طن', 1000],
        ['5eed0000-0000-4000-8000-000000000004', 'قطن زهر', 'قنطار', 157.5],
        ['5eed0000-0000-4000-8000-000000000005', 'فول بلدي', 'أردب', 155],
        ['5eed0000-0000-4000-8000-000000000006', 'بصل', 'طن', 1000],
      ];
      for (final c in crops) {
        await w.insertIfAbsent('crops', {'id': c[0], 'name': c[1], 'unit_name': c[2], 'kg_per_unit': c[3]});
      }
      await w.insertIfAbsent('warehouses', {'id': '5eed0000-0000-4000-8000-000000000101', 'name': 'الشونة الرئيسية'});
      await w.insertIfAbsent('cash_boxes', {'id': '5eed0000-0000-4000-8000-000000000201', 'name': 'خزنة التجارة'});
    } else {
      await w.insertIfAbsent('warehouses', {'id': '5eed0000-0000-4000-8000-000000000102', 'name': 'مخزن المعرض'});
      await w.insertIfAbsent('cash_boxes', {'id': '5eed0000-0000-4000-8000-000000000202', 'name': 'خزنة المعرض'});
    }
    await w.insertIfAbsent('app_settings', {'id': '$d:company_name', 'value': defaultCompanyName});
  });
  await db.setMeta('seeded', '1');
}
