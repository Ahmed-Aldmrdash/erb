import 'dart:convert';

import '../core/util/format.dart';
import '../core/util/uuid.dart';

/// A trading season (موسم القمح 2026...), saved in the division settings so
/// every phone of the trade sees the same seasons.
class Season {
  const Season({required this.id, required this.name, required this.from, required this.to});

  final String id;
  final String name;
  final String from;
  final String to;

  Map<String, String> toJson() => {'id': id, 'name': name, 'from': from, 'to': to};

  static Season? fromJson(Object? j) {
    if (j is! Map) return null;
    final from = s(j['from']), to = s(j['to']);
    if (from.isEmpty || to.isEmpty) return null;
    return Season(id: s(j['id']).isEmpty ? newId() : s(j['id']), name: s(j['name']), from: from, to: to);
  }
}

List<Season> seasonsOf(Map<String, String> settings) {
  try {
    final list = jsonDecode(settings['seasons'] ?? '[]') as List;
    return [for (final j in list) ?Season.fromJson(j)]..sort((a, b) => b.from.compareTo(a.from));
  } catch (_) {
    return const [];
  }
}

String seasonsJson(List<Season> seasons) => jsonEncode([for (final x in seasons) x.toJson()]);

/// Usual Egyptian trading seasons of [year], offered when adding a season.
List<Season> seasonPresets(int year) => [
      Season(id: '', name: 'موسم القمح $year', from: '$year-04-01', to: '$year-07-31'),
      Season(id: '', name: 'موسم الذرة والرز $year', from: '$year-08-01', to: '$year-12-31'),
      Season(id: '', name: 'موسم الفول والبصل $year', from: '$year-02-01', to: '$year-05-31'),
    ];
