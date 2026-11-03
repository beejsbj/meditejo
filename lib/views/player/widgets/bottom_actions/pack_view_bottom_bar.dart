import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/views/pack/widgets/pack_path_button.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../widgets/medito_icon.dart';

/// The course page's bottom bar: Back, and nothing else while the header is
/// in view. The course's actions live in its header (#81). Once the header's
/// Play has scrolled away, [showPlay] brings a one-line copy of it here, so
/// the next session stays a thumb's reach away in a long course.
class PackViewBottomBar extends ConsumerWidget {
  const PackViewBottomBar({
    super.key,
    required this.packId,
    required this.onBackPressed,
    this.showPlay = false,
  });

  final String packId;
  final VoidCallback onBackPressed;
  final bool showPlay;

  static const _fade = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pack = ref.watch(packProvider(packId: packId)).value;
    final play = showPlay && pack != null && PackPlayButton.isPlayable(pack);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            IconButton(
              onPressed: onBackPressed,
              tooltip: l10n.goBack,
              icon: MeditoIcon(
                assetName: MeditoIcons.arrowLeft,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                // The bar is as tall as its row, not the screen.
                heightFactor: 1,
                child: AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : _fade,
                  child: play
                      ? PackPlayButton(
                          key: const ValueKey('bar_play'),
                          pack: pack,
                          compact: true,
                        )
                      // Holds the bar's height, so it does not jump.
                      : const SizedBox(height: 48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
