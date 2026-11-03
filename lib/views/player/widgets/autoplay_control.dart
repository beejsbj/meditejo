import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';

/// The pauses a listener can put between a course's sessions, in seconds
/// (what [CueSettings] stores).
const autoplayPauses = [0, 5, 10, 30];

/// Autoplay for a session played in a course: whether the course's next
/// session starts by itself when this one ends. It is about the queue, so it
/// lives in the player rather than in Customize (#72). It is stored with the
/// session's cue settings, where a course override carries it and the native
/// side reads the pause it holds.
class AutoplayButton extends ConsumerWidget {
  const AutoplayButton({super.key, required this.scope, this.trackId});

  /// The playing session's scope; it names its course.
  final CueScope scope;

  /// The playing session, for the "Up next" line.
  final String? trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final on = ref.watch(cueSettingsProvider(scope).select((s) => s.autoplay));
    // The same rounded highlight as the repeat and speed buttons when on.
    return TextButton.icon(
      key: const ValueKey('player_autoplay'),
      onPressed: () =>
          unawaited(showAutoplaySheet(context, scope: scope, trackId: trackId)),
      style: TextButton.styleFrom(
        foregroundColor: ColorConstants.white,
        backgroundColor: on
            ? ColorConstants.graphite.withAlpha(200)
            : Colors.transparent,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      icon: Icon(
        on ? Icons.playlist_play_rounded : Icons.playlist_remove_rounded,
      ),
      label: Text(on ? l10n.playerAutoplayOn : l10n.playerAutoplayOff),
    );
  }
}

Future<void> showAutoplaySheet(
  BuildContext context, {
  required CueScope scope,
  String? trackId,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
  builder: (_) => AutoplaySheet(scope: scope, trackId: trackId),
);

/// Autoplay on or off, the pause before the next session, and which session
/// that is.
class AutoplaySheet extends ConsumerWidget {
  const AutoplaySheet({super.key, required this.scope, this.trackId});

  final CueScope scope;
  final String? trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final s = ref.watch(cueSettingsProvider(scope));
    // Saved where Customize saves for this session: the course's own
    // settings when it has them, else its kind's.
    void edit(CueSettings value) => unawaited(
      ref
          .read(cueSettingsProvider(scope).notifier)
          .update(
            value,
            courseOverride: ref
                .read(cueSettingsStoreProvider)
                .hasOverride(scope),
          ),
    );
    final next = _upNext(ref, l10n);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.playerAutoplay,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
            if (next != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Text(
                  next,
                  key: const ValueKey('autoplay_up_next'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const ValueKey('autoplay_switch'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: Text(l10n.playerAutoplaySwitch),
              value: s.autoplay,
              onChanged: (v) => edit(s.copyWith(autoplay: v)),
            ),
            if (s.autoplay) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Text(
                  l10n.playerAutoplayPause,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final seconds in autoplayPauses)
                      ChoiceChip(
                        key: ValueKey('autoplay_pause_$seconds'),
                        label: Text(
                          seconds == 0
                              ? l10n.playerAutoplayNoPause
                              : l10n.playerAutoplaySeconds(seconds),
                        ),
                        selected: s.interludeSeconds == seconds,
                        onSelected: (_) =>
                            edit(s.copyWith(interludeSeconds: seconds)),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// "Up next: …" from the course as its page lists it, once it is loaded;
  /// nothing while it loads or when it cannot be read.
  String? _upNext(WidgetRef ref, AppLocalizations l10n) {
    final courseId = scope.courseId;
    final id = trackId;
    if (courseId == null || id == null) return null;
    final pack = ref.watch(packDataProvider(packId: courseId)).value;
    if (pack == null) return null;
    final items = pack.playableTracks;
    final index = items.indexWhere((item) => item.id == id);
    if (index < 0) return null;
    return index + 1 < items.length
        ? l10n.playerAutoplayUpNext(items[index + 1].title)
        : l10n.playerAutoplayLast;
  }
}
