import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/labels.dart';
import '../../ui/share.dart';
import '../../ui/theme.dart';
import '../../ui/wa_text.dart';
import '../../ui/widgets.dart';
import '../common/pdf_docs.dart';
import 'voucher_form.dart';

class VoucherDetailScreen extends StatelessWidget {
  const VoucherDetailScreen({super.key, required this.voucherId});

  final String voucherId;

  @override
  Widget build(BuildContext context) => DbBuilder<DbRow?>(
        query: () => app.accounts.voucher(voucherId),
        builder: (context, v) {
          if (v == null || n(v['deleted']) == 1) {
            return Scaffold(appBar: AppBar(), body: const EmptyView(icon: Icons.receipt_long, text: 'السند ده اتحذف'));
          }
          final kind = s(v['kind']);
          final title = voucherKinds[kind] ?? 'سند';
          return Scaffold(
            appBar: AppBar(
              title: Text('$title ${s(v['number'])}'),
              actions: [
                IconButton(
                  tooltip: 'تعديل',
                  onPressed: () => push(context, VoucherForm(kind: kind, id: voucherId)),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: () async {
                    final ok = await confirmDialog(context, title: 'حذف السند', message: 'متأكد من حذف السند؟', ok: 'حذف', danger: true);
                    if (!ok) return;
                    await app.accounts.deleteVoucher(voucherId);
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline, color: AppColors.bad),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Box(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        egp(n(v['amount'])),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: switch (kind) {
                            'receipt' || 'deposit' => AppColors.good,
                            'payment' || 'advance' || 'withdrawal' => AppColors.bad,
                            _ => AppColors.text,
                          },
                        ),
                      ),
                      const Gap(8),
                      InfoRow('التاريخ', showDate(v['date'])),
                      if (s(v['party_name']).isNotEmpty) InfoRow(kind == 'receipt' ? 'استلمنا من' : 'الاسم', s(v['party_name'])),
                      if (s(v['category']).isNotEmpty) InfoRow('البند', s(v['category'])),
                      if (s(v['box_name']).isNotEmpty) InfoRow(kind == 'transfer' ? 'من خزنة' : 'الخزنة', s(v['box_name'])),
                      if (kind == 'debit_adj' || kind == 'credit_adj')
                        const InfoRow('الخزنة', 'من غير فلوس (تسوية حساب)'),
                      if (s(v['to_box_name']).isNotEmpty) InfoRow('إلى خزنة', s(v['to_box_name'])),
                      if (s(v['invoice_number']).isNotEmpty) InfoRow('عن فاتورة', s(v['invoice_number'])),
                      if (s(v['handled_by']).isNotEmpty)
                        InfoRow(kind == 'receipt' || kind == 'deposit' ? 'اللي استلم الفلوس' : 'اللي دفع الفلوس', s(v['handled_by']), bold: true),
                      if (s(v['notes']).isNotEmpty) InfoRow('البيان', s(v['notes'])),
                      ByLine(row: v),
                    ],
                  ),
                ),
                const Gap(16),
                FilledButton.tonalIcon(
                  onPressed: () => sharePdf(context, () => PdfDocs.voucher(voucherId), '$title ${s(v['number'])}.pdf'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('مشاركة السند PDF'),
                ),
                if (s(v['party_phone']).isNotEmpty) ...[
                  const Gap(10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final bal = await app.accounts.partyBalance(s(v['party_id']));
                      if (!context.mounted) return;
                      await openWhatsApp(context, s(v['party_phone']), WaText.voucher(v, bal));
                    },
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('إرسال واتساب'),
                  ),
                ],
              ],
            ),
          );
        },
      );
}
