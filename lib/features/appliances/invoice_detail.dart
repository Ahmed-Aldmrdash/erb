import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/appliances_repo.dart';
import '../../data/calc.dart';
import '../../data/labels.dart';
import '../../data/permissions.dart';
import '../../ui/share.dart';
import '../../ui/theme.dart';
import '../../ui/wa_text.dart';
import '../../ui/widgets.dart';
import '../accounts/party_detail.dart';
import '../accounts/voucher_form.dart';
import '../accounts/vouchers_screen.dart';
import '../common/pdf_docs.dart';
import 'invoice_form.dart';
import 'return_flow.dart';

class _InvoiceData {
  _InvoiceData(this.inv, this.lines, this.installments, this.receipts, this.returns);

  final DbRow? inv;
  final List<DbRow> lines;
  final List<InstallmentStatus> installments;
  final List<DbRow> receipts;

  /// The returns written against this invoice, so the goods that came back
  /// are visible on the invoice they went out on.
  final List<DbRow> returns;
}

class InvoiceDetailScreen extends StatelessWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId, this.justSaved = false});

  final String invoiceId;
  final bool justSaved;

  Future<_InvoiceData> _load() async => _InvoiceData(
        await app.appliances.invoice(invoiceId),
        await app.appliances.invoiceLines(invoiceId),
        await app.appliances.invoiceInstallments(invoiceId),
        await app.accounts.vouchers(invoiceId: invoiceId),
        await app.appliances.returnsOf(invoiceId),
      );

  @override
  Widget build(BuildContext context) => DbBuilder<_InvoiceData>(
        query: _load,
        builder: (context, d) {
          final inv = d.inv;
          if (inv == null || n(inv['deleted']) == 1) {
            return Scaffold(appBar: AppBar(), body: const EmptyView(icon: Icons.receipt_long, text: 'الفاتورة دي اتحذفت'));
          }
          final kind = s(inv['kind']);
          final title = '${invoiceKinds[kind]} ${s(inv['number'])}';
          final isInstallment = inv['payment_type'] == 'installment';
          final grand = n(inv['grand_total']);
          final paid = n(inv['paid_amount']);
          final collected = n(inv['collected']);
          final remaining = AppliancesRepo.remainingOf(inv);
          // Paid through general receipts / payments on the account.
          final onAccount = roundMoney(grand - paid - collected - remaining);
          final partyId = inv['party_id'] as String?;
          final partyName = s(inv['party_name']).isNotEmpty ? s(inv['party_name']) : s(inv['customer_name']);
          final today = todayStr();
          final nextDue = d.installments.where((i) => i.remaining > 0.009).firstOrNull;
          return Scaffold(
            appBar: AppBar(
              title: Text(title),
              actions: [
                // A cashier may look at his own sale and print it again, but
                // changing or deleting an invoice is not his to do.
                if (app.can(Perm.sales))
                IconButton(
                  tooltip: 'تعديل',
                  onPressed: () => push(context, InvoiceForm(kind: kind, id: invoiceId)),
                  icon: const Icon(Icons.edit_outlined),
                ),
                if (app.can(Perm.sales))
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'return') {
                      await returnFromInvoice(context, inv);
                    } else if (v == 'delete') {
                      final ok = await confirmDialog(
                        context,
                        title: 'حذف الفاتورة',
                        message: 'حذف $title؟ هيتشال أثرها من المخزن والحسابات.'
                            '${collected > 0 ? '\nالمبالغ اللي اتحصلت عليها هتفضل مسجلة في حساب العميل.' : ''}',
                        ok: 'حذف',
                        danger: true,
                      );
                      if (!ok) return;
                      await app.appliances.deleteInvoice(invoiceId);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  itemBuilder: (_) => [
                    if (kind == 'sale' || kind == 'purchase')
                      const PopupMenuItem(value: 'return', child: Text('عمل مرتجع من الفاتورة')),
                    const PopupMenuItem(value: 'delete', child: Text('حذف الفاتورة', style: TextStyle(color: AppColors.bad))),
                  ],
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
                    decoration: BoxDecoration(color: AppColors.appliancesSoft, borderRadius: BorderRadius.circular(12)),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: AppColors.good),
                        SizedBox(width: 8),
                        Text('تم حفظ الفاتورة', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.good)),
                      ],
                    ),
                  ),
                Box(
                  child: Column(
                    children: [
                      InkWell(
                        onTap: partyId == null ? null : () => push(context, PartyDetailScreen(partyId: partyId)),
                        child: InfoRow(kind.startsWith('purchase') ? 'المورد' : 'العميل', partyName.isEmpty ? 'نقدي' : partyName, bold: true),
                      ),
                      InfoRow('التاريخ', showDate(inv['date'])),
                      InfoRow('طريقة الدفع', paymentTypes[inv['payment_type']] ?? ''),
                      if (kind == 'sale') InfoRow('السعر', priceLevels[inv['price_level']] ?? ''),
                      InfoRow('المخزن', s(inv['warehouse_name'])),
                      if (isInstallment && s(inv['guarantor_name']).isNotEmpty)
                        InfoRow('الضامن', '${s(inv['guarantor_name'])} ${s(inv['guarantor_phone'])}'),
                      if (s(inv['notes']).isNotEmpty) InfoRow('ملاحظات', s(inv['notes'])),
                      // A return says which invoice the goods went out on, so
                      // anybody looking at it can get back to the sale itself.
                      if (kind.endsWith('_return') && inv['ref_invoice_id'] != null)
                        InkWell(
                          onTap: () => push(context, InvoiceDetailScreen(invoiceId: s(inv['ref_invoice_id']))),
                          child: const InfoRow('مرتجع من', 'افتح الفاتورة الأصلية', color: AppColors.appliances),
                        ),
                      ByLine(row: inv),
                    ],
                  ),
                ),
                const SectionTitle('الأصناف', padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
                Box(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final l in d.lines)
                        ListTile(
                          title: Text(s(l['product_name'])),
                          subtitle: Text('${qty(n(l['qty']))} × ${money(n(l['price']))}${s(l['notes']).isNotEmpty ? ' • ${s(l['notes'])}' : ''}'),
                          trailing: Text(egp(n(l['total'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ),
                const Gap(12),
                Box(
                  child: Column(
                    children: [
                      InfoRow('الإجمالي', egp(n(inv['subtotal']))),
                      if (n(inv['discount']) > 0) InfoRow('الخصم', egp(n(inv['discount']))),
                      InfoRow('الصافي', egp(n(inv['total'])), bold: true),
                      if (isInstallment) ...[
                        InfoRow('زيادة التقسيط ${qty(n(inv['markup_pct']))}%', egp(n(inv['markup_amount']))),
                        InfoRow('الإجمالي بالتقسيط', egp(grand), bold: true),
                        InfoRow('المقدم', egp(paid)),
                      ] else
                        InfoRow('المدفوع وقت الفاتورة', egp(paid)),
                      if (collected > 0) InfoRow('اتحصل بعد كده', egp(collected)),
                      if (onAccount > 0.009) InfoRow('اتدفع على الحساب', egp(onAccount)),
                      if (remaining > 0.009) InfoRow('المتبقي', egp(remaining), bold: true, big: true, color: AppColors.bad),
                    ],
                  ),
                ),
                if (d.installments.isNotEmpty) ...[
                  const SectionTitle('الأقساط', padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
                  Box(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final it in d.installments) _InstallmentTile(inv: inv, it: it, today: today),
                      ],
                    ),
                  ),
                ],
                if (d.receipts.isNotEmpty) ...[
                  const SectionTitle('المدفوعات على الفاتورة', padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
                  TileGroup(margin: EdgeInsets.zero, children: [for (final r in d.receipts) VoucherTile(r)]),
                ],
                if (d.returns.isNotEmpty) ...[
                  const SectionTitle('اللي رجع من الفاتورة دي', padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
                  TileGroup(margin: EdgeInsets.zero, children: [
                    for (final r in d.returns)
                      ListTile(
                        onTap: () => push(context, InvoiceDetailScreen(invoiceId: s(r['id']))),
                        leading: const Icon(Icons.assignment_return_outlined, color: AppColors.warn),
                        title: Text('مرتجع ${s(r['number'])} • ${showDate(s(r['date']))}'),
                        subtitle: Text('${ni(r['line_count'])} صنف'),
                        trailing: Text(egp(n(r['grand_total'])),
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.warn)),
                      ),
                  ]),
                ],
                const Gap(16),
                if (remaining > 0.009 && partyId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.good),
                      onPressed: () => push(
                        context,
                        VoucherForm(
                          kind: kind == 'sale' || kind == 'purchase_return' ? 'receipt' : 'payment',
                          partyId: partyId,
                          invoiceId: invoiceId,
                          amount: nextDue?.remaining ?? remaining,
                          notes: nextDue != null
                              ? 'قسط ${nextDue.seq} - فاتورة ${s(inv['number'])}'
                              : 'دفعة من فاتورة ${s(inv['number'])}',
                        ),
                      ),
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(nextDue != null ? 'تحصيل القسط ${nextDue.seq}' : 'تسجيل دفعة'),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => sharePdf(context, () => PdfDocs.invoice(invoiceId), '$title.pdf'),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('ابعت الفاتورة'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        // Shows it on screen first, then print or save.
                        onPressed: () => printPdf(context, () => PdfDocs.invoice(invoiceId), 'فاتورة ${s(inv['number'])}'),
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('اعرض واطبع'),
                      ),
                    ),
                  ],
                ),
                if (kind == 'sale') ...[
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => printPdf(context, () => PdfDocs.receipt(invoiceId), 'إيصال ${s(inv['number'])}'),
                          icon: const Icon(Icons.receipt_outlined),
                          label: const Text('إيصال صغير'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => sharePdf(context, () => PdfDocs.receipt(invoiceId), 'إيصال ${s(inv['number'])}.pdf'),
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('ابعت الإيصال'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (s(inv['party_phone']).isNotEmpty) ...[
                  const Gap(10),
                  OutlinedButton.icon(
                    onPressed: () => openWhatsApp(context, s(inv['party_phone']), WaText.invoice(inv, remaining: remaining, nextDue: nextDue)),
                    icon: const Icon(Icons.chat_outlined),
                    label: Text(nextDue != null ? 'تذكير بالقسط على واتساب' : 'إرسال على واتساب'),
                  ),
                ],
              ],
            ),
          );
        },
      );
}

