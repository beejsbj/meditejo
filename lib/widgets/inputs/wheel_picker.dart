import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';

/// One value a [WheelPicker] can land on, with the words it shows ("6 min",
/// "Off", "Halfway") and, optionally, longer words for a screen reader.
class WheelOption<T> {
  const WheelOption(this.value, this.label, {this.semanticsLabel});

  final T value;
  final String label;
  final String? semanticsLabel;
}

/// A scroll-wheel picker (BRIEF decision 18): the chosen value centred on a
/// tonal band, its neighbours fading and shrinking above and below, as in the
/// iOS time picker. It snaps to a value, ticks under the finger, and reports
/// the value once the wheel comes to rest, so a flick through twenty values
/// writes one setting, not twenty.
///
/// Tapping a neighbour moves to it. With [parseEntry], tapping the centred
/// value (or a long press anywhere) asks for an exact value instead. A screen
/// reader gets one adjustable control: "Interval, 6 min", swipe up or down to
/// step, plus a "Type a value" action when typing is offered.
class WheelPicker<T> extends StatefulWidget {
  const WheelPicker({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.parseEntry,
    this.entryHint,
    this.entryText,
    this.visibleItems = 5,
    this.itemExtent = 40,
  }) : assert(visibleItems >= 3 && visibleItems % 2 == 1);

  /// What the wheel sets, for the screen reader and the typing dialog.
  final String label;
  final List<WheelOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Turns typed text into a value (null: not one of [options]). Null: the
  /// wheel offers no typing; short lists do not need it.
  final T? Function(String text)? parseEntry;

  /// Shown under the typing field, e.g. "1 to 299 minutes".
  final String? entryHint;

  /// The typing field's starting text for a value. Default: a whole number
  /// value as it is (never digits scraped from a label such as "1 h 35 min",
  /// which would read as 135), and nothing for a negative one (a sentinel
  /// such as Halfway).
  final String Function(T value)? entryText;

  static String _defaultEntryText(Object? value) =>
      value is num && value >= 0 ? value.round().toString() : '';

  /// Rows on show, the centred one included.
  final int visibleItems;

  /// One row's height at 1× text; it grows with the text size.
  final double itemExtent;

  @override
  State<WheelPicker<T>> createState() => WheelPickerState<T>();
}

/// Public so tests (and callers that need it) can find the wheel's state.
class WheelPickerState<T> extends State<WheelPicker<T>> {
  late FixedExtentScrollController _controller;
  late int _selected;
  late T _reported;

  /// A finger (or its fling) is moving the wheel: those ticks buzz.
  bool _userDriven = false;

  // Computed once: the token re-runs its spring simulation on every read.
  static final _settle = MeditejoMotion.standardSpatial.duration;
  static final _settleCurve = MeditejoMotion.standardSpatial.curve;

  int get selectedIndex => _selected;

  int _indexOf(T value) {
    final i = widget.options.indexWhere((o) => o.value == value);
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    _selected = _indexOf(widget.value);
    _reported = widget.value;
    _controller = FixedExtentScrollController(initialItem: _selected);
  }

