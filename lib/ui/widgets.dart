import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/util/format.dart';
import 'theme.dart';

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? AppColors.bad : null,
  ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String ok = 'تأكيد',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.bad) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

/// Asks before leaving a screen with something typed on it but not saved.
///
/// Losing half a written invoice because somebody pressed back is the kind of
/// thing that makes people stop trusting the app, so every form that can hold
/// work wraps itself in this.
class UnsavedGuard extends StatelessWidget {
  const UnsavedGuard({
    super.key,
    required this.dirty,
    required this.child,
    this.message = 'اللي كتبته هيضيع من غير حفظ.',
  });

  /// Asked at the moment of leaving, not while building: a form does not
  /// rebuild itself every time a letter is typed into it.
  final bool Function() dirty;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final navigator = Navigator.of(context);
          if (!dirty()) {
            navigator.pop();
            return;
          }
          final ok = await confirmDialog(
            context,
            title: 'تخرج من غير حفظ؟',
            message: message,
            ok: 'اخرج',
            danger: true,
          );
          if (ok) navigator.pop();
        },
        child: child,
      );
}

/// Runs [query], and runs it again every time the local database changes
/// (a local edit or data arriving from another phone).
class DbBuilder<T> extends StatefulWidget {
  const DbBuilder({super.key, required this.query, required this.builder, this.queryKey});

  final Future<T> Function() query;
  final Widget Function(BuildContext context, T data) builder;

  /// Change it (e.g. to a record of the filters) to re-run the query.
  final Object? queryKey;

  @override
  State<DbBuilder<T>> createState() => _DbBuilderState<T>();
}

class _DbBuilderState<T> extends State<DbBuilder<T>> {
  T? _data;
  bool _loaded = false;
  Object? _error;
  StreamSubscription<Set<String>>? _sub;
  Timer? _debounce;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _run();
    _sub = app.db.changes.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 150), _run);
    });
  }

  @override
  void didUpdateWidget(covariant DbBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queryKey != widget.queryKey) _run();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    final gen = ++_generation;
    try {
      final d = await widget.query();
      if (!mounted || gen != _generation) return;
      setState(() {
        _data = d;
        _loaded = true;
        _error = null;
      });
    } catch (e, st) {
      debugPrint('DbBuilder: $e\n$st');
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('حصلت مشكلة في قراءة البيانات:\n$_error', textAlign: TextAlign.center),
        ),
      );
    }
    if (!_loaded) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
      );
    }
    return widget.builder(context, _data as T);
  }
}

// ---------------------------------------------------------------- layout

class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(16, 22, 8, 8),
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text),
              ),
            ),
            if (action != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: Text(action!),
              ),
          ],
        ),
      );
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.subtitle,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;

  /// Accent color; the value itself stays dark unless a color is given.
  final Color? color;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.primary;
    return Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 18, color: color),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: this.color == null ? AppColors.text : color),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
  }
}

/// Two or three cards side by side with equal height.
class CardRow extends StatelessWidget {
  const CardRow({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: 16)});

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: children[i]),
              ],
            ],
          ),
        ),
      );
}

class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  /// Small red counter on the icon (e.g. open reminders).
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.primary;
    return Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: badge > 0,
                  label: Text('$badge'),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.25),
                ),
              ],
            ),
          ),
        ),
      );
  }
}

