/// الصلاحيات: what each login is allowed to open on the phone.
///
/// A user's permissions are a comma separated list kept with his login on the
/// server ("pos,stock"). An **empty** list means no limits, which is what the
/// accounts of the business itself have.
///
/// This decides what the phone shows. Which business's data a login reaches
/// (المعرض or التجارة) is decided by its division, on the server.
class Perm {
  static const pos = 'pos';
  static const stock = 'stock';
  static const sales = 'sales';
  static const accounts = 'accounts';
  static const money = 'money';
  static const reports = 'reports';
  static const settings = 'settings';

  /// In the order they are shown when the owner ticks them.
  static const all = [pos, stock, sales, accounts, money, reports, settings];

  static const names = {
    pos: 'الكاشير',
    stock: 'المخزن والأصناف',
    sales: 'الفواتير والأقساط',
    accounts: 'حسابات العملاء',
    money: 'الخزنة وحركات الفلوس',
    reports: 'التقارير والأرباح',
    settings: 'الإعدادات والنسخة الاحتياطية',
  };

  /// What each one lets somebody do, in the words of the showroom.
  static const details = {
    pos: 'يبيع بالكاشير ويطبع الإيصال',
    stock: 'يشوف الأصناف والكميات، يعدّل الأسعار، يجرد، ويطبع الملصقات',
    sales: 'فواتير البيع والشراء والمرتجعات والأقساط',
    accounts: 'حسابات العملاء والموردين واللي لينا واللي علينا',
    money: 'الخزنة والمصروفات واستلام ودفع الفلوس',
    reports: 'تقارير المبيعات والأرباح وتقرير الموسم',
    settings: 'بيانات المؤسسة، النسخة الاحتياطية، المستخدمين وكلمات المرور',
  };

  /// A cashier who only sells and sees the stock.
  static const cashierPreset = [pos, stock];

  /// Somebody running a whole business, minus the settings.
  static const managerPreset = [pos, stock, sales, accounts, money, reports];

  static Set<String> parse(String? text) => {
        for (final part in (text ?? '').split(','))
          if (part.trim().isNotEmpty) part.trim(),
      };

  static String write(Iterable<String> perms) => (perms.toList()..sort((a, b) => all.indexOf(a).compareTo(all.indexOf(b)))).join(',');

  /// "الكاشير • المخزن والأصناف", or "كل الصلاحيات" for a login with no limits.
  static String describe(String? text) {
    final set = parse(text);
    if (set.isEmpty) return 'كل الصلاحيات';
    return [for (final p in all) if (set.contains(p)) names[p]!].join(' • ');
  }
}
