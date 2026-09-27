import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/db/schema.dart';
import '../../core/util/format.dart';
import '../../data/labels.dart';
import '../../ui/share.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Reminders shared by everybody: money left with one person for another,
/// tasks and notes. Nothing gets forgotten because it stays open until
/// somebody marks it done, and the app shows who did.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  bool _done = false;
  String _search = '';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('التذكيرات والملاحظات')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showNoteSheet(context),
          icon: const Icon(Icons.add),
          label: const Text('تذكير جديد'),
        ),
        body: Column(
          children: [
            SearchField(onChanged: (v) => setState(() => _search = v)),
            ChipsBar<bool>(
              options: const {false: 'مفتوحة', true: 'خلصت'},
              value: _done,
              onChanged: (v) => setState(() => _done = v),
            ),
            Expanded(
              child: DbBuilder<List<DbRow>>(
                queryKey: (_done, _search),
                query: () => app.notes.list(done: _done, search: _search),
                builder: (context, rows) {
                  if (rows.isEmpty) {
                    return EmptyView(
                      icon: _done ? Icons.task_alt : Icons.sticky_note_2_outlined,
                      text: _done ? 'مفيش حاجة خلصت لسه' : 'مفيش تذكيرات مفتوحة 👌',
                      actionLabel: _done ? null : 'تذكير جديد',
                      onAction: _done ? null : () => showNoteSheet(context),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => NoteCard(rows[i]),
                  );
                },
              ),
            ),
          ],
        ),
      );
}

({Color color, Color soft, IconData icon}) noteStyle(String kind) => switch (kind) {
      'money' => (color: const Color(0xFFB7791F), soft: const Color(0xFFFFF4DC), icon: Icons.payments_outlined),
      'task' => (color: AppColors.appliances, soft: AppColors.appliancesSoft, icon: Icons.checklist_rounded),
      _ => (color: AppColors.accounts, soft: AppColors.accountsSoft, icon: Icons.sticky_note_2_outlined),
    };

class NoteCard extends StatelessWidget {
  const NoteCard(this.r, {super.key, this.compact = false});

