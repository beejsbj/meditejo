import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/audio_download_widget.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/audio_speed_widget.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/bg_sound_widget.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/views/soundscape/sounds_view.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/speed_sheet.dart';

import 'bottom_action_bar.dart';

class PlayerActionBar extends StatelessWidget {
  const PlayerActionBar({
    super.key,
    required this.request,
    required this.isBackgroundSoundSelected,
    required this.onSpeedChanged,
    required this.onClosePressed,
  });

  final bool isBackgroundSoundSelected;
  final PlaybackRequest request;
  final Function(double) onSpeedChanged;
  final VoidCallback onClosePressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // A timer is local silence: nothing to download, and speed would only
    // change how long the session takes. Keep close, Sounds and Customize.
    if (request.isTimer) {
      return BottomActionBar(
        leftItem: BottomActionBarItem(
          child: const Icon(Icons.close, color: ColorConstants.white),
          onTap: onClosePressed,
          semanticLabel: l10n.close,
        ),
        rightCenterItem: BottomActionBarItem(
          child: _buildBackgroundSoundWidget(),
          onTap: () => openSoundsPage(context),
          semanticLabel: l10n.backgroundSounds,
        ),
        rightItem: BottomActionBarItem(
          child: _customizeIcon,
          onTap: () => _customize(context),
          semanticLabel: _customizeLabel,
        ),
      );
    }

    return BottomActionBar(
      layout: BottomActionBarLayout.edgeAligned,
      leftItem: BottomActionBarItem(
        child: const Icon(Icons.close, color: ColorConstants.white),
        onTap: onClosePressed,
        semanticLabel: l10n.close,
      ),
      leftCenterItem: BottomActionBarItem.custom(
        // A file imported into the app is already on the device; there is
        // nothing to download.
        child: request.remoteUrl.startsWith('http')
            ? AudioDownloadWidget(request: request)
            : const SizedBox(width: 48, height: 48),
      ),
      // Open for every session: the Sounds mixer can play under a talk too
      // (its Talks default or a Customize choice), so it must be reachable
      // here to adjust or stop it.
      centerItem: BottomActionBarItem(
        child: _buildBackgroundSoundWidget(),
        onTap: () => openSoundsPage(context),
        semanticLabel: l10n.backgroundSounds,
      ),
      rightCenterItem: BottomActionBarItem(
        child: _customizeIcon,
        onTap: () => _customize(context),
        semanticLabel: _customizeLabel,
      ),
      rightItem: BottomActionBarItem(
        child: const AudioSpeedWidget(),
        onTap: () => showSpeedSheet(
          context,
          onSpeedChanged: (speed) {
            onSpeedChanged(speed);
          },
        ),
        semanticLabel: l10n.playbackSpeed,
      ),
    );
  }

  Widget _buildBackgroundSoundWidget() =>
      BgSoundWidget(isBackgroundSoundSelected: isBackgroundSoundSelected);

  static const _customizeLabel = 'Customize';
  static const _customizeIcon = Icon(
    Icons.tune_rounded,
    color: ColorConstants.white,
  );

  void _customize(BuildContext context) {
    unawaited(showCustomizeSheet(context, request: request));
  }
}
