import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/calc.dart';
import '../../data/labels.dart';
import '../../ui/share.dart';
import '../../ui/theme.dart';
import '../../ui/wa_text.dart';
import '../../ui/widgets.dart';
import '../accounts/party_detail.dart';
import '../accounts/voucher_form.dart';
import '../common/pdf_docs.dart';
import 'crop_trade_form.dart';

class CropTradeDetailScreen extends StatelessWidget {
  const CropTradeDetailScreen({super.key, required this.tradeId, this.justSaved = false});

  final String tradeId;
  final bool justSaved;

  @override
  Widget build(BuildContext context) => DbBuilder<DbRow?>(
        query: () => app.crops.trade(tradeId),
        builder: (context, t) {
          if (t == null || n(t['deleted']) == 1) {
            return Scaffold(appBar: AppBar(), body: const EmptyView(icon: Icons.grass, text: 'العملية دي اتحذفت'));
          }
          final isSale = t['kind'] == 'sale';
          final unit = s(t['unit_name']);
          final kpu = n(t['kg_per_unit']);
          final c = CropCalc.fromRow(t);
          final sacks = s(t['weigh_mode']) == 'sacks';
          final sackWeights = sackWeightsOf(t['sack_weights']);
          final title = '${cropTradeKinds[t['kind']]} ${s(t['number'])}';
          final partyWord = isSale ? 'التاجر' : 'الفلاح';
          return Scaffold(
            appBar: AppBar(
              title: Text(title),
              actions: [
                IconButton(
                  tooltip: 'تعديل',
                  onPressed: () => push(context, CropTradeForm(kind: s(t['kind']), id: tradeId)),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'حذف العملية',
                      message: 'حذف $title؟ هيتشال أثرها من المخزن والحسابات.',
                      ok: 'حذف',
                      danger: true,
                    );
                    if (!ok) return;
                    await app.crops.deleteTrade(tradeId);
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline, color: AppColors.bad),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (justSaved)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.cropsSoft, borderRadius: BorderRadius.circular(12)),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: AppColors.good),
                        SizedBox(width: 8),
                        Text('تم الحفظ', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.good)),
                      ],
                    ),
                  ),
                Box(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: () => push(context, PartyDetailScreen(partyId: s(t['party_id']))),
                        child: InfoRow(partyWord, s(t['party_name']), bold: true),
                      ),
                      InfoRow('المحصول', s(t['crop_name']), bold: true),
                      InfoRow('التاريخ', showDate(t['date'])),
                      InfoRow('المخزن', s(t['warehouse_name'])),
                      if (s(t['ticket_no']).isNotEmpty) InfoRow('رقم الكارتة', s(t['ticket_no'])),
                      if (s(t['vehicle']).isNotEmpty) InfoRow('العربية / السواق', s(t['vehicle'])),
                      ByLine(row: t),
                    ],
                  ),
                ),
                const SectionTitle('الوزن', padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
                Box(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (sacks) ...[
                        InfoRow('طريقة الوزن', 'بالشكارة'),
                        InfoRow('عدد الشكاير', intf(c.bagsCount)),
                        InfoRow('وزن الشكاير', '${qty(c.grossKg)} كجم'),
                        if (sackWeights.isNotEmpty) ...[
                          const Gap(6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final w in sackWeights)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(6)),
                                  child: Text(qty(w), style: const TextStyle(fontSize: 12)),
                                ),
                            ],
                          ),
                          const Gap(6),
                        ],
                      ] else ...[
                        InfoRow('طريقة الوزن', 'باسكول'),
                        InfoRow('القايم', '${qty(c.grossKg)} كجم'),
                        if (c.tareKg > 0) ...[
                          InfoRow('الفارغ', '${qty(c.tareKg)} كجم'),
                          InfoRow('الحمولة (القايم - الفارغ)', '${qty(c.loadKg)} كجم', bold: true),
                        ],
                      ],
                      if (c.bagsKg > 0) InfoRow('خصم الشكاير (${qty(c.bagsCount)} × ${qty(c.bagWeightKg)})', '${qty(c.bagsKg)} كجم'),
                      if (c.moistureDeductionKg > 0) InfoRow('خصم الرطوبة', '${qty(c.moistureDeductionKg)} كجم'),
                      if (c.impuritiesDeductionKg > 0) InfoRow('خصم الشوائب', '${qty(c.impuritiesDeductionKg)} كجم'),
                      if (c.otherDeductionKg > 0) InfoRow('خصم تاني', '${qty(c.otherDeductionKg)} كجم'),
                      const Divider(),
                      InfoRow(
                        'الوزن الصافي',
                        unitsOf(c.netKg, unit, kpu),
                        sub: kpu == 1 ? null : '${qty(c.netKg)} كجم',
                        bold: true,
                      ),
                      if (isSale && c.stockKg != c.netKg) InfoRow('الخارج من المخزن', '${qty(c.stockKg)} كجم'),
                    ],
                  ),
                ),
                const SectionTitle('الحساب', padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
                Box(
                  child: Column(
                    children: [
                      InfoRow('سعر ال$unit', egp(c.pricePerUnit)),
                      InfoRow('قيمة المحصول', egp(c.subtotal), bold: true),
                      if (c.freight > 0) InfoRow('نولون', egp(c.freight)),
                      if (c.loading > 0) InfoRow('عتالة وتحميل', egp(c.loading)),
                      if (c.otherExpenses > 0) InfoRow('مصاريف أخرى', egp(c.otherExpenses)),
                      if (c.expenses > 0)
                        InfoRow('المصاريف', c.expensesOnParty ? 'على $partyWord' : 'علينا'),
                      const Divider(),
                      InfoRow('صافي حساب $partyWord', egp(c.partyTotal), bold: true, big: true),
                      InfoRow(isSale ? 'المقبوض' : 'المدفوع', egp(c.paid)),
                      if (c.remaining > 0.009)
                        InfoRow(isSale ? 'الباقي على التاجر' : 'الباقي للفلاح', egp(c.remaining), color: AppColors.bad, bold: true),
                      if (s(t['box_name']).isNotEmpty) InfoRow('الخزنة', s(t['box_name'])),
                    ],
                  ),
                ),
                if (s(t['notes']).isNotEmpty) ...[
                  const Gap(),
                  Box(child: Text(s(t['notes']))),
                ],
                const Gap(16),
                FilledButton.icon(
                  onPressed: () => sharePdf(context, () => PdfDocs.cropTrade(tradeId), '$title.pdf'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(isSale ? 'مشاركة الفاتورة PDF' : 'مشاركة البون PDF'),
                ),
                const Gap(10),
                Row(
                  children: [
                    if (s(t['party_phone']).isNotEmpty) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final balance = await app.accounts.partyBalance(s(t['party_id']));
                            if (!context.mounted) return;
                            await openWhatsApp(context, s(t['party_phone']), WaText.cropTrade(t, c, balance));
                          },
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('واتساب'),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (c.remaining > 0.009)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => push(
                            context,
                            VoucherForm(
                              kind: isSale ? 'receipt' : 'payment',
                              partyId: s(t['party_id']),
                              amount: c.remaining,
                              notes: '${isSale ? 'تحصيل' : 'سداد'} ${cropTradeKinds[t['kind']]} ${s(t['number'])}',
                            ),
                          ),
                          icon: const Icon(Icons.payments_outlined),
                          label: Text(isSale ? 'تحصيل الباقي' : 'دفع الباقي'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      );
}
