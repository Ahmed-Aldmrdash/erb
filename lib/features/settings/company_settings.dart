import 'package:flutter/material.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';

import '../../core/app_state.dart';
import '../../core/seed.dart';
import '../../core/util/format.dart';
import '../../data/calc.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Business details printed on invoices, receipts and statements, and the
/// defaults of the open division. Shared by every phone of the division.
class CompanySettingsScreen extends StatefulWidget {
  const CompanySettingsScreen({super.key});

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  final _name = TextEditingController(text: app.settings['company_name'] ?? '');
  final _phone = TextEditingController(text: app.settings['company_phone'] ?? '');
  final _address = TextEditingController(text: app.settings['company_address'] ?? '');
  final _footer = TextEditingController(text: app.settings['invoice_footer'] ?? '');
  final _markup = TextEditingController(text: app.settings['default_markup_pct'] ?? '');
  final _bagWeight = TextEditingController(text: app.settings['default_bag_weight'] ?? '');
  final _profit = TextEditingController(text: app.settings['default_profit_pct'] ?? '');
  late double _priceRound = app.priceStep;
  bool _busy = false;

  final FlutterNativeContactPicker _contactPicker = FlutterNativeContactPicker();

  Future<void> _pickContact() async {
    try {
      final contact = await _contactPicker.selectContact();
      if (contact != null) {
        setState(() {
          if (contact.phoneNumbers != null && contact.phoneNumbers!.isNotEmpty) {
            _phone.text = contact.phoneNumbers!.first;
          }
          if (_name.text.isEmpty && contact.fullName != null) {
            _name.text = contact.fullName!;
          }
        });
      }
    } catch (e) {
      if (mounted) toast(context, 'حصل مشكلة في فتح جهات الاتصال', error: true);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await app.accounts.saveSettings({
      'company_name': _name.text.trim(),
      'company_phone': normalizeDigits(_phone.text.trim()),
      'company_address': _address.text.trim(),
      'invoice_footer': _footer.text.trim(),
      if (app.isCrops) 'default_bag_weight': numText(parseNum(_bagWeight.text)),
      if (!app.isCrops) 'default_markup_pct': numText(parseNum(_markup.text)),
      if (!app.isCrops) 'default_profit_pct': numText(parseNum(_profit.text)),
      if (!app.isCrops) 'price_round': numText(_priceRound),
    });
    if (!mounted) return;
    toast(context, 'تم الحفظ');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('بيانات ${app.divisionName}')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'البيانات دي بتتطبع على الفواتير والإيصالات وصفحات الحساب بتاعة ${app.divisionName}.',
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const Gap(),
            TextF(
              controller: _name,
              label: 'اسم المؤسسة',
              icon: Icons.storefront_outlined,
              hint: defaultCompanyName,
            ),
            const Gap(),
            TextF(
              controller: _phone,
              label: 'التليفون',
              icon: Icons.phone_outlined,
              keyboard: TextInputType.phone,
              suffixIcon: IconButton(
                icon: Icon(Icons.contacts_outlined, color: AppColors.primary),
                onPressed: _pickContact,
                tooltip: 'اختيار من جهات الاتصال',
              ),
            ),
            const Gap(),
            TextF(controller: _address, label: 'العنوان', icon: Icons.location_on_outlined),
            const Gap(),
            TextF(
              controller: _footer,
              label: 'ملاحظة أسفل الفاتورة والإيصال',
              maxLines: 3,
              hint: app.isCrops ? 'مثلاً: شكراً لتعاملكم معنا' : 'مثلاً: البضاعة المباعة ترد خلال 14 يوم بحالتها',
            ),
            const Gap(16),
            const Text('قيم افتراضية', style: TextStyle(fontWeight: FontWeight.w700)),
            const Gap(8),
            if (app.isCrops)
              NumField(controller: _bagWeight, label: 'وزن الجوال الفاضي', suffix: 'كجم')
            else ...[
              Row(
                children: [
                  Expanded(child: NumField(controller: _markup, label: 'نسبة زيادة التقسيط', suffix: '%')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NumField(
                      controller: _profit,
                      label: 'نسبة المكسب',
                      suffix: '%',
                      helper: 'بتتحط لوحدها في الصنف الجديد',
                    ),
                  ),
                ],
              ),
              const Gap(16),
              const Text('تقريب أسعار البيع', style: TextStyle(fontWeight: FontWeight.w700)),
              const Gap(4),
              const Text(
                'أي سعر بيع بيتحسب (من نسبة المكسب أو بعد ما سعر الشراء يزيد) بيتقرب لفوق للرقم ده، '
                'علشان الأسعار تفضل أرقام مظبوطة.',
                style: TextStyle(color: AppColors.muted, height: 1.5, fontSize: 13),
              ),
              const Gap(8),
              Wrap(
                spacing: 8,
                children: [
                  for (final step in priceRoundSteps)
                    ChoiceChip(
                      label: Text(numText(step)),
                      selected: _priceRound == step,
                      onSelected: (_) => setState(() => _priceRound = step),
                    ),
                ],
              ),
              const Gap(8),
              Text(
                'يعني سعر زي ${money(1243.7)} هيبقى ${money(ceilToStep(1243.7, _priceRound))}.',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ],
        ),
        bottomNavigationBar: SaveBar(onSave: _save, busy: _busy),
      );
}
