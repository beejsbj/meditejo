import 'package:flutter/material.dart';
import 'package:medito/widgets/cards/card_tokens.dart';

/// One choice in a [FilterChipBar].
@immutable
class FilterOption<T> {
  const FilterOption(this.value, this.label, {this.key, this.leading});

  final T value;
  final String label;
  final Key? key;

  /// A picture for the chip's start (a practice's art on the Library's label
  /// chips): it fills the chip's height, clipped to its shape, with the
  /// label beside it. Null leaves a plain chip.
  final Widget? leading;
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
  bool _frameUpdateScheduled = false;
  bool _pendingMoreBefore = false;
  bool _pendingMoreAfter = false;

  bool _update(ScrollMetrics metrics) {
    _pendingMoreBefore = metrics.extentBefore > 1;
    _pendingMoreAfter = metrics.extentAfter > 1;
    if (!_frameUpdateScheduled &&
        (_pendingMoreBefore != _moreBefore ||
            _pendingMoreAfter != _moreAfter)) {
      _frameUpdateScheduled = true;
      // Metrics arrive during layout, so the rebuild waits for the frame, and
      // then applies the latest state rather than the one that queued it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _frameUpdateScheduled = false;
        if (mounted &&
            (_moreBefore != _pendingMoreBefore ||
                _moreAfter != _pendingMoreAfter)) {
          setState(() {
            _moreBefore = _pendingMoreBefore;
            _moreAfter = _pendingMoreAfter;
          });
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    return false;
  }

  void _choose(T value) => widget.onSelected(
    value == widget.selected && widget.allowDeselect ? null : value,
  );

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
                      if (option.leading case final leading?)
                        _PictureChip(
                          key: option.key,
                          label: option.label,
                          leading: leading,
                          selected: option.value == widget.selected,
                          onTap: () => _choose(option.value),
                        )
                      else
                        ChoiceChip(
                          key: option.key,
                          label: Text(option.label),
                          selected: option.value == widget.selected,
                          onSelected: (_) => _choose(option.value),
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

/// A choice chip that leads with a picture: the picture is a square of the
/// chip's height at its start, clipped to the chip's shape, and the label
/// sits beside it, centred. It takes the theme's chip colours, shape and
/// text styles, so it sits in a row with plain [ChoiceChip]s; chosen, it
/// shows the tick over its picture.
class _PictureChip extends StatelessWidget {
  const _PictureChip({
    super.key,
    required this.label,
    required this.leading,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Widget leading;
  final bool selected;
  final VoidCallback onTap;

  /// A Material 3 chip's height, and the height it takes with its padding.
  static const _height = 32.0;
  static const _tapHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = ChipTheme.of(context);
    final scheme = theme.colorScheme;
    final shape = (chips.shape ?? const StadiumBorder()).copyWith(
      side: selected
          ? BorderSide.none
          : chips.side ?? BorderSide(color: scheme.outlineVariant),
    );
    final style =
        (selected ? chips.secondaryLabelStyle : chips.labelStyle) ??
        theme.textTheme.labelLarge;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      // The whole 48 dp slot takes the tap, as a plain chip's does.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: _tapHeight,
          child: Center(
            child: Material(
              color: selected
                  ? chips.selectedColor ?? scheme.secondaryContainer
                  : chips.backgroundColor ?? scheme.surfaceContainerLow,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox(
                  height: _height,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: _height,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            leading,
                            if (selected) ...[
                              const ColoredBox(color: Color(0x66000000)),
                              const Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 8,
                          end: 12,
                        ),
                        child: Text(label, style: style),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
