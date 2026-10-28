import 'package:flutter/material.dart';
import 'package:medito/l10n/app_localizations.dart';

/// Shown while the voice rests in one of its own pauses: how long is left,
/// and a way to carry on now.
class RestCard extends StatelessWidget {
  const RestCard({super.key, required this.secondsLeft, required this.onSkip});

  final int secondsLeft;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final time =
        '${secondsLeft ~/ 60}:${(secondsLeft % 60).toString().padLeft(2, '0')}';
    return Semantics(
      container: true,
      liveRegion: false,
      child: Material(
        key: const ValueKey('rest_card'),
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n?.extendHoldTitle ?? 'Resting in silence',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    Text(
                      l10n?.extendHoldLeft(time) ?? '$time left',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const ValueKey('skip_pause'),
                onPressed: onSkip,
                child: Text(l10n?.extendSkipPause ?? 'Skip this pause'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
