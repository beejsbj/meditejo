import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/views/home/home_styles.dart';
import 'package:medito/views/home/widgets/pinned/pinned_list_view.dart';
import 'package:medito/views/player/start_session.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/cards/card_actions.dart';
import 'package:medito/widgets/snackbar_widget.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/network_image_widget.dart';

/// The first three things the user pinned, courses with where they are in
/// them and sessions with what they are, then "See all" when there are more.
/// Hidden when nothing is pinned.
class PinnedSection extends ConsumerWidget {
  const PinnedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(pinnedCoursesProvider);
    if (ids.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final shown = ids.take(PinnedCoursesNotifier.homeLimit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(l10n.homePinnedTitle),
        for (final (i, id) in shown.indexed)
          Padding(
            padding: EdgeInsets.fromLTRB(
              kHomeGutter,
              i == 0 ? 0 : kHomeRowGap,
              kHomeGutter,
              0,
            ),
            child: PinnedTile(id: id),
          ),
        if (ids.length > PinnedCoursesNotifier.homeLimit)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kHomeGutter,
              kHomeGap / 4,
              kHomeGutter - 8,
              0,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('pinned_see_all'),
                onPressed: () => openPinnedList(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.pinnedSeeAll(ids.length)),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A pin as its card: a course's or a session's, by what was pinned.
class PinnedTile extends ConsumerWidget {
  const PinnedTile({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(pinnedCoursesProvider);
    final session = ref.read(pinnedCoursesProvider.notifier).isSession(id);
    return session
        ? PinnedSessionTile(key: ValueKey('pinned_$id'), id: id)
        : PinnedCourseTile(key: ValueKey('pinned_$id'), id: id);
  }
}

class PinnedCourseTile extends ConsumerWidget {
  const PinnedCourseTile({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(packProvider(packId: id));
    final pack = state.value;
    final entries = ref.watch(libraryEntriesProvider).value;
    final entry = entries?.where((e) => e.sourceId == id).firstOrNull;
    final l10n = AppLocalizations.of(context)!;
    // Its source no longer has it: say so rather than show an ID.
    final gone = pack == null && state.hasError;
    final saved = ref.read(pinnedCoursesProvider.notifier).savedTitle(id);
    final title =
        entry?.displayTitle ??
        pack?.title ??
        saved ??
        (gone ? l10n.pinnedUnavailable : '');
    final theme = Theme.of(context);
    // As the course page counts: a session its source has lost is not one.
    final playable = pack?.playableTracks ?? const [];
    final total = playable.length;
    final done = playable.where((i) => i.isCompleted == true).length;

    final scheme = theme.colorScheme;
    final type = context.typography;
    void open() => handleNavigation(
      TypeConstants.pack,
      [id, '/packs/$id'],
      context,
      ref: ref,
    );

    // The first session not done, else the first there is.
    final next =
        playable.where((i) => i.isCompleted != true).firstOrNull ??
        playable.firstOrNull;

    return _PinnedCard(
      id: id,
      title: title,
      art: courseArt(id),
      coverUrl: pack?.coverUrl ?? '',
      onOpen: open,
      openIcon: Icons.menu_book_outlined,
      onPlay: next == null
          ? null
          : () => startSession(
              context,
              ref,
              trackId: next.id,
              path: next.path,
              courseId: id,
            ),
      below: gone && title != l10n.pinnedUnavailable
          ? _Unavailable(l10n.pinnedUnavailable)
          : total > 0
          ? Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: done / total,
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.upNextProgress(done, total),
                  style: type.baseline.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

/// A single session pinned to Home: its art, title and what it is. Tapping
/// opens it; its menu also plays it.
class PinnedSessionTile extends ConsumerWidget {
  const PinnedSessionTile({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(tracksProvider(trackId: id));
    final entries = ref.watch(libraryEntriesProvider).value;
    final entry = entries?.where((e) => e.sourceId == id).firstOrNull;
    final l10n = AppLocalizations.of(context)!;
    // Its source no longer has it: say so rather than show an ID. While it
    // loads the card stays blank.
    final gone = !track.hasValue && track.hasError;
    final saved = ref.read(pinnedCoursesProvider.notifier).savedTitle(id);
    final title =
        entry?.displayTitle ??
        track.value?.title ??
        saved ??
        (gone ? l10n.pinnedUnavailable : '');
    final detail = gone
        ? (title == l10n.pinnedUnavailable ? '' : l10n.pinnedUnavailable)
        : (track.value?.subtitle ?? entry?.subtitle ?? '').trim();
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;

    return _PinnedCard(
      id: id,
      title: title,
      art: singleArt(id),
      coverUrl: track.value?.coverUrl ?? entry?.coverUrl ?? '',
      onOpen: () =>
          handleNavigation(TypeConstants.track, [id], context, ref: ref),
      openIcon: Icons.info_outline_rounded,
      // Nothing to play until it loads, and nothing once it is gone.
      onPlay: track.hasValue
          ? () => startSession(context, ref, trackId: id, path: '/tracks/$id')
          : null,
      below: detail.isEmpty
          ? null
          : Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: type.baseline.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
    );
  }
}

/// The line under a pin whose content is gone.
class _Unavailable extends StatelessWidget {
  const _Unavailable(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: context.typography.baseline.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// The card both kinds of pin share: art, title, a line below, and a menu
/// (Open, Play, Unpin) on its ⋮ and on a long press.
class _PinnedCard extends ConsumerWidget {
  const _PinnedCard({
    required this.id,
    required this.title,
    required this.art,
    required this.coverUrl,
    required this.onOpen,
    required this.openIcon,
    required this.onPlay,
    required this.below,
  });

  final String id;
  final String title;
  final ArtSubject art;
  final String coverUrl;
  final VoidCallback onOpen;
  final IconData openIcon;
  final VoidCallback? onPlay;
  final Widget? below;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    // Even an unavailable pin keeps an Unpin control, so stale pins do not
    // stay forever.
    void unpin() {
      // The card goes as soon as the pin does, so the snackbar and Undo are
      // set up before anything is waited on.
      final pins = ref.read(pinnedCoursesProvider.notifier);
      final before = ref.read(pinnedCoursesProvider);
      final session = pins.isSession(id);
      pins.unpin(id);
      showSnackBar(
        context,
        l10n.homeUnpinned,
        actionLabel: l10n.undo,
        onActionPressed: () => pins.pinBack(id, before, session: session),
      );
    }

    final actions = [
      CardAction(
        key: const ValueKey('pinned_menu_open'),
        icon: openIcon,
        label: l10n.libraryOpen,
        onSelected: onOpen,
      ),
      if (onPlay case final play?)
        CardAction(
          key: const ValueKey('pinned_menu_play'),
          icon: Icons.play_arrow_rounded,
          label: l10n.play,
          onSelected: play,
        ),
      CardAction(
        key: const ValueKey('pinned_menu_unpin'),
        icon: Icons.push_pin_outlined,
        label: l10n.unpinCourse,
        onSelected: unpin,
      ),
    ];

    return HomePressable(
      color: scheme.surfaceContainer,
      radius: kHomeCardRadius,
      onTap: onOpen,
      onLongPress: () =>
          showCardActions(context, title: title, actions: actions),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(kHomeArtRadius),
              child: SizedBox.square(
                dimension: 56,
                child: NetworkImageWidget(
                  url: coverUrl,
                  art: art,
                  shouldCache: true,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.typography.emphasized.titleMedium,
                  ),
                  if (below case final below?) ...[
                    const SizedBox(height: 6),
                    below,
                  ],
                ],
              ),
            ),
            CardMenuButton(title: title, actions: actions),
          ],
        ),
      ),
    );
  }
}
