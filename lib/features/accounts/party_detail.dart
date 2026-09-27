import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/appliances_repo.dart';
import '../../data/labels.dart';
import '../../ui/share.dart';
import '../../ui/theme.dart';
import '../../ui/wa_text.dart';
import '../../ui/widgets.dart';
import '../common/open_doc.dart';
import '../common/pdf_docs.dart';
import '../notes/notes_screen.dart';
import 'money_sheet.dart';
import 'paper_ledger.dart';
import 'party_form.dart';
import '../appliances/installments_screen.dart';

/// The account of one customer / supplier / farmer / trader: balance, quick
/// money in/out, reminders and the paper-like account page.
class PartyDetailScreen extends StatefulWidget {
  const PartyDetailScreen({super.key, required this.partyId});

  final String partyId;

  @override
  State<PartyDetailScreen> createState() => _PartyDetailScreenState();
}

class _PartyDetailScreenState extends State<PartyDetailScreen> {
  Period _period = Period.all();

  Future<({DbRow? party, List<DbRow> ledger, ({double gave, double took}) totals, List<InstallmentRow> installments})>
      _load() async => (
        party: await app.accounts.party(widget.partyId),
        installments: app.isCrops ? const <InstallmentRow>[] : await app.appliances.openInstallments(partyId: widget.partyId),
        ledger: await app.accounts.partyLedger(
          widget.partyId,
          from: _period == Period.all() ? null : _period.from,
          to: _period == Period.all() ? null : _period.to,
        ),
        totals: await app.accounts.partyTotals(widget.partyId),
      );

