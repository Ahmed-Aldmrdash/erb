import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// صفحة الحساب: the account drawn like a page of the paper account book —
/// cream paper, ruled lines, a red margin and a handwritten (رقعة) header.
class PaperLedger extends StatelessWidget {
  const PaperLedger({super.key, required this.party, required this.rows, this.onTap, this.periodText});

  final DbRow party;
  final List<DbRow> rows;
  final void Function(DbRow r)? onTap;
  final String? periodText;

  static const _dateW = 52.0;
  static const _amountW = 64.0;
  static const _balanceW = 70.0;

  @override
  Widget build(BuildContext context) {
    double debit = 0, credit = 0;
    for (final r in rows) {
      debit += n(r['debit']);
      credit += n(r['credit']);
    }
    final balance = rows.isEmpty ? 0.0 : n(rows.last['balance']);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.paperLine),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Stack(
        children: [
          // The red margin line after the date column.
          const PositionedDirectional(
            start: _dateW + 10,
            top: 0,
            bottom: 0,
            child: SizedBox(width: 1.4, child: ColoredBox(color: AppColors.paperMargin)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              Container(height: 2, color: AppColors.paperMargin.withValues(alpha: 0.6)),
              const SizedBox(height: 2),
              Container(height: 1, color: AppColors.paperMargin.withValues(alpha: 0.6)),
              _columns(),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Text('الصفحة لسه فاضية',
                      textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Ruqaa', fontSize: 20, color: AppColors.muted)),
                ),
              for (final r in rows) _line(r),
              _footer(debit, credit, balance),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(app.companyName,
                      style: const TextStyle(fontFamily: 'Ruqaa', fontSize: 17, color: AppColors.muted, height: 1.2)),
                ),
                Text(showDate(todayStr()), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
            const Text('صفحة حساب',
                style: TextStyle(fontFamily: 'Ruqaa', fontSize: 22, color: AppColors.paperMargin, height: 1.3)),
            Text(s(party['name']),
                style: const TextStyle(fontFamily: 'Ruqaa', fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.ink, height: 1.3)),
            if (s(party['phone']).isNotEmpty || periodText != null)
              Text(
                [if (s(party['phone']).isNotEmpty) s(party['phone']), ?periodText].join('  •  '),
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
          ],
        ),
      );

  Widget _columns() => Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.paperLine))),
        child: const Row(
          children: [
            SizedBox(width: _dateW, child: _Head('التاريخ')),
            SizedBox(width: 12),
            Expanded(child: _Head('البيان', start: true)),
            SizedBox(width: _amountW, child: _Head('ادّيناه', sub: 'عليه')),
            SizedBox(width: _amountW, child: _Head('خدنا منه', sub: 'له')),
            SizedBox(width: _balanceW, child: _Head('الرصيد', sub: 'لينا / علينا')),
          ],
        ),
      );

  Widget _line(DbRow r) {
    final d = parseDate(r['date']);
    final details = [
      if (s(r['number']).isNotEmpty) 'رقم ${s(r['number'])}',
      if (s(r['category']).isNotEmpty) s(r['category']),
      if (s(r['notes']).isNotEmpty) s(r['notes']),
      if (s(r['handled_by']).isNotEmpty)
        '${r['kind'] == 'receipt' ? 'استلمها' : 'سلّمها'}: ${s(r['handled_by'])}',
      if (s(r['by_name']).isNotEmpty && s(r['by_name']) != s(r['handled_by'])) 'سجلها: ${s(r['by_name'])}',
    ];
    final bal = n(r['balance']);
    final carried = r['doc_type'] == 'carried' || r['doc_type'] == 'opening';
    return InkWell(
      onTap: carried || onTap == null ? null : () => onTap!(r),
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.paperLine))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _dateW,
              child: d == null
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        Text('${d.day}/${d.month}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 13)),
                        Text('${d.year}', style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                      ],
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s(r['title']),
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.ink, fontStyle: carried ? FontStyle.italic : null)),
                  if (details.isNotEmpty)
                    Text(details.join(' • '), style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4)),
                ],
              ),
            ),
            SizedBox(width: _amountW, child: _amount(n(r['debit']), AppColors.bad)),
            SizedBox(width: _amountW, child: _amount(n(r['credit']), AppColors.good)),
            SizedBox(
              width: _balanceW,
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(money(bal.abs()), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink, fontSize: 13)),
                  ),
                  Text(balanceInfo(bal).word,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: balanceInfo(bal).color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amount(double v, Color color) => v <= 0
      ? const SizedBox.shrink()
      : FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(money(v), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        );

  Widget _footer(double debit, double credit, double balance) => Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: _dateW + 12),
                const Expanded(child: Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink))),
                SizedBox(width: _amountW, child: _amount(debit, AppColors.bad)),
                SizedBox(width: _amountW, child: _amount(credit, AppColors.good)),
                const SizedBox(width: _balanceW),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                balanceInfo(balance).text,
                style: TextStyle(
                  fontFamily: 'Ruqaa',
                  fontSize: 24,
                  color: balance > 0.009 ? AppColors.good : (balance < -0.009 ? AppColors.bad : AppColors.muted),
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      );
}

class _Head extends StatelessWidget {
  const _Head(this.text, {this.start = false, this.sub});

  final String text;
  final bool start;

  /// The paper book's own word under the column name.
  final String? sub;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: start ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Text(
            text,
            textAlign: start ? TextAlign.start : TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.ink),
          ),
          if (sub != null)
            Text(sub!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        ],
      );
}
