import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:medito/constants/theme/expressive_typography.dart';

/// A labelled slider over a real-world range: the name and the value in its
/// own units above, a word for each end below. [logarithmic] spaces the track
/// evenly in ratio, as pitch and decay time are heard.
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

  /// The key of the slider itself, for tests.
  final Key? sliderKey;

  double _toTrack(double v) => logarithmic
      ? math.log(v / min) / math.log(max / min)
      : (v - min) / (max - min);

  double _fromTrack(double t) =>
      logarithmic ? min * math.pow(max / min, t) : min + t * (max - min);

  @override
  Widget build(BuildContext context) {
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
          Semantics(
            label: label,
            value: format(value),
            child: Slider(
              key: sliderKey,
              value: _toTrack(value).clamp(0.0, 1.0),
              onChanged: (t) => onChanged(_fromTrack(t)),
              onChangeEnd: onChangeEnd == null
                  ? null
                  : (t) => onChangeEnd!(_fromTrack(t)),
            ),
          ),
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