class _InstallmentTile extends StatelessWidget {
  const _InstallmentTile({required this.inv, required this.it, required this.today});

  final DbRow inv;
  final InstallmentStatus it;
  final String today;

  @override
  Widget build(BuildContext context) {
    final state = it.stateOn(today);
    final (label, color) = switch (state) {
      InstallmentState.paid => ('مدفوع', AppColors.good),
      InstallmentState.partial => ('مدفوع جزء', AppColors.warn),
      InstallmentState.overdue => ('متأخر', AppColors.bad),
      InstallmentState.due => ('لم يستحق', AppColors.muted),
    };
    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Text('${it.seq}', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
      ),
      title: Text('${egp(it.amount)} • ${showDate(it.dueDate)}'),
      subtitle: it.paid > 0 && state != InstallmentState.paid ? Text('مدفوع ${egp(it.paid)} • باقي ${egp(it.remaining)}') : null,
      trailing: state == InstallmentState.paid
          ? Pill(label, color: color)
          : TextButton(
              onPressed: () => push(
                context,
                VoucherForm(
                  kind: 'receipt',
                  partyId: inv['party_id'] as String?,
                  invoiceId: s(inv['id']),
                  amount: it.remaining,
                  notes: 'قسط ${it.seq} - فاتورة ${s(inv['number'])}',
                ),
              ),
              child: Text(state == InstallmentState.overdue ? 'تحصيل (متأخر)' : 'تحصيل', style: TextStyle(color: color == AppColors.muted ? null : color)),
            ),
    );
  }
}