  @override
  Widget build(BuildContext context) =>
      DbBuilder<({DbRow? party, List<DbRow> ledger, ({double gave, double took}) totals, List<InstallmentRow> installments})>(
        queryKey: _period,
        query: _load,
        builder: (context, d) {
          final p = d.party;
          if (p == null || n(p['deleted']) == 1) {
            return Scaffold(appBar: AppBar(), body: const EmptyView(icon: Icons.person_off_outlined, text: 'الاسم ده اتحذف'));
          }
          final balance = n(p['balance']);
          final b = balanceInfo(balance);
          final phone = s(p['phone']);
          final limit = n(p['credit_limit']);
          final collectOn = s(p['collect_on']);
          return Scaffold(
            appBar: AppBar(
              title: Text(s(p['name'])),
              actions: [
                IconButton(
                  tooltip: 'مشاركة صفحة الحساب PDF',
                  onPressed: () => sharePdf(
                    context,
                    () => _period == Period.all()
                        ? PdfDocs.statement(widget.partyId)
                        : PdfDocs.statement(widget.partyId, from: _period.from, to: _period.to, periodText: _period.rangeText),
                    'حساب ${s(p['name'])}.pdf',
                  ),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
                IconButton(
                  tooltip: 'تعديل',
                  onPressed: () => push(context, PartyFormScreen(id: widget.partyId)),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Box(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          LetterAvatar(s(p['name']), radius: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Pill(partyKinds[p['kind']] ?? ''),
                                if (phone.isNotEmpty)
                                  Text(phone, style: const TextStyle(color: AppColors.muted)),
                              ],
                            ),
                          ),
                          if (phone.isNotEmpty) ...[
                            IconButton.filledTonal(
                              tooltip: 'اتصال',
                              onPressed: () => callPhone(context, phone),
                              icon: const Icon(Icons.call_outlined),
                            ),
                            IconButton.filledTonal(
                              tooltip: 'واتساب',
                              onPressed: () => openWhatsApp(
                                context,
                                phone,
                                WaText.account(
                                  name: s(p['name']),
                                  balance: balance,
                                  collectOn: s(p['collect_on']),
                                  lastMove: _lastMove(d.ledger),
                                ),
                              ),
                              icon: const Icon(Icons.chat_outlined),
                            ),
                          ],
                        ],
                      ),
                      const Gap(10),
                      const Text('الحساب النهارده', style: TextStyle(color: AppColors.muted)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(b.text, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: b.color)),
                      ),
                      const Gap(8),
                      Row(
                        children: [
                          Expanded(child: _Total(label: 'ادّيناه (عليه)', value: d.totals.gave, color: AppColors.bad)),
                          const SizedBox(width: 8),
                          Expanded(child: _Total(label: 'خدنا منه (له)', value: d.totals.took, color: AppColors.good)),
                        ],
                      ),
                      if (limit > 0 && balance > limit)
                        Text('تعدى الحد المسموح (${egp(limit)})', style: const TextStyle(color: AppColors.bad, fontWeight: FontWeight.w700)),
                      const Gap(8),
                      Row(
                        children: [
                          const Icon(Icons.event_available_outlined, size: 18, color: AppColors.muted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              collectOn.isEmpty ? 'مفيش ميعاد تحصيل' : 'ميعاد التحصيل: ${showDate(collectOn)}',
                              style: TextStyle(
                                color: collectOn.isNotEmpty && collectOn.compareTo(todayStr()) <= 0 && balance > 0 ? AppColors.bad : AppColors.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(onPressed: () => _setCollectDate(p), child: Text(collectOn.isEmpty ? 'حدد ميعاد' : 'تغيير')),
                        ],
                      ),
                    ],
                  ),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: BigActionButton(
                        label: 'استلمت',
                        icon: Icons.south_west,
                        color: AppColors.good,
                        onTap: () => showMoneySheet(context, party: p, receive: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BigActionButton(
                        label: 'دفعت',
                        icon: Icons.north_east,
                        color: AppColors.bad,
                        onTap: () => showMoneySheet(context, party: p, receive: false),
                      ),
                    ),
                  ],
                ),
                const Gap(8),
                if (d.installments.isNotEmpty) ...[
                  OutlinedButton.icon(
                    onPressed: () => push(context, InstallmentsScreen(partyId: widget.partyId)),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      'أقساطه (${d.installments.length} باقيين • ${egp(d.installments.fold<double>(0, (a, i) => a + i.status.remaining))})',
                    ),
                  ),
                  const Gap(8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => showAdjustSheet(context, party: p, increase: true),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('زوّد على حسابه'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => showAdjustSheet(context, party: p, increase: false),
                        icon: const Icon(Icons.remove_circle_outline),
                        label: const Text('نزّل من حسابه'),
                      ),
                    ),
                  ],
                ),
                const Gap(8),
                OutlinedButton.icon(
                  onPressed: () => showNoteSheet(context, presetBody: 'بخصوص ${s(p['name'])}: '),
                  icon: const Icon(Icons.sticky_note_2_outlined),
                  label: const Text('تذكير بخصوصه'),
                ),
                const Gap(16),
                Row(
                  children: [
                    const Expanded(child: Text('صفحة الحساب', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    Text('${d.ledger.where((r) => r['doc_type'] != 'carried').length} حركة',
                        style: const TextStyle(color: AppColors.muted)),
                  ],
                ),
                const Gap(6),
                PeriodBar(value: _period, onChanged: (v) => setState(() => _period = v)),
                const Gap(8),
                PaperLedger(
                  party: p,
                  rows: d.ledger,
                  periodText: _period == Period.all() ? null : _period.rangeText,
                  onTap: (r) => openDoc(context, s(r['doc_type']), s(r['doc_id'])),
                ),
              ],
            ),
          );
        },
      );

  Future<void> _setCollectDate(DbRow p) async {
    final d = await showDatePicker(
      context: context,
      helpText: 'ميعاد التحصيل / السداد',
      initialDate: parseDate(p['collect_on']) ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (d != null) await app.accounts.setCollectDate(widget.partyId, dateStr(d));
  }

  /// "اشترى بضاعة (آجل) - 22/9/2026" for the WhatsApp reminder.
  String? _lastMove(List<DbRow> ledger) {
    final moves = ledger.where((r) => r['doc_type'] != 'carried' && r['doc_type'] != 'opening').toList();
    if (moves.isEmpty) return null;
    final r = moves.last;
    final amount = n(r['debit']) > 0 ? n(r['debit']) : n(r['credit']);
    return '${s(r['title'])} بـ ${egp(amount)} يوم ${showDate(r['date'])}';
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(egp(value), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ],
        ),
      );
}
