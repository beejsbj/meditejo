import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/widgets/inputs/wheel_picker.dart';

/// The shared control vocabulary every sound's editor is built from (#71):
/// chips, a range, a wheel, a row of ranges, and the Swell toggle. A sound
/// does not get its own hand-built editor; it gets a curated list of these
/// (its spec, in `sound_control_spec.dart`), and [SoundControlView] draws
/// any of them the same way wherever it appears.
///
/// Every control reads its value out of a layer's params and writes a new
/// params map back, so the params' JSON (what presets, the current mix and
/// a session's `layers:` choice store) is the one source of truth.
typedef SoundParams = Map<String, Object?>;

/// Words for the user, looked up when drawn.
typedef SoundText = String Function(AppLocalizations l10n);

sealed class SoundControl {
  const SoundControl({required this.id, required this.title});

  /// The control's widget key, and the prefix of its parts' keys.
  final String id;

  /// What it sets: its heading, and its name to a screen reader.
  final SoundText title;
}

/// One named choice a [SoundChips] offers.
class SoundChoice<T> {
  const SoundChoice(this.value, this.id, this.label);

  final T value;

  /// The chip's key is `<control id>_<id>`.
  final String id;
  final SoundText label;
}

/// Named choices. One at a time, or up to [maxSelected] together (a drone
/// chord, #69). A [fine] control, when given, sits under the chips and
/// refines what they chose (the binaural beat within its band; the noise
/// bands under a shape).
class SoundChips<T> extends SoundControl {
  const SoundChips({
    required super.id,
    required super.title,
    required this.choices,
    required this.read,
    required this.write,
    this.maxSelected = 1,
    this.otherLabel,
    this.restoreOther,
    this.caption,
    this.fine,
    this.fineFolds = false,
  }) : assert(maxSelected >= 1),
       assert(otherLabel == null || restoreOther != null);

  final List<SoundChoice<T>> choices;

  /// The choices the params hold; empty when they match none.
  final Set<T> Function(SoundParams params) read;

  /// The params with [selected] chosen (never empty).
  final SoundParams Function(SoundParams params, Set<T> selected) write;

  final int maxSelected;

  /// Shown as a selected chip of its own when the params match no choice
  /// (bands shaped by hand), so the editor never shows nothing chosen.
  /// Once such params have been seen, the chip stays while the editor is
  /// open, and choosing it brings them back ([restoreOther]): a tap on a
  /// name never loses a curve drawn by hand.
  final SoundText? otherLabel;

  /// [current] with what these chips set taken from [remembered] (params
  /// that matched no choice): the noise's bands, its colour left alone.
  final SoundParams Function(SoundParams current, SoundParams remembered)?
  restoreOther;

  /// A line under the chips about what is chosen ("4–8 Hz").
  final String? Function(AppLocalizations l10n, SoundParams params)? caption;

  final SoundControl? fine;

  /// The [fine] control starts folded under its title (unless the params
  /// match no choice, when it is what made them).
  final bool fineFolds;

  /// [write] for a view that does not know [T].
  SoundParams choose(SoundParams params, Iterable<Object?> selected) =>
      write(params, {for (final v in selected) v as T});
}

/// A value along a range, with its reading in the heading.
class SoundRange extends SoundControl {
  const SoundRange({
    required super.id,
    required super.title,
    required this.read,
    required this.write,
    this.min = 0,
    this.max = 1,
    this.readout,
  });

  final double Function(SoundParams params) read;
  final SoundParams Function(SoundParams params, double value) write;
  final double min;
  final double max;

  /// The value in words ("200 Hz"); null: the heading has no reading.
  final String Function(AppLocalizations l10n, double value)? readout;
}

/// A wheel of exact steps (BRIEF decision 18's [WheelPicker]).
class SoundWheel<T> extends SoundControl {
  const SoundWheel({
    required super.id,
    required super.title,
    required this.options,
    required this.read,
    required this.write,
  });

  final List<WheelOption<T>> Function(AppLocalizations l10n, SoundParams p)
  options;
  final T Function(SoundParams params) read;
  final SoundParams Function(SoundParams params, T value) write;

  /// [write] for a view that does not know [T].
  SoundParams apply(SoundParams params, Object? value) =>
      write(params, value as T);
}

/// Ranges side by side, upright, for levels that belong together (the
/// noise's ten bands).
class SoundRanges extends SoundControl {
  const SoundRanges({
    required super.id,
    required super.title,
    required this.count,
    required this.label,
    required this.read,
    required this.write,
    required this.partId,
  });

  final int count;

  /// The words under range [i] ("1k").
  final String Function(int i) label;
  final double Function(SoundParams params, int i) read;
  final SoundParams Function(SoundParams params, int i, double value) write;

  /// Range [i]'s key.
  final String Function(int i) partId;
}

