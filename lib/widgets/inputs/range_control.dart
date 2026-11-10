import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:medito/constants/theme/expressive_typography.dart';

/// A labelled slider over a real-world range. [logarithmic] spaces the track
/// evenly in ratio, as pitch and decay time are heard.
///
/// Horizontal (the default) is a row: the name and the value in its own units
/// above the track, a word for each end below. Vertical is one channel of a
/// mixing desk: the value above, the word for the high end, the track (low at
/// the bottom), the word for the low end, then the name. Put several vertical
/// ones in a [RangeControlBank], which sets them side by side and, when the
/// text is large or the screen narrow, in more than one row.
///
/// Nothing here knows about sounds. It is the "range" of the shared control
/// vocabulary (UX issue #71): the bell maker uses it now, and the synth
/// editors can adopt it without changes to the widget.
class RangeControl extends StatelessWidget {
  const RangeControl({
    super.key,
    required this.label,
    required this.low,
    required this.high,
    required this.min,
    required this.max,
    required this.value,
    required this.format,
    required this.onChanged,
    this.onChangeEnd,
    this.logarithmic = false,
    this.axis = Axis.horizontal,
    this.sliderKey,
  }) : assert(max > min),
       assert(!logarithmic || min > 0);

  /// What it changes ("Pitch").
  final String label;

  /// The words at the two ends of the track ("Deep", "High").
  final String low, high;

  /// The ends of the range, and the current value between them, in the
  /// control's own units.
  final double min, max, value;

  /// The value as the person reads it ("440 Hz").
  final String Function(double) format;

  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final bool logarithmic;

  /// Horizontal is a row; vertical is a channel for a [RangeControlBank].
  final Axis axis;

  /// How long a vertical track is, before the text around it.
  static const verticalTrack = 168.0;

  /// The key of the slider itself, for tests.
  final Key? sliderKey;

  double _toTrack(double v) => logarithmic
      ? math.log(v / min) / math.log(max / min)
      : (v - min) / (max - min);

  double _fromTrack(double t) =>
      logarithmic ? min * math.pow(max / min, t) : min + t * (max - min);

  // The label and the value in its units sit on the slider's own node, the one
  // a screen reader adjusts, so it reads "Pitch, 400 Hz" and moving it speaks
  // the new value in the same units.
  Widget _slider() => MergeSemantics(
    child: Semantics(
      label: label,
      child: Slider(
        key: sliderKey,
        value: _toTrack(value).clamp(0.0, 1.0),
        semanticFormatterCallback: (t) => format(_fromTrack(t)),
        onChanged: (t) => onChanged(_fromTrack(t)),
        onChangeEnd: onChangeEnd == null
            ? null
            : (t) => onChangeEnd!(_fromTrack(t)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) =>
      axis == Axis.vertical ? _vertical(context) : _horizontal(context);

  Widget _vertical(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final muted = type.baseline.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    // One line each, in a box as tall as that style's line, and shrunk rather
    // than cut: a column is narrow, and a word that is clipped is a word that
    // is lost. The fixed height keeps every channel's track at the same level
    // when one channel's word had to shrink.
    final scaler = MediaQuery.textScalerOf(context);
    // The words are for the eye: the slider's own node already says the name
    // and the value, so a screen reader does not hear them twice.
    Widget line(String text, TextStyle? style) => ExcludeSemantics(
      child: SizedBox(
        height: scaler.scale((style?.fontSize ?? 14) * (style?.height ?? 1.4)),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(text, style: style, maxLines: 1),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        line(format(value), type.emphasized.labelMedium),
        const SizedBox(height: 4),
        line(high, muted),
        SizedBox(
          height: verticalTrack,
          // The slider's left end is the bottom of the track, whichever way
          // the text runs: up is more in every language.
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: RotatedBox(quarterTurns: 3, child: _slider()),
          ),
        ),
        line(low, muted),
        const SizedBox(height: 8),
        line(label, type.emphasized.titleSmall),
      ],
    );
  }

  Widget _horizontal(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final muted = type.baseline.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: type.emphasized.titleSmall)),
              Text(format(value), style: muted),
            ],
          ),
          _slider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(low, style: muted),
                Text(high, style: muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical [RangeControl]s side by side. Each gets a column about
/// [columnWidth] wide at the normal text size and as much wider as the text
/// is larger, so the name a person asked to see large is not drawn small; the
/// columns share the width, and when they do not fit in one row the rest
/// continue in the next, so nothing is clipped or scrolled out of reach. In
/// room without a width (a horizontal scroll view) they sit in one row at
/// that width.
class RangeControlBank extends StatelessWidget {
  const RangeControlBank({
    super.key,
    required this.children,
    this.columnWidth = 64,
  });

  final List<Widget> children;
  final double columnWidth;

  @override
  Widget build(BuildContext context) {
    final wanted = MediaQuery.textScalerOf(context).scale(columnWidth);
    return LayoutBuilder(
      builder: (context, box) {
        if (!box.hasBoundedWidth) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final child in children)
                SizedBox(width: wanted, child: child),
            ],
          );
        }
        final perRow = children.isEmpty
            ? 1
            : (box.maxWidth / wanted).floor().clamp(1, children.length);
        final width = box.maxWidth / perRow;
        return Wrap(
          alignment: WrapAlignment.center,
          runSpacing: 16,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}
