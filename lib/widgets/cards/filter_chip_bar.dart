import 'package:flutter/material.dart';
import 'package:medito/widgets/cards/card_tokens.dart';

/// One choice in a [FilterChipBar].
@immutable
class FilterOption<T> {
  const FilterOption(this.value, this.label, {this.key});

  final T value;
  final String label;
  final Key? key;
}

/// A row of single-choice chips that scrolls sideways when it does not fit:
/// the Library's kinds, Explore's Practice and Talks, search's talk lengths.
/// With [allowDeselect], tapping the chosen chip again clears the choice
/// (null).
class FilterChipBar<T> extends StatefulWidget {
  const FilterChipBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.allowDeselect = false,
    this.semanticsLabel,
    this.padding = const EdgeInsets.symmetric(horizontal: kCardGutter),
  });

  final List<FilterOption<T>> options;
  final T? selected;
  final ValueChanged<T?> onSelected;
  final bool allowDeselect;
  final String? semanticsLabel;
  final EdgeInsets padding;

  @override
  State<FilterChipBar<T>> createState() => _FilterChipBarState<T>();
}

/// How wide the edge fade is, in dp.
const _kFadeWidth = 48.0;

class _FilterChipBarState<T> extends State<FilterChipBar<T>> {
  // Whether there is more to scroll to before / after what is showing. The
  // row fades out at an edge with more behind it, so a chip cut off there
  // reads as "scrolls on" rather than as clipped.
  bool _moreBefore = false;
  bool _moreAfter = false;

  bool _update(ScrollMetrics metrics) {
    final before = metrics.extentBefore > 1;
    final after = metrics.extentAfter > 1;
    if (before != _moreBefore || after != _moreAfter) {
      // Metrics arrive during layout, so the rebuild waits for the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _moreBefore = before;
            _moreAfter = after;
          });
        }
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final (moreLeft, moreRight) = rtl
        ? (_moreAfter, _moreBefore)
        : (_moreBefore, _moreAfter);
    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) => _update(n.metrics),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => _update(n.metrics),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fade = constraints.maxWidth.isFinite
                  ? (_kFadeWidth / constraints.maxWidth).clamp(0.0, 0.5)
                  : 0.0;
              final scroller = SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: widget.padding,
                child: Row(
                  children: [
                    for (final (i, option) in widget.options.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      ChoiceChip(
                        key: option.key,
                        label: Text(option.label),
                        selected: option.value == widget.selected,
                        onSelected: (_) => widget.onSelected(
                          option.value == widget.selected &&
                                  widget.allowDeselect
                              ? null
                              : option.value,
                        ),
                      ),
                    ],
                  ],
                ),
              );
              if (!moreLeft && !moreRight) return scroller;
              return ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => LinearGradient(
                  colors: const [
                    Color(0x00FFFFFF),
                    Color(0xFFFFFFFF),
                    Color(0xFFFFFFFF),
                    Color(0x00FFFFFF),
                  ],
                  stops: [0, moreLeft ? fade : 0, moreRight ? 1 - fade : 1, 1],
                ).createShader(rect),
                child: scroller,
              );
            },
          ),
        ),
      ),
    );
  }
}
