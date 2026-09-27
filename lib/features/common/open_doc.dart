import 'package:flutter/material.dart';

import '../../ui/widgets.dart';
import '../accounts/voucher_detail.dart';
import '../appliances/invoice_detail.dart';
import '../crops/crop_trade_detail.dart';

/// Opens the screen of a ledger line's document.
void openDoc(BuildContext context, String docType, String docId) {
  switch (docType) {
    case 'crop_trade':
      push(context, CropTradeDetailScreen(tradeId: docId));
    case 'invoice':
      push(context, InvoiceDetailScreen(invoiceId: docId));
    case 'voucher':
      push(context, VoucherDetailScreen(voucherId: docId));
  }
}
