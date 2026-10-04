import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db/app_db.dart';
import '../../core/util/format.dart';
import '../../data/labels.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../accounts/party_detail.dart';
import '../appliances/product_detail.dart';
import '../common/open_doc.dart';
import '../notes/notes_screen.dart';

/// سجل الحركات: who added, changed or deleted what, newest first.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _person = '';

  Future<({List<DbRow> rows, List<String> people})> _load() async =>
      (rows: await app.activity.recent(person: _person), people: await app.activity.people());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('سجل الحركات')),
        body: DbBuilder(
          queryKey: _person,
          query: _load,
          builder: (context, d) => Column(
            children: [
              ChipsBar<String>(
                options: {'': 'الكل', for (final p in d.people) p: p},
                value: _person,
                onChanged: (v) => setState(() => _person = v),
              ),
              Expanded(
                child: d.rows.isEmpty
                    ? const EmptyView(icon: Icons.history, text: 'مفيش حركات')
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: d.rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                        itemBuilder: (context, i) => _ActivityTile(d.rows[i]),
                      ),
              ),
            ],
          ),
        ),
      );
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile(this.r);

  final DbRow r;

  @override
  Widget build(BuildContext context) {
    final action = s(r['action']);
    final (icon, color, verb) = switch (action) {
      'deleted' => (Icons.delete_outline, AppColors.bad, 'حذف'),
      'edited' => (Icons.edit_outlined, AppColors.appliances, 'عدّل'),
      _ => (Icons.add_circle_outline, AppColors.good, 'سجّل'),
    };
    final docType = s(r['doc_type']);
    final isMove = docType == 'stock_move';
    final moveQty = n(r['amount']);
    // "زوّد 5 قطعة" instead of a document number nobody can read.
    final what = isMove
        ? _moveTitle(s(r['kind']), moveQty, s(r['item_unit']))
        : [
            docLabel(docType, s(r['kind'])),
            if (s(r['number']).isNotEmpty) s(r['number']),
          ].join(' ');
    final about = switch (docType) {
      'note' => s(r['note_body']),
      'product' => s(r['product_name']),
      'stock_move' => s(r['item_name']),
      _ => s(r['party_name']),
    };
    final amount = n(r['amount']);
    final when = DateTime.tryParse(s(r['updated_at']));
    final who = s(r['who']).isEmpty ? 'حد' : s(r['who']);
    // A movement already reads as a sentence ("زوّد 3 قطعة"), so it does not
    // need "سجّل" in front of it as well.
    final line = isMove
        ? (action == 'added' ? '$who $what' : '$who $verb: $what')
        : '$who $verb $what';
    return ListTile(
      leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color, size: 20)),
      title: Text(line),
      subtitle: Text(
        [
          if (about.isNotEmpty) about,
          if (isMove) ..._moveDetails(r),
          if (!isMove && amount != 0) egp(amount),
          if (!isMove && ni(r['line_count']) > 0) '${ni(r['line_count'])} صنف',
          if (when != null) timeAgo(when.toLocal()),
        ].join(' • '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: action == 'deleted' ? null : () => _open(context, docType),
    );
  }

  /// What a stock movement actually did, in words.
  static String _moveTitle(String kind, double amount, String unit) {
    final u = unit.isEmpty ? '' : ' $unit';
    if (kind == 'transfer') return 'حوّل ${numText(amount.abs())}$u بين المخازن';
    if (amount > 0) return 'زوّد ${numText(amount)}$u في المخزن';
    if (amount < 0) return 'نقّص ${numText(-amount)}$u من المخزن';
    return 'تسوية مخزون من غير فرق';
  }

  static List<String> _moveDetails(DbRow r) {
    final kind = s(r['kind']);
    final from = s(r['warehouse_name']);
    final to = s(r['to_warehouse_name']);
    return [
      if (kind == 'transfer' && from.isNotEmpty && to.isNotEmpty) 'من $from لـ $to',
      if (kind != 'transfer' && from.isNotEmpty) from,
      if (s(r['move_notes']).isNotEmpty) s(r['move_notes']),
      if (s(r['number']).isNotEmpty) 'رقم ${s(r['number'])}',
    ];
  }

  void _open(BuildContext context, String docType) {
    final id = s(r['doc_id']);
    switch (docType) {
      case 'party':
        push(context, PartyDetailScreen(partyId: id));
      case 'product':
        push(context, ProductDetailScreen(productId: id));
      case 'note':
        app.notes.note(id).then((note) {
          if (note != null && context.mounted) showNoteSheet(context, note: note);
        });
      default:
        openDoc(context, docType, id);
    }
  }
}