/// What a control does with a change: [live] while a finger is still on a
/// range (shown, not yet applied), otherwise applied to the layer.
typedef SoundParamsChanged = void Function(SoundParams next, {bool live});

/// Draws any [SoundControl] for [params].
class SoundControlView extends StatelessWidget {
  const SoundControlView({
    super.key,
    required this.control,
    required this.params,
    required this.onChanged,
  });

  final SoundControl control;
  final SoundParams params;
  final SoundParamsChanged onChanged;

  @override
  Widget build(BuildContext context) => switch (control) {
    final SoundChips<Object?> c => _ChipsView(
      key: ValueKey(c.id),
      control: c,
      params: params,
      onChanged: onChanged,
    ),
    final SoundRange c => _RangeView(
      control: c,
      params: params,
      onChanged: onChanged,
    ),
    final SoundWheel<Object?> c => _WheelView(
      control: c,
      params: params,
      onChanged: onChanged,
      heading: true,
    ),
    final SoundRanges c => _RangesView(
      control: c,
      params: params,
      onChanged: onChanged,
    ),
  };
}

/// A control's heading: its title, and a reading after a dot.
class SoundControlHeading extends StatelessWidget {
  const SoundControlHeading(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding16,
        padding16,
        trailing == null ? padding16 : padding8,
        6,
      ),
      child: trailing == null
          ? title
          : Row(
              children: [
                Expanded(child: title),
                trailing!,
              ],
            ),
    );
  }
}

class _ChipsView extends StatefulWidget {
  const _ChipsView({
    super.key,
    required this.control,
    required this.params,
    required this.onChanged,
  });

  final SoundChips<Object?> control;
  final SoundParams params;
  final SoundParamsChanged onChanged;

  @override
  State<_ChipsView> createState() => _ChipsViewState();
}

class _ChipsViewState extends State<_ChipsView> {
  SoundChips<Object?> get _c => widget.control;

  /// Folded only where the chips' own choice explains the params.
  late bool _folded = _c.fineFolds && _c.read(widget.params).isNotEmpty;

  /// The last params this editor saw that matched no choice (a curve drawn
  /// by hand), kept so the "other" chip can bring them back.
  SoundParams? _other;

  void _remember(SoundParams params) {
    if (_c.otherLabel != null && _c.read(params).isEmpty) _other = params;
  }

  @override
  void initState() {
    super.initState();
    _remember(widget.params);
  }

  @override
  void didUpdateWidget(_ChipsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _remember(widget.params);
  }

  void _restoreOther(Set<Object?> selected) {
    final other = _other;
    final restore = _c.restoreOther;
    // Already showing it: nothing to bring back.
    if (other == null || restore == null || selected.isEmpty) return;
    widget.onChanged(restore(widget.params, other));
  }

  void _toggle(Object? value, bool on, Set<Object?> selected) {
    final Set<Object?> next;
    if (_c.maxSelected == 1) {
      // Tapping the chosen chip again keeps it: one is always chosen.
      if (!on || selected.contains(value)) return;
      next = {value};
    } else {
      next = on ? {...selected, value} : ({...selected}..remove(value));
      if (next.isEmpty || next.length > _c.maxSelected) return;
    }
    widget.onChanged(_c.choose(widget.params, next));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final selected = _c.read(widget.params);
    final multi = _c.maxSelected > 1;
    final full = multi && selected.length >= _c.maxSelected;
    final other = _c.otherLabel;
    final caption = _c.caption?.call(l10n, widget.params);
    final fine = _c.fine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoundControlHeading(_c.title(l10n)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: padding16),
          child: Wrap(
            spacing: padding8,
            runSpacing: padding8,
            children: [
              for (final choice in _c.choices)
                if (multi)
                  Semantics(
                    // Why a tap on the last chosen chip does nothing.
                    hint:
                        selected.length == 1 && selected.contains(choice.value)
                        ? l10n.soundChipsKeepOne
                        : null,
                    child: FilterChip(
                      key: ValueKey('${_c.id}_${choice.id}'),
                      label: Text(choice.label(l10n)),
                      selected: selected.contains(choice.value),
                      // A full chord takes no more notes until one comes off.
                      onSelected: full && !selected.contains(choice.value)
                          ? null
                          : (on) => _toggle(choice.value, on, selected),
                    ),
                  )
                else
                  ChoiceChip(
                    key: ValueKey('${_c.id}_${choice.id}'),
                    label: Text(choice.label(l10n)),
                    selected: selected.contains(choice.value),
                    onSelected: (on) => _toggle(choice.value, on, selected),
                  ),
              if (other != null && (selected.isEmpty || _other != null))
                ChoiceChip(
                  key: ValueKey('${_c.id}_other'),
                  label: Text(other(l10n)),
                  selected: selected.isEmpty,
                  // After a name replaced the curve, this brings it back.
                  onSelected: (_) => _restoreOther(selected),
                ),
            ],
          ),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(padding16, 6, padding16, 0),
            child: Text(
              caption,
              key: ValueKey('${_c.id}_caption'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (fine != null && _c.fineFolds)
          SoundControlHeading(
            fine.title(l10n),
            trailing: IconButton(
              key: ValueKey('${fine.id}_fold'),
              tooltip: _folded
                  ? MaterialLocalizations.of(context).collapsedIconTapHint
                  : MaterialLocalizations.of(context).expandedIconTapHint,
              onPressed: () => setState(() => _folded = !_folded),
              icon: Icon(
                _folded
                    ? Symbols.keyboard_arrow_down_rounded
                    : Symbols.keyboard_arrow_up_rounded,
              ),
            ),
          ),
        if (fine != null && !(_c.fineFolds && _folded))
          Padding(
            padding: EdgeInsets.only(top: _c.fineFolds ? 0 : padding8),
            child: switch (fine) {
              final SoundWheel<Object?> w => _WheelView(
                control: w,
                params: widget.params,
                onChanged: widget.onChanged,
                heading: false,
              ),
              final SoundRanges r => _RangesView(
                control: r,
                params: widget.params,
                onChanged: widget.onChanged,
                heading: false,
              ),
              _ => SoundControlView(
                control: fine,
                params: widget.params,
                onChanged: widget.onChanged,
              ),
            },
          ),
      ],
    );
  }
}

