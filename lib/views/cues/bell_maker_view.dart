import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/cues/custom_bell_provider.dart';
import 'package:medito/services/audio/session_bell_preview.dart';
import 'package:medito/services/bells/bell_recipe.dart';
import 'package:medito/services/bells/bell_recipes.dart';
import 'package:medito/services/bells/bell_synth.dart';
import 'package:medito/services/bells/custom_bell.dart';
import 'package:medito/services/bells/custom_bell_store.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/art/engine/bell.dart';
import 'package:path_provider/path_provider.dart';

/// Opens the bell maker, starting from the bell a cue rings now ([from] is a
/// cue sound: a bundled bell's asset path or a made bell's id). Completes
/// with the bell that was saved, or null if the user left without saving.
Future<CustomBell?> showBellMaker(
  BuildContext context, {
  String from = '',
  double volume = 0.5,
}) => Navigator.of(context).push<CustomBell>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => BellMakerView(from: from, volume: volume),
  ),
);

/// Makes a bell from the five controls, from any bell as a start, with the
/// bell's figure drawn from the controls as they move and the sound a tap
/// away. Nothing is kept until Save.
class BellMakerView extends ConsumerStatefulWidget {
  const BellMakerView({
    super.key,
    this.from = '',
    this.volume = 0.5,
    this.render,
    this.previewFile,
  });

  /// A cue sound to start from; anything else starts from the singing bowl.
  final String from;

  /// How loudly the preview rings: the cue's own bell volume.
  final double volume;

  /// Makes the sound (off the UI thread). Tests swap in something faster.
  final Future<Uint8List> Function(BellSpec spec)? render;

  /// Where the preview is written for the player to open.
  final Future<File> Function()? previewFile;

  @override
  ConsumerState<BellMakerView> createState() => _BellMakerViewState();
}

class _BellMakerViewState extends ConsumerState<BellMakerView> {
  late String _preset;
  late BellKnobs _knobs;
  late final TextEditingController _name;
  late final SessionBellPreview _preview;
  final _strike = ValueNotifier<int>(0);
  var _making = false;
  var _saving = false;
  var _generation = 0;
  String? _renderedKey;
  Uint8List? _rendered;

  @override
  void initState() {
    super.initState();
    _preview = ref.read(sessionBellPreviewProvider);
    final start = _startingPoint(widget.from);
    _preset = start.$1;
    _knobs = start.$2;
    _name = TextEditingController(
      text: ref.read(customBellStoreProvider).suggestName(),
    );
  }

  @override
  void dispose() {
    _generation++;
    // Nothing keeps ringing once the maker is closed.
    unawaited(_preview.stop());
    _name.dispose();
    _strike.dispose();
    super.dispose();
  }

  /// The preset and controls of the bell a cue rings now.
  (String, BellKnobs) _startingPoint(String sound) {
    final made = isCustomBellId(sound)
        ? ref.read(customBellStoreProvider).find(sound)
        : null;
    if (made != null) return (made.preset, made.knobs);
    final shipped = BellFigure.byAsset(sound)?.preset ?? 'bowl_medium';
    return (shipped, bellRecipes[shipped]!.knobs);
  }

  BellSpec get _spec => BellSpec(_preset, _knobs);

  void _startFrom(String preset) {
    setState(() {
      _preset = preset;
      _knobs = bellRecipes[preset]!.knobs;
    });
    unawaited(_hear());
  }

  void _move(String name, double value) => setState(() {
    final k = _knobs;
    _knobs = BellSpec.clampKnobs(switch (name) {
      'pitch' => k.copyWith(pitch: value),
      'bright' => k.copyWith(bright: value),
      'ring' => k.copyWith(ring: value),
      'strike' => k.copyWith(strike: value),
      _ => k.copyWith(shimmer: value),
    });
  });

