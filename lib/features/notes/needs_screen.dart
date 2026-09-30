import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/labels.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// النواقص: what the shop ran out of and has to be brought. Anybody writes on
/// it, and when the goods arrive one tap moves the line to "اللي جه" with the
/// date and the name of whoever said so.
class NeedsScreen extends StatefulWidget {
  const NeedsScreen({super.key});

  @override
  State<NeedsScreen> createState() => _NeedsScreenState();
}

class _NeedsScreenState extends State<NeedsScreen> {
  bool _arrived = false;
  String _search = '';

  Future<void> _markArrived(DbRow r, bool arrived) async {
    await app.notes.setDone(s(r['id']), arrived);
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(arrived ? 'تمام، "${s(r['body'])}" جت' : 'رجعت في النواقص'),
      duration: const Duration(seconds: 5),
      persist: false,
      action: SnackBarAction(label: 'تراجع', onPressed: () => _markArrived(r, !arrived)),
    ));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('النواقص')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await showNeedSheet(context);
            if (mounted) setState(() {});
          },
          icon: const Icon(Icons.add),
          label: const Text('ناقص جديد'),
        ),
        body: Column(
          children: [
            SearchField(onChanged: (v) => setState(() => _search = v), hint: 'بحث في النواقص'),
            ChipsBar<bool>(
              options: const {false: 'اللي ناقص', true: 'اللي جه'},
              value: _arrived,
              onChanged: (v) => setState(() => _arrived = v),
            ),
            Expanded(
              child: DbBuilder<List<DbRow>>(
                queryKey: (_arrived, _search),
                query: () => app.notes.list(done: _arrived, search: _search, kinds: const [needKind]),
                builder: (context, rows) {
                  if (rows.isEmpty) {
                    return EmptyView(
                      icon: _arrived ? Icons.inventory_outlined : Icons.playlist_add_check_circle_outlined,
                      text: _arrived
                          ? 'لسه مجاش حاجة من النواقص'
                          : 'مفيش نواقص. أول ما حاجة تخلص اكتبها هنا عشان ماتنساهاش.',
                      actionLabel: _arrived ? null : 'ناقص جديد',
                      onAction: _arrived
                          ? null
                          : () async {
                              await showNeedSheet(context);
                              if (mounted) setState(() {});
                            },
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 90),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(
                          _arrived ? '${rows.length} جه' : '${rows.length} ناقص',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
                      TileGroup(children: [
                        for (final r in rows) _NeedTile(r, onChanged: () => _markArrived(r, !_arrived)),
                      ]),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
}

class _NeedTile extends StatelessWidget {
  const _NeedTile(this.r, {required this.onChanged});

  final DbRow r;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final arrived = n(r['done']) == 1;
    final from = s(r['person']);
    final wrote = s(r['created_by_name']);
    return ListTile(
      leading: IconButton(
        tooltip: arrived ? 'رجّعه للنواقص' : 'جت',
        onPressed: onChanged,
        icon: Icon(
          arrived ? Icons.check_circle : Icons.radio_button_unchecked,
          color: arrived ? AppColors.good : AppColors.muted,
          size: 28,
        ),
      ),
      title: Text(
        s(r['body']),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: arrived ? TextDecoration.lineThrough : null,
          color: arrived ? AppColors.muted : null,
        ),
      ),
      subtitle: Text(
        [
          if (from.isNotEmpty) 'من $from',
          if (arrived) 'جت ${showDate(s(r['done_at']).split('T').first)}${s(r['done_by']).isEmpty ? '' : ' • ${s(r['done_by'])}'}'
          else if (wrote.isNotEmpty) 'كتبها $wrote',
        ].join(' • '),
      ),
      trailing: arrived
          ? null
          : FilledButton.tonal(
              onPressed: onChanged,
              child: const Text('جت'),
            ),
      onLongPress: () async {
        final ok = await confirmDialog(
          context,
          title: 'حذف',
          message: 'تشيل "${s(r['body'])}" من القايمة؟',
          ok: 'حذف',
          danger: true,
        );
        if (ok) {
          await app.notes.delete(s(r['id']));
          onChanged();
        }
      },
    );
  }
}

/// Writing something the shop needs. [presetBody] comes from a product that
/// ran out, so its name is already filled in.
Future<void> showNeedSheet(BuildContext context, {String? presetBody}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NeedSheet(presetBody: presetBody),
    );

class _NeedSheet extends StatefulWidget {
  const _NeedSheet({this.presetBody});

  final String? presetBody;

  @override
  State<_NeedSheet> createState() => _NeedSheetState();
}

class _NeedSheetState extends State<_NeedSheet> {
  late final _body = TextEditingController(text: widget.presetBody ?? '');
  final _from = TextEditingController();
  bool _busy = false;

  Future<void> _save() async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      toast(context, 'اكتب الناقص إيه', error: true);
      return;
    }
    setState(() => _busy = true);
    await app.notes.save({
      'kind': needKind,
      'body': body,
      'person': _from.text.trim(),
      'division': app.division,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('ناقص جديد', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const Gap(12),
            TextF(
              controller: _body,
              label: 'الناقص إيه',
              hint: 'مثلاً: 5 مراوح فريش 18 بوصة',
              autofocus: true,
              maxLines: 2,
            ),
            const Gap(),
            TextF(controller: _from, label: 'من مين / التوكيل (اختياري)', icon: Icons.storefront_outlined),
            const Gap(14),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('ضيفه للنواقص'),
            ),
          ],
        ),
      );
}
