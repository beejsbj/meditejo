import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';

import 'sound_control_spec.dart';
import 'sound_controls.dart';

/// Opens the editor for a generated layer in the mix: its controls, as its
/// spec lists them (#71).
Future<void> showSynthEditor(BuildContext context, String id) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      // Scrolls in landscape or at large text sizes. It only takes drags
      // when the editor overflows, so the vertical band sliders and the
      // wheel are not contested otherwise.
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + padding16,
        ),
        child: SoundEditor(id: id),
      ),
    );

/// A sound's controls, built from [soundControlSpec]. A range shows its
/// value as it is dragged and applies it once, on release; chips and the
/// wheel apply at once (the wheel when it comes to rest): every commit
/// regenerates or retunes the layer.
class SoundEditor extends ConsumerStatefulWidget {
  const SoundEditor({super.key, required this.id, this.spec});

  final String id;

  /// The controls; by default the sound's own.
  final SoundControlSpec? spec;

  @override
  ConsumerState<SoundEditor> createState() => _SoundEditorState();
}

class _SoundEditorState extends ConsumerState<SoundEditor> {
  late SoundParams _params =
      ref.read(soundscapeProvider).mix.layer(widget.id)?.params ??
      defaultSynthParams(widget.id);

  void _changed(SoundParams next, {bool live = false}) {
    setState(() => _params = next);
    if (!live) {
      ref.read(soundscapeProvider.notifier).setLayerParams(widget.id, next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec ?? soundControlSpec(widget.id);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (spec.headphones) const BinauralHeadphonesNote(),
        for (final control in spec.adjust)
          SoundControlView(
            control: control,
            params: _params,
            onChanged: _changed,
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