  @override
  void didUpdateWidget(WheelPicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _indexOf(widget.value);
    _reported = widget.value;
    final moving =
        _controller.hasClients &&
        _controller.position.isScrollingNotifier.value;
    // The value changed elsewhere (or the options did): follow it, unless the
    // user is in the middle of turning the wheel.
    if (!moving && target != _selected) {
      _selected = target;
      if (_controller.hasClients) _controller.jumpToItem(target);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _report(int index) {
    final value = widget.options[index].value;
    if (value == _reported) return;
    _reported = value;
    widget.onChanged(value);
  }

  /// Moves to [index] and reports it at once (not when the motion ends, so a
  /// sheet closed mid-motion still keeps the choice).
  void moveTo(int index) {
    final i = index.clamp(0, widget.options.length - 1);
    _report(i);
    if (!_controller.hasClients) return;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.jumpToItem(i);
    } else {
      unawaited(
        _controller.animateToItem(i, duration: _settle, curve: _settleCurve),
      );
    }
  }

  Future<void> typeEntry() async {
    final parse = widget.parseEntry;
    if (parse == null) return;
    final value = await showDialog<T>(
      context: context,
      builder: (_) => _EntryDialog<T>(
        label: widget.label,
        hint: widget.entryHint,
        initial:
            widget.entryText?.call(widget.options[_selected].value) ??
            WheelPicker._defaultEntryText(widget.options[_selected].value),
        parse: parse,
      ),
    );
    if (!mounted || value == null) return;
    final index = widget.options.indexWhere((o) => o.value == value);
    if (index >= 0) moveTo(index);
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _userDriven = true;
    } else if (n is ScrollEndNotification) {
      _userDriven = false;
      _report(_selected);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final extent = MediaQuery.textScalerOf(
      context,
    ).scale(widget.itemExtent).clamp(widget.itemExtent, double.infinity);
    final last = widget.options.length - 1;
    String spoken(int i) =>
        widget.options[i].semanticsLabel ?? widget.options[i].label;
    final centre = type.emphasized.titleLarge!.copyWith(
      color: scheme.onSecondaryContainer,
    );
    final neighbour = type.baseline.titleMedium!.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final wheel = SizedBox(
      height: extent * widget.visibleItems,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The band the chosen value sits on.
          Container(
            height: extent,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(MeditejoShapes.large),
            ),
          ),
          NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: ListWheelScrollView.useDelegate(
              controller: _controller,
              itemExtent: extent,
              physics: const FixedExtentScrollPhysics(),
              diameterRatio: 2.4,
              perspective: 0.002,
              onSelectedItemChanged: (i) {
                setState(() => _selected = i);
                if (_userDriven) unawaited(HapticFeedback.selectionClick());
              },
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: widget.options.length,
                builder: (context, i) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: i == _selected ? typeEntry : () => moveTo(i),
                  onLongPress: widget.parseEntry == null ? null : typeEntry,
                  child: _WheelItem(
                    controller: _controller,
                    index: i,
                    extent: extent,
                    label: widget.options[i].label,
                    centre: centre,
                    neighbour: neighbour,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      label: widget.label,
      value: spoken(_selected),
      increasedValue: _selected < last ? spoken(_selected + 1) : null,
      decreasedValue: _selected > 0 ? spoken(_selected - 1) : null,
      onIncrease: _selected < last ? () => moveTo(_selected + 1) : null,
      onDecrease: _selected > 0 ? () => moveTo(_selected - 1) : null,
      customSemanticsActions: widget.parseEntry == null
          ? null
          : {const CustomSemanticsAction(label: 'Type a value'): typeEntry},
      // The rows are a run of loose labels to a screen reader; the control
      // above says which is chosen and what it sets.
      child: ExcludeSemantics(child: wheel),
    );
  }
}

/// One row, styled by its distance from the centre: the chosen value in the
/// emphasized style on the band, neighbours lighter, fainter and smaller.
class _WheelItem extends StatelessWidget {
  const _WheelItem({
    required this.controller,
    required this.index,
    required this.extent,
    required this.label,
    required this.centre,
    required this.neighbour,
  });

  final FixedExtentScrollController controller;
  final int index;
  final double extent;
  final String label;
  final TextStyle centre, neighbour;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final at = controller.hasClients
            ? controller.offset / extent
            : controller.initialItem.toDouble();
        final distance = (at - index).abs();
        final t = distance.clamp(0.0, 1.0);
        return Center(
          child: Opacity(
            opacity: (1 - distance * 0.3).clamp(0.2, 1.0),
            child: Transform.scale(
              scale: 1 - distance.clamp(0.0, 2.0) * 0.07,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle.lerp(centre, neighbour, t),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EntryDialog<T> extends StatefulWidget {
  const _EntryDialog({
    required this.label,
    required this.hint,
    required this.initial,
    required this.parse,
  });

  final String label;
  final String? hint;
  final String initial;
  final T? Function(String) parse;

  @override
  State<_EntryDialog<T>> createState() => _EntryDialogState<T>();
}

class _EntryDialogState<T> extends State<_EntryDialog<T>> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  bool _invalid = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = widget.parse(_text.text.trim());
    if (value == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.label),
      content: TextField(
        key: const ValueKey('wheel_picker_entry'),
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onChanged: (_) => _invalid ? setState(() => _invalid = false) : null,
        decoration: InputDecoration(
          helperText: _invalid ? null : widget.hint,
          errorText: _invalid ? (widget.hint ?? 'Not a value here') : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(material.cancelButtonLabel),
        ),
        TextButton(onPressed: _submit, child: Text(material.okButtonLabel)),
      ],
    );
  }
}
