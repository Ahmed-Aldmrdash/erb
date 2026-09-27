import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../ui/share.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../accounts/cash_boxes.dart';

/// يومية الخزنة: for one day, every cash box's opening, in, out and closing
/// with all the day's movements — the end-of-day check.
class DailyCashScreen extends StatefulWidget {
  const DailyCashScreen({super.key});

  @override
  State<DailyCashScreen> createState() => _DailyCashScreenState();
}

class _DailyCashScreenState extends State<DailyCashScreen> {
  DateTime _day = DateTime.now();

  String get _date => dateStr(_day);

  void _shift(int days) => setState(() => _day = _day.add(Duration(days: days)));

  String _summary(List<DbRow> boxes, List<DbRow> rows) {
    final lines = <String>['يومية الخزنة - ${app.companyName} (${app.divisionName})', longDate(_day), ''];
    for (final b in boxes) {
      lines
        ..add('${s(b['name'])}:')
        ..add('  أول اليوم ${egp(n(b['opening']))}')
        ..add('  داخل ${egp(n(b['amount_in']))} • خارج ${egp(n(b['amount_out']))}')
        ..add('  آخر اليوم ${egp(n(b['closing']))}');
    }
    lines
      ..add('')
      ..add('عدد الحركات: ${rows.length}')
      ..add('— ${app.person}');
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) => DbBuilder<({List<DbRow> boxes, List<DbRow> rows})>(
        queryKey: _date,
        query: () => app.accounts.cashDay(_date),
        builder: (context, d) {
          final totalIn = d.boxes.fold<double>(0, (a, b) => a + n(b['amount_in']));
          final totalOut = d.boxes.fold<double>(0, (a, b) => a + n(b['amount_out']));
          final closing = d.boxes.fold<double>(0, (a, b) => a + n(b['closing']));
          final isToday = _date == todayStr();
          return Scaffold(
            appBar: AppBar(
              title: const Text('يومية الخزنة'),
              actions: [
                IconButton(
                  tooltip: 'إرسال على واتساب',
                  onPressed: () => openWhatsApp(context, null, _summary(d.boxes, d.rows)),
                  icon: const Icon(Icons.share_outlined),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left), tooltip: 'اليوم اللي قبله'),
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final p = await showDatePicker(
                              context: context,
                              initialDate: _day,
                              firstDate: DateTime(2015),
                              lastDate: DateTime(2100),
                            );
                            if (p != null) setState(() => _day = p);
                          },
                          child: Text(isToday ? 'النهارده • ${longDate(_day)}' : longDate(_day),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      IconButton(
                        onPressed: isToday ? null : () => _shift(1),
                        icon: const Icon(Icons.chevron_right),
                        tooltip: 'اليوم اللي بعده',
                      ),
                    ],
                  ),
                ),
                CardRow(children: [
                  StatCard(label: 'داخل', value: egp(totalIn), color: AppColors.good, icon: Icons.south_west),
                  StatCard(label: 'خارج', value: egp(totalOut), color: AppColors.bad, icon: Icons.north_east),
                  StatCard(label: 'آخر اليوم', value: egp(closing), icon: Icons.account_balance_wallet_outlined),
                ]),
                const SectionTitle('كل خزنة'),
                for (final b in d.boxes)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Box(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(s(b['name']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                          const Gap(4),
                          InfoRow('أول اليوم', egp(n(b['opening']))),
                          InfoRow('داخل', egp(n(b['amount_in'])), color: AppColors.good),
                          InfoRow('خارج', egp(n(b['amount_out'])), color: AppColors.bad),
                          const Divider(),
                          InfoRow('آخر اليوم', egp(n(b['closing'])), bold: true),
                        ],
                      ),
                    ),
                  ),
                SectionTitle('حركات اليوم (${d.rows.length})'),
                if (d.rows.isEmpty)
                  const EmptyView(icon: Icons.inbox_outlined, text: 'مفيش حركات في اليوم ده')
                else
                  TileGroup(children: [for (final r in d.rows.reversed) CashMoveTile(r)]),
              ],
            ),
          );
        },
      );
}
