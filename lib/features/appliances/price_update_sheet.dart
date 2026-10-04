import 'package:flutter/material.dart';

import '../../core/util/format.dart';
import '../../data/appliances_repo.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Shown before a purchase invoice is saved: the purchase price of these
/// products changed, so their selling prices move by the same ratio.
///
/// Returns the updates to apply (the user can untick a product or type
/// another price), or null when the user goes back to the invoice.
Future<List<PriceUpdate>?> showPriceUpdateSheet(BuildContext context, List<PriceUpdate> updates) =>
    showModalBottomSheet<List<PriceUpdate>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PriceUpdateSheet(updates: updates),
    );

class _PriceUpdateSheet extends StatefulWidget {
  const _PriceUpdateSheet({required this.updates});

  final List<PriceUpdate> updates;

  @override
  State<_PriceUpdateSheet> createState() => _PriceUpdateSheetState();
}

class _PriceUpdateSheetState extends State<_PriceUpdateSheet> {
  late final Set<String> _on = {for (final u in widget.updates) u.productId};

  Future<void> _edit(PriceUpdate u) async {
    final retail = TextEditingController(text: numText(u.retail));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(u.name),
        content: StatefulBuilder(
          builder: (c, setInner) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('سعر الشراء الجديد ${egp(u.cost)}', style: const TextStyle(color: AppColors.muted)),
              const Gap(),
              NumField(
                controller: retail,
                label: 'سعر البيع',
                suffix: currency,
                autofocus: true,
                onChanged: (_) => setInner(() {}),
                helper: parseNum(retail.text) > u.cost
                    ? 'مكسب ${money(parseNum(retail.text) - u.cost)}'
                    : 'أقل من سعر الشراء!',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تمام')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      u.retail = parseNum(retail.text);
      _on.add(u.productId);
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              children: [
                Text('الأسعار بعد الشراء', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Gap(4),
                Text(
                  'سعر الشراء اتغير، فسعر البيع بيزيد بنفس النسبة ويتقرب لفوق. دوس على أي صنف لو عايز تكتب سعر بإيدك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.5, fontSize: 13),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              children: [
                for (final u in widget.updates)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _edit(u),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _on.contains(u.productId),
                              onChanged: (v) => setState(() => v == true ? _on.add(u.productId) : _on.remove(u.productId)),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(u.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  _line('الشراء', u.oldCost, u.cost),
                                  _line('البيع', u.oldRetail, u.retail),
                                ],
                              ),
                            ),
                            const Icon(Icons.edit_outlined, size: 18, color: AppColors.muted),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SaveBar(
            label: 'احفظ الفاتورة والأسعار',
            onSave: () => Navigator.pop(context, [for (final u in widget.updates) if (_on.contains(u.productId)) u]),
            extra: OutlinedButton(
              onPressed: () => Navigator.pop(context, const <PriceUpdate>[]),
              child: const Text('سيب الأسعار'),
            ),
          ),
        ],
      );

  Widget _line(String label, double from, double to) {
    final changed = (from - to).abs() > 0.009;
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
          if (from > 0)
            Text(
              money(from),
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.muted,
                decoration: changed ? TextDecoration.lineThrough : null,
              ),
            ),
          if (changed) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.arrow_back, size: 12, color: AppColors.muted),
            ),
            Text(
              money(to),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: to > from ? AppColors.good : AppColors.bad,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
