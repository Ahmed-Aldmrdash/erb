import 'dart:math';

import 'package:flutter/material.dart';

import '../core/util/format.dart';
import 'theme.dart';

/// Small bar chart of the last days (one or two series), drawn by hand to
/// avoid a chart dependency.
class MiniBarChart extends StatelessWidget {
  const MiniBarChart({
    super.key,
    required this.dates,
    required this.a,
    this.b,
    required this.colorA,
    this.colorB,
    this.height = 140,
  });

  final List<String> dates;
  final List<double> a;
  final List<double>? b;
  final Color colorA;
  final Color? colorB;
  final double height;

  static const _days = ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'];

  @override
  Widget build(BuildContext context) {
    final maxV = [...a, ...?b].fold<double>(0, max);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < dates.length; i++)
            Expanded(
              child: Tooltip(
                message: '${showDate(dates[i])}\n${money(a[i])}${b != null ? ' / ${money(b![i])}' : ''}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _bar(a[i], maxV, colorA),
                          if (b != null) ...[const SizedBox(width: 2), _bar(b![i], maxV, colorB ?? AppColors.muted)],
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _days[(parseDate(dates[i])?.weekday ?? 1) - 1],
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(double v, double maxV, Color color) => LayoutBuilder(
        builder: (context, c) {
          final h = maxV <= 0 ? 0.0 : (v / maxV) * c.maxHeight;
          return Container(
            width: b == null ? 18 : 10,
            height: max(v > 0 ? 3.0 : 0.0, h),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          );
        },
      );
}