class _RangeView extends StatelessWidget {
  const _RangeView({
    required this.control,
    required this.params,
    required this.onChanged,
  });

  final SoundRange control;
  final SoundParams params;
  final SoundParamsChanged onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final value = control.read(params).clamp(control.min, control.max);
    final readout = control.readout?.call(l10n, value);
    final title = control.title(l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoundControlHeading(readout == null ? title : '$title · $readout'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: padding8),
          child: Slider(
            key: ValueKey(control.id),
            min: control.min,
            max: control.max,
            value: value,
            activeColor: context.brandAccent,
            semanticFormatterCallback: (v) =>
                control.readout?.call(l10n, v) ?? '${(v * 100).round()}%',
            onChanged: (v) => onChanged(control.write(params, v), live: true),
            onChangeEnd: (v) => onChanged(control.write(params, v)),
          ),
        ),
      ],
    );
  }
}

class _WheelView extends StatelessWidget {
  const _WheelView({
    required this.control,
    required this.params,
    required this.onChanged,
    required this.heading,
  });

  final SoundWheel<Object?> control;
  final SoundParams params;
  final SoundParamsChanged onChanged;
  final bool heading;

  /// As wide as the Customize wheels.
  static const width = 140.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scaler = MediaQuery.textScalerOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading) SoundControlHeading(control.title(l10n)),
        Center(
          child: SizedBox(
            width: scaler.scale(width).clamp(width, 220),
            child: WheelPicker<Object?>(
              key: ValueKey(control.id),
              label: control.title(l10n),
              options: control.options(l10n, params),
              value: control.read(params),
              onChanged: (v) => onChanged(control.apply(params, v)),
            ),
          ),
        ),
      ],
    );
  }
}

class _RangesView extends StatelessWidget {
  const _RangesView({
    required this.control,
    required this.params,
    required this.onChanged,
    this.heading = true,
  });

  final SoundRanges control;
  final SoundParams params;
  final SoundParamsChanged onChanged;
  final bool heading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      key: ValueKey(control.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading) SoundControlHeading(control.title(l10n)),
        SizedBox(
          height: 200,
          child: Row(
            children: [
              for (var i = 0; i < control.count; i++)
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            key: ValueKey(control.partId(i)),
                            value: control.read(params, i),
                            activeColor: context.brandAccent,
                            semanticFormatterCallback: (v) =>
                                '${control.label(i)} Hz ${(v * 100).round()}%',
                            onChanged: (v) => onChanged(
                              control.write(params, i, v),
                              live: true,
                            ),
                            onChangeEnd: (v) =>
                                onChanged(control.write(params, i, v)),
                          ),
                        ),
                      ),
                      // Ten across a 360 dp phone: a label shrinks rather
                      // than run into its neighbour.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            control.label(i),
                            maxLines: 1,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The Swell toggle every layer has (#70), with its caption beside it.
class SwellToggle extends StatelessWidget {
  const SwellToggle({
    super.key,
    this.chipKey,
    required this.selected,
    required this.onChanged,
  });

  /// The chip's own key (the caption beside it does not toggle).
  final Key? chipKey;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterChip(
          key: chipKey,
          avatar: const Icon(Symbols.waves_rounded),
          label: Text(l10n.soundsSwell),
          selected: selected,
          // The waves stay; the tonal fill says it is on.
          showCheckmark: false,
          onSelected: onChanged,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            l10n.soundsSwellHint,
            style: context.typography.baseline.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
