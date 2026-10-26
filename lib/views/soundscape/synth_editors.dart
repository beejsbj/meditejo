import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';

/// Opens the editor for a generated layer in the mix.
Future<void> showSynthEditor(BuildContext context, String id) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      // Scrolls in landscape or at large text sizes. It only takes drags
      // when the editor overflows, so the vertical band sliders are not
      // contested otherwise.
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + padding16,
        ),
        child: switch (id) {
          kSynthNoiseId => const NoiseEditor(),
          kSynthDroneId => const DroneEditor(),
          _ => const BinauralEditor(),
        },
      ),
    );

/// Commits on release (onChangeEnd): every commit regenerates or retunes
/// the layer, so a drag shows its value live and applies once.
mixin _LayerParams<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String get layerId;

  Map<String, Object?> get current =>
      ref.read(soundscapeProvider).mix.layer(layerId)?.params ??
      defaultSynthParams(layerId);

  void commit(Map<String, Object?> params) =>
      ref.read(soundscapeProvider.notifier).setLayerParams(layerId, params);
}

Widget _heading(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(padding16, padding16, padding16, 6),
  child: Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
  ),
);

class NoiseEditor extends ConsumerStatefulWidget {
  const NoiseEditor({super.key});

  @override
  ConsumerState<NoiseEditor> createState() => _NoiseEditorState();
}

class _NoiseEditorState extends ConsumerState<NoiseEditor>
    with _LayerParams<NoiseEditor> {
  @override
  String get layerId => kSynthNoiseId;

  late NoiseParams _params = NoiseParams.fromJson(current);

  void _set(NoiseParams p, {bool apply = true}) {
    setState(() => _params = p);
    if (apply) commit(p.toJson());
  }

  static String _label(double hz) =>
      hz >= 1000 ? '${(hz / 1000).round()}k' : '${hz.round()}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, l10n.noiseColour),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: padding16),
          child: SegmentedButton<NoiseColour>(
            key: const ValueKey('noise_colour'),
            segments: [
              ButtonSegment(
                value: NoiseColour.white,
                label: Text(l10n.noiseWhite),
              ),
              ButtonSegment(
                value: NoiseColour.pink,
                label: Text(l10n.noisePink),
              ),
              ButtonSegment(
                value: NoiseColour.brown,
                label: Text(l10n.noiseBrown),
              ),
            ],
            selected: {_params.colour},
            onSelectionChanged: (s) => _set(_params.copyWith(colour: s.first)),
          ),
        ),
        Row(
          children: [
            Expanded(child: _heading(context, l10n.noiseBands)),
            Padding(
              padding: const EdgeInsets.only(right: padding8, top: padding8),
              child: TextButton(
                key: const ValueKey('noise_reset'),
                onPressed: () =>
                    _set(_params.copyWith(bands: NoiseParams.flat)),
                child: Text(l10n.noiseReset),
              ),
            ),
          ],
        ),
        SizedBox(
          height: 200,
          child: Row(
            children: [
              for (var i = 0; i < NoiseParams.bandCentres.length; i++)
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            key: ValueKey('noise_band_$i'),
                            value: _params.bands[i],
                            activeColor: context.brandAccent,
                            semanticFormatterCallback: (v) =>
                                '${_label(NoiseParams.bandCentres[i])} Hz '
                                '${(v * 100).round()}%',
                            onChanged: (v) => _set(
                              _params.copyWith(
                                bands: [..._params.bands]..[i] = v,
                              ),
                              apply: false,
                            ),
                            onChangeEnd: (_) => commit(_params.toJson()),
                          ),
                        ),
                      ),
                      Text(
                        _label(NoiseParams.bandCentres[i]),
                        style: Theme.of(context).textTheme.labelSmall,
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

class DroneEditor extends ConsumerStatefulWidget {
  const DroneEditor({super.key});

  @override
  ConsumerState<DroneEditor> createState() => _DroneEditorState();
}

class _DroneEditorState extends ConsumerState<DroneEditor>
    with _LayerParams<DroneEditor> {
  @override
  String get layerId => kSynthDroneId;

  late DroneParams _params = DroneParams.fromJson(current);

  void _set(DroneParams p, {bool apply = true}) {
    setState(() => _params = p);
    if (apply) commit(p.toJson());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, l10n.droneRoot),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: padding16),
          child: Wrap(
            spacing: padding8,
            runSpacing: padding8,
            children: [
              for (final MapEntry(key: name, value: hz)
                  in DroneParams.roots.entries)
                ChoiceChip(
                  key: ValueKey('drone_root_$name'),
                  label: Text(name),
                  selected: (_params.rootHz - hz).abs() < 0.01,
                  onSelected: (_) => _set(_params.copyWith(rootHz: hz)),
                ),
            ],
          ),
        ),
        _heading(context, l10n.droneTimbre),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: padding16),
          child: SegmentedButton<DroneTimbre>(
            key: const ValueKey('drone_timbre'),
            segments: [
              ButtonSegment(
                value: DroneTimbre.pure,
                label: Text(l10n.dronePure),
              ),
              ButtonSegment(
                value: DroneTimbre.warm,
                label: Text(l10n.droneWarm),
              ),
              ButtonSegment(
                value: DroneTimbre.bright,
                label: Text(l10n.droneBright),
              ),
            ],
            selected: {_params.timbre},
            onSelectionChanged: (s) => _set(_params.copyWith(timbre: s.first)),
          ),
        ),
        _heading(context, l10n.droneMovement),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: padding8),
          child: Slider(
            key: const ValueKey('drone_movement'),
            value: _params.movement,
            activeColor: context.brandAccent,
            onChanged: (v) => _set(_params.copyWith(movement: v), apply: false),
            onChangeEnd: (_) => commit(_params.toJson()),
          ),
        ),
      ],
    );
  }
}