class ActionGrid extends StatelessWidget {
  const ActionGrid({super.key, required this.children, this.columns = 3});

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: columns >= 4 ? 0.76 : 1.0,
          children: children,
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.text, this.actionLabel, this.onAction});

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: AppColors.muted.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
              if (actionLabel != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false, this.color, this.big = false, this.sub});

  final String label;
  final String value;
  final bool bold;
  final bool big;
  final Color? color;

  /// Smaller second line under the value (e.g. the weight in kg).
  final String? sub;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: bold ? AppColors.text : AppColors.muted,
                  fontSize: big ? 16 : 14,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: big ? 17 : 14.5,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                      color: color ?? AppColors.text,
                    ),
                  ),
                  if (sub != null)
                    Text(sub!, textAlign: TextAlign.end, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// White rounded box with padding, the basic container of forms.
class Box extends StatelessWidget {
  const Box({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color});

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}

/// Our side of an account, always in the same words everywhere:
/// لينا (he owes us, green) / علينا (we owe him, red), like Kannash.
({String text, String word, String amount, Color color}) balanceInfo(double balance) {
  if (balance > 0.009) return (text: 'لينا عنده ${egp(balance)}', word: 'لينا', amount: egp(balance), color: AppColors.good);
  if (balance < -0.009) return (text: 'علينا له ${egp(-balance)}', word: 'علينا', amount: egp(-balance), color: AppColors.bad);
  return (text: 'الحساب خالص', word: 'خالص', amount: egp(0), color: AppColors.muted);
}

/// The same balance told to the customer himself (WhatsApp, PDF).
String balanceForParty(double balance) {
  if (balance > 0.009) return 'عليك لينا ${egp(balance)}';
  if (balance < -0.009) return 'ليك عندنا ${egp(-balance)}';
  return 'حسابك خالص';
}

class BalanceText extends StatelessWidget {
  const BalanceText(this.balance, {super.key, this.size = 14});

  final double balance;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = balanceInfo(balance);
    return Text(b.text, style: TextStyle(color: b.color, fontWeight: FontWeight.w700, fontSize: size));
  }
}

// ---------------------------------------------------------------- inputs

final _numberChars = FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩۰-۹.٫,-]'));

class NumField extends StatelessWidget {
  const NumField({
    super.key,
    required this.controller,
    required this.label,
    this.suffix,
    this.helper,
    this.onChanged,
    this.validator,
    this.autofocus = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? suffix;
  final String? helper;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool autofocus;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        enabled: enabled,
        autofocus: autofocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [_numberChars],
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: helper),
        onChanged: onChanged,
        validator: validator,
      );
}

class TextF extends StatelessWidget {
  const TextF({
    super.key,
    required this.controller,
    required this.label,
    this.keyboard,
    this.maxLines = 1,
    this.validator,
    this.icon,
    this.hint,
    this.autofocus = false,
    this.obscure = false,
    this.onChanged,
    this.textDirection,
    this.suffixIcon,
    this.helper,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboard;
  final int maxLines;
  final FormFieldValidator<String>? validator;
  final IconData? icon;
  final String? hint;
  final bool autofocus;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final TextDirection? textDirection;
  final Widget? suffixIcon;
  final String? helper;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: obscure ? 1 : maxLines,
        minLines: 1,
        autofocus: autofocus,
        obscureText: obscure,
        textDirection: textDirection,
        textInputAction: maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          prefixIcon: icon == null ? null : Icon(icon),
          suffixIcon: suffixIcon,
        ),
        validator: validator,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
      );
}

String? requiredText(String? v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null;

String? positiveNumber(String? v) => parseNum(v) <= 0 ? 'اكتب رقم أكبر من صفر' : null;

class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: parseDate(value) ?? DateTime.now(),
            firstDate: DateTime(2015),
            lastDate: DateTime(2100),
          );
          if (picked != null) onChanged(dateStr(picked));
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.calendar_month_outlined),
          ),
          child: Text(showDate(value)),
        ),
      );
}

/// Looks like a text field; opens a picker when tapped.
class PickField extends StatelessWidget {
  const PickField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
    this.errorText,
    this.helper,
    this.onClear,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final IconData? icon;
  final String? errorText;
  final String? helper;

  /// Shows an × to empty the field (optional fields only).
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: InputDecorator(
          isEmpty: value == null || value!.isEmpty,
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            helperText: helper,
            prefixIcon: icon == null ? null : Icon(icon),
            suffixIcon: onClear != null && value != null && value!.isNotEmpty
                ? IconButton(tooltip: 'إلغاء الاختيار', onPressed: onClear, icon: const Icon(Icons.close))
                : const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          child: Text(value ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
}

class Choice<T> extends StatelessWidget {
  const Choice({super.key, required this.options, required this.value, required this.onChanged});

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [
            for (final e in options.entries) ButtonSegment<T>(value: e.key, label: Text(e.value)),
          ],
          selected: {value},
          onSelectionChanged: (sel) => onChanged(sel.first),
        ),
      );
}