  final DbRow r;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final st = noteStyle(s(r['kind']));
    final done = n(r['done']) == 1;
    final due = s(r['due_date']);
    final overdue = !done && due.isNotEmpty && due.compareTo(todayStr()) < 0;
    final dueToday = !done && due == todayStr();
    final amount = n(r['amount']);
    return Material(
      color: done ? Colors.white : st.soft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: overdue ? AppColors.bad : (done ? AppColors.border : st.color.withValues(alpha: 0.25))),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showNoteSheet(context, note: r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: done,
                activeColor: AppColors.good,
                onChanged: (v) => app.notes.setDone(s(r['id']), v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(st.icon, size: 18, color: st.color),
                        const SizedBox(width: 6),
                        Text(noteKinds[r['kind']] ?? '', style: TextStyle(color: st.color, fontWeight: FontWeight.w700, fontSize: 12.5)),
                        if (r['division'] == Division.all) ...[const SizedBox(width: 6), const Pill('للقسمين', color: AppColors.accounts)],
                        if (n(r['pinned']) == 1) ...[const SizedBox(width: 6), Icon(Icons.push_pin, size: 16, color: st.color)],
                        const Spacer(),
                        if (due.isNotEmpty)
                          Pill(
                            overdue ? 'متأخر ${showDate(due)}' : (dueToday ? 'النهارده' : showDate(due)),
                            color: overdue ? AppColors.bad : (dueToday ? AppColors.warn : AppColors.muted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s(r['body']),
                      maxLines: compact ? 2 : 6,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? AppColors.muted : AppColors.text,
                      ),
                    ),
                    if (amount > 0 || s(r['person']).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 12,
                        children: [
                          if (amount > 0)
                            Text(egp(amount), style: TextStyle(fontWeight: FontWeight.w800, color: st.color, fontSize: 16)),
                          if (s(r['person']).isNotEmpty)
                            Text('لـ ${s(r['person'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      done
                          ? 'خلصها ${s(r['done_by'])} ${_ago(s(r['done_at']))}'
                          : 'كتبها ${s(r['created_by_name'])} ${_ago(s(r['created_at']))}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _ago(String iso) {
    final t = DateTime.tryParse(iso);
    return t == null ? '' : timeAgo(t.toLocal());
  }
}

Future<void> showNoteSheet(BuildContext context, {DbRow? note, String? presetBody, double? presetAmount}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NoteSheet(note: note, presetBody: presetBody, presetAmount: presetAmount),
    );

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({this.note, this.presetBody, this.presetAmount});

  final DbRow? note;
  final String? presetBody;
  final double? presetAmount;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late String _kind = s(widget.note?['kind']).isEmpty ? 'note' : s(widget.note?['kind']);
  late final _body = TextEditingController(text: s(widget.note?['body']).isEmpty ? (widget.presetBody ?? '') : s(widget.note?['body']));
  late final _amount = TextEditingController(text: numText(widget.note == null ? widget.presetAmount : n(widget.note!['amount'])));
  late final _person = TextEditingController(text: s(widget.note?['person']));
  late String _due = s(widget.note?['due_date']);
  late bool _both = widget.note?['division'] == Division.all;
  late bool _pinned = n(widget.note?['pinned']) == 1;
  bool _busy = false;

  bool get _isEdit => widget.note != null;

  Future<void> _save() async {
    if (_body.text.trim().isEmpty && parseNum(_amount.text) <= 0) {
      toast(context, 'اكتب التذكير', error: true);
      return;
    }
    setState(() => _busy = true);
    await app.notes.save({
      'kind': _kind,
      'body': _body.text.trim(),
      'amount': parseNum(_amount.text),
      'person': _person.text.trim(),
      'due_date': _due.isEmpty ? null : _due,
      'pinned': _pinned,
      'division': _both ? Division.all : app.division,
    }, id: _isEdit ? s(widget.note!['id']) : null);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_isEdit ? 'تعديل التذكير' : 'تذكير جديد', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                if (_isEdit) ...[
                  IconButton(
                    tooltip: 'واتساب',
                    onPressed: () => openWhatsApp(context, null, _shareText()),
                    icon: const Icon(Icons.chat_outlined),
                  ),
                  IconButton(
                    tooltip: 'حذف',
                    onPressed: () async {
                      final ok = await confirmDialog(context, title: 'حذف التذكير', message: 'متأكد؟', ok: 'حذف', danger: true);
                      if (!ok) return;
                      await app.notes.delete(s(widget.note!['id']));
                      if (context.mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete_outline, color: AppColors.bad),
                  ),
                ],
              ],
            ),
            const Gap(8),
            Choice<String>(options: noteKinds, value: _kind, onChanged: (v) => setState(() => _kind = v)),
            const Gap(),
            TextF(
              controller: _body,
              label: switch (_kind) {
                'money' => 'مين ساب الفلوس ولمين؟ (مثلاً: الحاج سيد ساب فلوس لأحمد)',
                'task' => 'المطلوب إيه؟',
                _ => 'الملاحظة',
              },
              maxLines: 4,
              autofocus: !_isEdit,
            ),
            const Gap(),
            Row(
              children: [
                if (_kind == 'money') ...[
                  Expanded(child: NumField(controller: _amount, label: 'المبلغ', suffix: currency)),
                  const SizedBox(width: 10),
                ],
                Expanded(child: TextF(controller: _person, label: 'لمين؟', icon: Icons.person_outline)),
              ],
            ),
            const Gap(),
            Row(
              children: [
                const Text('فكرني يوم:', style: TextStyle(color: AppColors.muted)),
                const SizedBox(width: 6),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in {
                        'النهارده': dateStr(today),
                        'بكرة': dateStr(today.add(const Duration(days: 1))),
                        'بعد أسبوع': dateStr(today.add(const Duration(days: 7))),
                      }.entries)
                        ChoiceChip(
                          label: Text(e.key),
                          selected: _due == e.value,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _due = _due == e.value ? '' : e.value),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.event, size: 18),
                        label: Text(_due.isEmpty ? 'تاريخ' : showDate(_due)),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: parseDate(_due) ?? today,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setState(() => _due = dateStr(d));
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _both,
              onChanged: (v) => setState(() => _both = v),
              title: const Text('يظهر في القسمين'),
              subtitle: const Text('المعرض والتجارة يشوفوه'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
              title: const Text('تثبيت فوق'),
            ),
            if (_isEdit) ByLine(row: widget.note!),
            const Gap(),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  String _shareText() => [
        'تذكير: ${_body.text.trim()}',
        if (parseNum(_amount.text) > 0) 'المبلغ: ${egp(parseNum(_amount.text))}',
        if (_person.text.trim().isNotEmpty) 'لـ: ${_person.text.trim()}',
        if (_due.isNotEmpty) 'يوم: ${showDate(_due)}',
        '— ${app.person}',
      ].join('\n');
}