class BinauralEditor extends ConsumerStatefulWidget {
  const BinauralEditor({super.key});

  @override
  ConsumerState<BinauralEditor> createState() => _BinauralEditorState();
}

class _BinauralEditorState extends ConsumerState<BinauralEditor>
    with _LayerParams<BinauralEditor> {
  @override
  String get layerId => kSynthBinauralId;

  late BinauralParams _params = BinauralParams.fromJson(current);

  void _set(BinauralParams p) => setState(() => _params = p);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BinauralHeadphonesNote(),
        _heading(
          context,
          '${l10n.binauralCarrier} · ${_params.carrierHz.round()} Hz',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: padding8),
          child: Slider(
            key: const ValueKey('binaural_carrier'),
            min: BinauralParams.minCarrier,
            max: BinauralParams.maxCarrier,
            value: _params.carrierHz,
            activeColor: context.brandAccent,
            onChanged: (v) => _set(_params.copyWith(carrierHz: v)),
            onChangeEnd: (_) => commit(_params.toJson()),
          ),
        ),
        _heading(
          context,
          '${l10n.binauralBeat} · ${_params.beatHz.toStringAsFixed(1)} Hz '
          '(${_params.band})',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: padding8),
          child: Slider(
            key: const ValueKey('binaural_beat'),
            min: BinauralParams.minBeat,
            max: BinauralParams.maxBeat,
            value: _params.beatHz,
            activeColor: context.brandAccent,
            onChanged: (v) => _set(_params.copyWith(beatHz: v)),
            onChangeEnd: (_) => commit(_params.toJson()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: padding16),
          child: Text(
            'delta < 4 · theta 4–8 · alpha 8–13 · beta ≥ 13 Hz',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown wherever binaural beats are: they only work on headphones.
class BinauralHeadphonesNote extends StatelessWidget {
  const BinauralHeadphonesNote({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('binaural_headphones'),
      padding: const EdgeInsets.fromLTRB(padding16, 4, padding16, 4),
      child: Row(
        children: [
          Icon(Icons.headphones_rounded, size: 18, color: context.brandAccent),
          const SizedBox(width: padding8),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.binauralHeadphones,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
