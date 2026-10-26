import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/services/stats/practice_summary.dart';
import 'package:medito/views/stats/stats_format.dart';

/// Bars of minutes practised each day, oldest to newest, ending today.
///
/// One series in one colour, so no legend: the card names it. Bars are thin,
/// rounded at the data end and sit on the baseline; a single gridline marks
/// the top of the scale. Touch or drag to read a day; with nothing touched
/// the readout gives the range's total.
class DailyBars extends StatefulWidget {
  const DailyBars({super.key, required this.days, this.height = 140});

  /// 7 or 30 days, oldest first.
  final List<DayTotal> days;
  final double height;

  @override
  State<DailyBars> createState() => _DailyBarsState();
}

class _DailyBarsState extends State<DailyBars> {
  int? _selected;

  @override
  void didUpdateWidget(DailyBars old) {
    super.didUpdateWidget(old);
    if (old.days.length != widget.days.length) _selected = null;
  }

  void _select(Offset local, double width) {
    final slot = width / widget.days.length;
    final index = (local.dx / slot).floor().clamp(0, widget.days.length - 1);
    if (index != _selected) setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final days = widget.days;

    final peakMinutes = days.fold<int>(
      0,
      (peak, d) => d.time.inMinutes > peak ? d.time.inMinutes : peak,
    );
    final ceiling = chartCeilingMinutes(peakMinutes);
    final total = days.fold(Duration.zero, (sum, d) => sum + d.time);
    final practised = days.where((d) => d.practised).length;
    final selected = _selected == null ? null : days[_selected!];

    final readout = selected == null
        ? l10n.statsChartTotal(
            formatPractice(total, l10n),
            practised,
            days.length,
          )
        : '${formatDay(selected.day, locale)} · ${formatPractice(selected.time, l10n)}';

    // Weekday names under 7 bars; a few dates under 30.
    final labelEvery = days.length <= 7 ? 1 : 7;
    String labelFor(int i) => days.length <= 7
        ? DateFormat.E(locale).format(days[i].day)
        : DateFormat.MMMd(locale).format(days[i].day);

    return Semantics(
      container: true,
      label: '${l10n.statsDailyMinutes}. $readout',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Live region, so the touched day is read out.
          Semantics(
            liveRegion: true,
            child: Text(
              readout,
              key: const ValueKey('daily_bars_readout'),
              style: type.baseline.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ExcludeSemantics(
            child: SizedBox(
              height: widget.height,
              child: LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _select(d.localPosition, box.maxWidth),
                  onHorizontalDragStart: (d) =>
                      _select(d.localPosition, box.maxWidth),
                  onHorizontalDragUpdate: (d) =>
                      _select(d.localPosition, box.maxWidth),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _BarsPainter(
                            minutes: [
                              for (final d in days) d.time.inSeconds / 60,
                            ],
                            ceiling: ceiling.toDouble(),
                            selected: _selected,
                            bar: scheme.primary,
                            faded: scheme.primary.withValues(alpha: 0.4),
                            rest: scheme.surfaceContainerHighest,
                            grid: scheme.outlineVariant,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        child: Text(
                          '$ceiling ${l10n.min}',
                          style: type.baseline.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ExcludeSemantics(
            // OverflowBox sizes to its parent, so the row needs a height: a
            // line of label text at the user's text size.
            child: SizedBox(
              height: MediaQuery.textScalerOf(context).scale(18),
              child: Row(
                children: [
                  for (var i = 0; i < days.length; i++)
                    Expanded(
                      child: (days.length - 1 - i) % labelEvery == 0
                          ? OverflowBox(
                              maxWidth: 64,
                              child: Text(
                                labelFor(i),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                style: type.baseline.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.minutes,
    required this.ceiling,
    required this.selected,
    required this.bar,
    required this.faded,
    required this.rest,
    required this.grid,
  });

  final List<double> minutes;
  final double ceiling;
  final int? selected;
  final Color bar, faded, rest, grid;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 2.0;
    const labelRoom = 16.0; // under the scale's label
    final base = size.height - 1;
    final top = labelRoom;

    canvas.drawLine(
      Offset(0, top),
      Offset(size.width, top),
      Paint()
        ..color = grid.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    final slot = size.width / minutes.length;
    final width = (slot - gap).clamp(2.0, 18.0);
    final paint = Paint();
    for (var i = 0; i < minutes.length; i++) {
      final cx = slot * i + slot / 2;
      final fraction = (minutes[i] / ceiling).clamp(0.0, 1.0);
      // A day with practice never rounds down to nothing.
      final h = minutes[i] <= 0
          ? 2.0
          : (fraction * (base - top)).clamp(3.0, base - top);
      paint.color = minutes[i] <= 0
          ? rest
          : (selected == null || selected == i ? bar : faded);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - width / 2, base - h, width, h),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.minutes != minutes ||
      old.ceiling != ceiling ||
      old.selected != selected ||
      old.bar != bar;
}