class ChipsBar<T> extends StatelessWidget {
  const ChipsBar({super.key, required this.options, required this.value, required this.onChanged});

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          children: [
            for (final e in options.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: e.key == value,
                  showCheckmark: false,
                  onSelected: (_) => onChanged(e.key),
                ),
              ),
          ],
        ),
      );
}

/// The search box over a list.
///
/// It waits a moment after the last letter before it asks for results: typing
/// "ثلاجة" used to run the whole query six times, once per letter, and on a
/// full showroom that is what made the search feel stuck.
class SearchField extends StatefulWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'بحث...'});

  final ValueChanged<String> onChanged;
  final String hint;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _sent = '';

  void _type(String v) {
    _debounce?.cancel();
    // An empty box goes back to the full list at once; nothing is being typed.
    _debounce = Timer(Duration(milliseconds: v.isEmpty ? 0 : 320), () {
      if (!mounted || v == _sent) return;
      _sent = v;
      widget.onChanged(v);
    });
    setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(
          controller: _controller,
          onChanged: _type,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) {
            _debounce?.cancel();
            _sent = v;
            widget.onChanged(v);
          },
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'مسح',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      _type('');
                    },
                  ),
          ),
        ),
      );
}

// ---------------------------------------------------------------- periods

class Period {
  const Period(this.from, this.to, this.label);

  final String from;
  final String to;
  final String label;

  static Period today() => Period(todayStr(), todayStr(), 'النهارده');

  static Period thisMonth() => Period(firstOfMonth(), lastOfMonth(), 'الشهر ده');

  static Period lastMonth() {
    final d = DateTime.now();
    final p = DateTime(d.year, d.month - 1, 1);
    return Period(firstOfMonth(p), lastOfMonth(p), 'الشهر اللي فات');
  }

  static Period thisYear() {
    final y = DateTime.now().year;
    return Period('$y-01-01', '$y-12-31', 'السنة دي');
  }

  static Period all() => const Period('2000-01-01', '2999-12-31', 'الكل');

  String get rangeText => from == to ? showDate(from) : '${showDate(from)} - ${showDate(to)}';

  @override
  bool operator ==(Object other) => other is Period && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class PeriodBar extends StatelessWidget {
  const PeriodBar({super.key, required this.value, required this.onChanged, this.includeAll = true});

  final Period value;
  final ValueChanged<Period> onChanged;
  final bool includeAll;

  @override
  Widget build(BuildContext context) {
    final presets = [
      Period.today(),
      Period.thisMonth(),
      Period.lastMonth(),
      Period.thisYear(),
      if (includeAll) Period.all(),
    ];
    final isCustom = !presets.contains(value);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          for (final p in presets)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(p.label),
                selected: p == value,
                showCheckmark: false,
                onSelected: (_) => onChanged(p),
              ),
            ),
          ChoiceChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(isCustom ? value.rangeText : 'فترة محددة'),
            selected: isCustom,
            showCheckmark: false,
            onSelected: (_) async {
              final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2015),
                lastDate: DateTime(2100),
                initialDateRange: isCustom
                    ? DateTimeRange(start: parseDate(value.from)!, end: parseDate(value.to)!)
                    : null,
              );
              if (r != null) onChanged(Period(dateStr(r.start), dateStr(r.end), 'فترة محددة'));
            },
          ),
        ],
      ),
    );
  }
}

/// Bottom action area of form screens.
class SaveBar extends StatelessWidget {
  const SaveBar({
    super.key,
    required this.onSave,
    this.label = 'حفظ',
    this.busy = false,
    this.extra,
    this.color,
    this.icon = Icons.check,
  });

