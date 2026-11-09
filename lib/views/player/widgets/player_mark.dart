import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/theme/palette_theme.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/services/identity/mark_moments.dart';
import 'package:medito/widgets/branding/mark_painter.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';

/// The day's mark (or the pinned one) above a timer session's controls, in
/// place of art (#86). It breathes at the session's pulse rate, else six
/// breaths a minute, while [isPlaying]; paused, covered or in the background
/// it holds, and with reduced motion it is the settled mark. Decorative, so
/// it is left out of the semantics tree.
class PlayerMark extends ConsumerWidget {
  const PlayerMark({super.key, required this.isPlaying, required this.size});

  final bool isPlaying;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A timer is always a practice session with no course.
    final cues = ref.watch(
      cueSettingsProvider(const CueScope(CueKind.practice)),
    );
    final period = PlayerBreath.periodSeconds(
      cues,
      reducedMotion: MediaQuery.disableAnimationsOf(context),
    );
    // The player's backdrop is always dark, whatever the theme.
    final colors = MarkColors.onBackground(
      MeditejoPalette.of(context).palette,
      background: ColorConstants.onyx,
      text: ColorConstants.white,
    );
    return MeditejoMark(
      key: const ValueKey('player_mark'),
      mark: ref.watch(homeMarkProvider),
      size: size,
      colors: colors,
      breathSeconds: period,
      paused: !isPlaying,
    );
  }
}
