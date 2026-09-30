import '../core/db/schema.dart';

const partyKinds = {
  'customer': 'عميل',
  'supplier': 'مورد',
  'farmer': 'فلاح',
  'trader': 'تاجر / مصنع',
  'other': 'أخرى',
};

/// Kinds of accounts each business deals with.
Map<String, String> partyKindsFor(String division) => division == Division.crops
    ? const {'farmer': 'فلاح', 'trader': 'تاجر / مصنع', 'other': 'أخرى'}
    : const {'customer': 'عميل', 'supplier': 'مورد', 'other': 'أخرى'};

const invoiceKinds = {
  'sale': 'فاتورة بيع',
  'purchase': 'فاتورة شراء',
  'sale_return': 'مرتجع بيع',
  'purchase_return': 'مرتجع شراء',
};

const paymentTypes = {
  'cash': 'كاش',
  'credit': 'آجل',
  'installment': 'تقسيط',
};

const priceLevels = {
  'retail': 'قطاعي',
  'wholesale': 'جملة',
};

const voucherKinds = {
  'receipt': 'استلام فلوس',
  'payment': 'دفع فلوس',
  'advance': 'سلفة',
  'expense': 'مصروف',
  'transfer': 'تحويل بين الخزن',
  'deposit': 'إيداع في الخزنة',
  'withdrawal': 'مسحوبات',
  'debit_adj': 'زيادة على الحساب',
  'credit_adj': 'خصم من الحساب',
};

const cropTradeKinds = {
  'purchase': 'توريد محصول',
  'sale': 'بيع محصول',
};

const stockMoveKinds = {
  'transfer': 'تحويل بين المخازن',
  'adjust': 'تسوية مخزون',
};

const noteKinds = {
  'note': 'ملاحظة',
  'money': 'فلوس / أمانة',
  'task': 'مهمة',
  // Written on the "النواقص" screen, not on the reminder board.
  needKind: 'ناقص',
};

/// Something the shop ran out of and has to be brought. It lives with the
/// reminders but has its own screen.
const needKind = 'need';

const defaultExpenseCategories = [
  'إيجار',
  'مرتبات',
  'كهرباء ومياه',
  'نقل ونولون',
  'عتالة',
  'صيانة',
  'بنزين وسولار',
  'ضرائب ورسوم',
  'نثريات',
];

/// Title of a ledger line or document.
String docLabel(String docType, String? kind) {
  switch (docType) {
    case 'opening':
      return 'رصيد أول المدة';
    case 'carried':
      return 'رصيد سابق';
    case 'crop_trade':
      return cropTradeKinds[kind] ?? 'محصول';
    case 'invoice':
      return invoiceKinds[kind] ?? 'فاتورة';
    case 'voucher':
      if (kind == 'transfer_in') return 'تحويل وارد';
      if (kind == 'transfer') return 'تحويل صادر';
      return voucherKinds[kind] ?? 'سند';
    case 'stock_move':
      if (kind == 'transfer_in') return 'تحويل وارد';
      if (kind == 'transfer') return 'تحويل صادر';
      return stockMoveKinds[kind] ?? 'حركة مخزن';
    case 'note':
      return 'تذكير';
    case 'party':
      return 'حساب';
    case 'product':
      return 'صنف';
  }
  return docType;
}