  final VoidCallback? onSave;
  final String label;
  final bool busy;
  final Widget? extra;
  final Color? color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              if (extra != null) ...[Expanded(child: extra!), const SizedBox(width: 12)],
              Expanded(
                child: FilledButton.icon(
                  style: color == null ? null : FilledButton.styleFrom(backgroundColor: color),
                  onPressed: busy ? null : onSave,
                  icon: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(icon),
                  label: Text(label),
                ),
              ),
            ],
          ),
        ),
      );
}

class Gap extends StatelessWidget {
  const Gap([this.size = 12, Key? key]) : super(key: key);

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size);
}

/// The same card-with-dividers look as [TileGroup], but only the rows on the
/// screen are built.
///
/// This is what long lists use. A [TileGroup] inside a `ListView` builds every
/// row the moment the screen opens, so a thousand products meant a thousand
/// tiles before anything appeared; here the list costs the same whether the
/// showroom has ten products or ten thousand.
class TileListView extends StatelessWidget {
  const TileListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.header,
    this.footer,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.bottomPadding = 90,
    this.controller,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Built once, above the card (totals, filters, a hint).
  final Widget? header;
  final Widget? footer;
  final EdgeInsets margin;
  final double bottomPadding;
  final ScrollController? controller;

  static const _radius = 18.0;

  @override
  Widget build(BuildContext context) {
    final lead = header == null ? 1 : 2;
    final tail = footer == null ? 0 : 1;
    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.only(bottom: bottomPadding),
      // One slot for the header, one for the top of the card, the rows, and
      // one for the footer.
      itemCount: itemCount + lead + tail,
      itemBuilder: (context, i) {
        if (header != null && i == 0) return header!;
        final index = i - lead;
        if (index < 0) return const SizedBox(height: 0);
        if (index >= itemCount) return footer ?? const SizedBox.shrink();
        final first = index == 0;
        final last = index == itemCount - 1;
        return Padding(
          padding: margin,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: first ? AppColors.border : Colors.transparent),
                bottom: BorderSide(color: last ? AppColors.border : Colors.transparent),
                left: const BorderSide(color: AppColors.border),
                right: const BorderSide(color: AppColors.border),
              ),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(first ? _radius : 0),
                bottom: Radius.circular(last ? _radius : 0),
              ),
            ),
            child: Column(
              children: [
                if (!first) const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder(context, index),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Card with a list of tiles separated by dividers.
class TileGroup extends StatelessWidget {
  const TileGroup({super.key, required this.children, this.margin = const EdgeInsets.symmetric(horizontal: 16)});

  final List<Widget> children;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                children[i],
              ],
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------- v2 pieces

/// Colored top area of the dashboards with the business name.
class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key, required this.title, this.subtitle, this.trailing, this.child});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = AppColors.palette;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 10, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [p.primary, p.dark],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
                    if (subtitle != null)
                      Text(subtitle!, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          if (child != null) ...[const SizedBox(height: 14), child!],
        ],
      ),
    );
  }
}

/// Big green / red button, e.g. "استلمت" / "دفعت".
class BigActionButton extends StatelessWidget {
  const BigActionButton({super.key, required this.label, required this.icon, required this.color, required this.onTap});

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
}

class LetterAvatar extends StatelessWidget {
  const LetterAvatar(this.name, {super.key, this.color, this.radius = 20});

  final String name;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    final t = name.trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: c.withValues(alpha: 0.12),
      child: Text(
        t.isEmpty ? '?' : t.substring(0, 1),
        style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: radius * 0.8),
      ),
    );
  }
}

/// "بواسطة فلان • 21/9" line under documents.
class ByLine extends StatelessWidget {
  const ByLine({super.key, required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final created = s(row['created_by_name']);
    final updated = s(row['updated_by_name']);
    final edited = s(row['created_at']) != s(row['updated_at']) && updated.isNotEmpty;
    final parts = [
      if (created.isNotEmpty) 'سجلها: $created',
      if (edited && updated != created) 'عدلها: $updated',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 16, color: AppColors.muted),
          const SizedBox(width: 4),
          Expanded(child: Text(parts.join(' • '), style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
        ],
      ),
    );
  }
}