  /// Makes the sound for the controls as they are, unless it is already made.
  Future<Uint8List?> _sound() async {
    final spec = _spec;
    if (_renderedKey == spec.key && _rendered != null) return _rendered;
    final generation = ++_generation;
    setState(() => _making = true);
    try {
      final wav = await (widget.render ?? renderBellWavInBackground)(spec);
      // The controls moved on while it was made: that sound is not wanted.
      if (!mounted || generation != _generation) return null;
      _renderedKey = spec.key;
      _rendered = wav;
      return wav;
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _making = false);
      }
    }
  }

  Future<void> _hear() async {
    try {
      final wav = await _sound();
      if (wav == null || !mounted) return;
      final file = await (widget.previewFile ?? _previewFile)();
      await file.parent.create(recursive: true);
      await file.writeAsBytes(wav, flush: true);
      if (!mounted) return;
      _strike.value++;
      await _preview.playFile(file.path, widget.volume);
    } catch (e) {
      AppLogger.e('BELLS', 'Bell preview failed', e);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            l10n?.bellMakerPlayFailed ?? 'The bell could not be played.',
          ),
        ),
      );
    }
  }

  static Future<File> _previewFile() async =>
      File('${(await getTemporaryDirectory()).path}/bell_maker/preview.wav');

  bool get _canSave =>
      !_saving &&
      cleanBellName(_name.text) != null &&
      ref.read(customBellsProvider).length < CustomBellStore.maxBells;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    try {
      final spec = _spec;
      // The sound heard is the sound kept: it is made once.
      final wav = await _sound() ?? await _render(spec);
      final bell = await ref
          .read(customBellsProvider.notifier)
          .save(name: _name.text, spec: spec, wav: wav);
      if (mounted) navigator.pop(bell);
    } catch (e) {
      AppLogger.e('BELLS', 'Bell could not be saved', e);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            l10n?.bellMakerSaveFailed ?? 'The bell could not be saved.',
          ),
        ),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Uint8List> _render(BellSpec spec) =>
      (widget.render ?? renderBellWavInBackground)(spec);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final full =
        ref.watch(customBellsProvider).length >= CustomBellStore.maxBells;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l10n?.bellMakerTitle ?? 'Make a bell'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ListenableBuilder(
              listenable: _name,
              builder: (context, _) => FilledButton(
                key: const ValueKey('bell_maker_save'),
                onPressed: _canSave ? _save : null,
                child: Text(l10n?.bellMakerSave ?? 'Save'),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _Figure(
              spec: _spec,
              strike: _strike,
              making: _making,
              onTap: _hear,
              label: l10n?.bellMakerHear ?? 'Hear it',
              makingLabel: l10n?.bellMakerMaking ?? 'Making the sound',
            ),
            const SizedBox(height: 16),
            _Label(l10n?.bellMakerStartFrom ?? 'Start from'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in BellFigure.shipped)
                  ChoiceChip(
                    key: ValueKey('bell_maker_start_${b.preset}'),
                    label: Text(b.title),
                    selected: b.preset == _preset,
                    onSelected: (_) => _startFrom(b.preset),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            for (final c in _controls(l10n))
              _Control(
                spec: c,
                value: _knobs[c.name],
                onChanged: (v) => _move(c.name, v),
                onChangeEnd: (_) => _hear(),
              ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('bell_maker_name'),
              controller: _name,
              maxLength: maxCustomBellNameLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n?.bellMakerName ?? 'Name',
                border: OutlineInputBorder(
                  borderRadius: MeditejoShapes.radius(MeditejoShapes.large),
                ),
              ),
            ),
            if (full)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n?.bellMakerLimit(CustomBellStore.maxBells) ??
                      'You can keep up to ${CustomBellStore.maxBells} bells. '
                          'Delete one to make another.',
                  style: type.baseline.bodyMedium?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_ControlSpec> _controls(AppLocalizations? l10n) => [
    _ControlSpec(
      'pitch',
      l10n?.bellPitch ?? 'Pitch',
      l10n?.bellPitchLow ?? 'Deep',
      l10n?.bellPitchHigh ?? 'High',
      (v) => '${v.round()} Hz',
    ),
    _ControlSpec(
      'bright',
      l10n?.bellBright ?? 'Brightness',
      l10n?.bellBrightLow ?? 'Dark',
      l10n?.bellBrightHigh ?? 'Bright',
      (v) => '${(v * 100).round()}%',
    ),
    _ControlSpec(
      'ring',
      l10n?.bellRing ?? 'Ring',
      l10n?.bellRingLow ?? 'Short',
      l10n?.bellRingHigh ?? 'Long',
      (v) => v < 1 ? '${(v * 1000).round()} ms' : '${v.toStringAsFixed(1)} s',
    ),
    _ControlSpec(
      'strike',
      l10n?.bellStrike ?? 'Strike',
      l10n?.bellStrikeLow ?? 'Soft',
      l10n?.bellStrikeHigh ?? 'Hard',
      (v) => '${(v * 100).round()}%',
    ),
    _ControlSpec(
      'shimmer',
      l10n?.bellShimmer ?? 'Shimmer',
      l10n?.bellShimmerLow ?? 'Still',
      l10n?.bellShimmerHigh ?? 'Wobbling',
      (v) => '${v.toStringAsFixed(1)} Hz',
    ),
  ];
}

class _ControlSpec {
  const _ControlSpec(this.name, this.label, this.low, this.high, this.format);

  final String name, label, low, high;
  final String Function(double) format;
}

/// A control as a slider: 0..1 along the control's own scale (`KNOBS`,
/// logarithmic for pitch and ring).
class _Control extends StatelessWidget {
  const _Control({
    required this.spec,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final _ControlSpec spec;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  BellKnob get _range => BellFigure.knobs[spec.name]!;

  double _toSlider(double v) => _range.scale == 'log'
      ? math.log(v / _range.min) / math.log(_range.max / _range.min)
      : (v - _range.min) / (_range.max - _range.min);

  double _fromSlider(double t) => _range.scale == 'log'
      ? _range.min * math.pow(_range.max / _range.min, t)
      : _range.min + t * (_range.max - _range.min);

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
              Expanded(
                child: Text(spec.label, style: type.emphasized.titleSmall),
              ),
              Text(spec.format(value), style: muted),
            ],
          ),
          Semantics(
            label: spec.label,
            value: spec.format(value),
            child: Slider(
              key: ValueKey('bell_maker_${spec.name}'),
              value: _toSlider(value).clamp(0.0, 1.0),
              onChanged: (t) => onChanged(_fromSlider(t)),
              onChangeEnd: (t) => onChangeEnd(_fromSlider(t)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(spec.low, style: muted),
                Text(spec.high, style: muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: context.typography.baseline.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// The bell, drawn from its controls. Tapping it rings it.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.spec,
    required this.strike,
    required this.making,
    required this.onTap,
    required this.label,
    required this.makingLabel,
  });

  final BellSpec spec;
  final ValueNotifier<int> strike;
  final bool making;
  final VoidCallback onTap;
  final String label, makingLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: making ? makingLabel : label,
      excludeSemantics: true,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: MeditejoShapes.radius(MeditejoShapes.extraLarge),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: InkWell(
            key: const ValueKey('bell_maker_figure'),
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ArtCover(
                  subject: ArtSubject.customBell(
                    'maker:${spec.preset}',
                    spec.preset,
                    spec.knobs,
                  ),
                  strike: strike,
                  holdWhileChanging: true,
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.85,
                      ),
                      shape: const StadiumBorder(),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: making
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.play_arrow_rounded,
                              color: scheme.onSurface,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
