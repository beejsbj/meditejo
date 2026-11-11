import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/providers/home/continue_dismissed_provider.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/views/home/home_styles.dart';
import 'package:medito/views/library/library_format.dart';
import 'package:medito/views/player/start_session.dart';
import 'package:medito/widgets/cards/card_actions.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/snackbar_widget.dart';
import 'package:medito/widgets/network_image_widget.dart';

/// What is in progress, up to three, each one tap from playing. With nothing
/// started it offers the next session of a pinned or starter course.
class ContinueSection extends ConsumerWidget {
  const ContinueSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final items = ref.watch(continueItemsProvider).value;
    if (items == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(l10n.upNextTitle),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kHomeGutter + 4),
            child: Text(
              l10n.homeContinueEmpty,
              key: const ValueKey('continue_empty'),
              style: context.typography.baseline.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final (i, item) in items.indexed)
            Padding(
              padding: EdgeInsets.fromLTRB(
                kHomeGutter,
                i == 0 ? 0 : kHomeRowGap,
                kHomeGutter,
                0,
              ),
              child: ContinueTile(item: item, lead: i == 0),
            ),
      ],
    );
  }
}

/// Plays [item] from where it stopped, or its course's next session. Home's
/// Continue and the Library's In progress both start this way.
Future<void> startContinueItem(
  BuildContext context,
  WidgetRef ref,
  ContinueItem item, {
  bool fromStart = false,
}) async {
  // The course Continue shows it under, for its cue scope and for where it
  // counts: startSession writes it before the session starts, which reads it.
  // An item with no course forgets the one it was last opened from.
  await startSession(
    context,
    ref,
    trackId: item.trackId,
    path: item.path,
    courseId: item.courseId,
    fromStart: fromStart,
  );
}

/// One thing in progress, as a card. The first ([lead]) is drawn on the
/// primary container: it is what Home most expects the user to want.
class ContinueTile extends ConsumerWidget {
  const ContinueTile({super.key, required this.item, this.lead = false});

  final ContinueItem item;
  final bool lead;

  /// The course, then where in it. Kept apart so a long course title cannot
  /// push "Session 4 of 32" off the card.
  List<String> _where(AppLocalizations l10n) => [
    if (item.sessionNumber != null && item.sessionTotal != null)
      l10n.homeContinueSessionOf(item.sessionNumber!, item.sessionTotal!),
    if (item.resume != null &&
        item.resume!.durationMs > item.resume!.positionMs)
      l10n.homeContinueTimeLeft(
        formatClock(item.resume!.durationMs - item.resume!.positionMs),
      ),
  ];

  List<CardAction> _actions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final courseId = item.courseId;
    return [
      if (courseId != null)
        CardAction(
          key: const ValueKey('continue_menu_open_course'),
          icon: Icons.menu_book_outlined,
          label: l10n.homeOpenCourse,
          onSelected: () => handleNavigation(
            TypeConstants.pack,
            [courseId, '/packs/$courseId'],
            context,
            ref: ref,
          ),
        ),
      // A course's next session has nothing to restart: it starts at the top.
      if (item.resume != null)
        CardAction(
          key: const ValueKey('continue_menu_restart'),
          icon: Icons.restart_alt_rounded,
          label: l10n.homeRestart,
          onSelected: () =>
              startContinueItem(context, ref, item, fromStart: true),
        ),
      CardAction(
        key: const ValueKey('continue_menu_remove'),
        icon: Icons.remove_circle_outline_rounded,
        label: l10n.homeRemoveFromContinue,
        onSelected: () {
          // Everything is read before the card goes: removing it unmounts
          // this tile.
          final dismissed = ref.read(continueDismissedProvider.notifier);
          final key = continueKeyOf(item);
          final before = ref.read(continueDismissedProvider)[key];
          dismissed.dismiss(key);
          showSnackBar(
            context,
            l10n.homeRemovedFromContinue,
            actionLabel: l10n.undo,
            onActionPressed: () => dismissed.restore(key, before),
          );
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final label = item.resume != null
        ? l10n.homeContinueResume
        : l10n.homeContinueStart;
    final parts = _where(l10n);
    final where = parts.join(' · ');
    final subtitle = [
      if (item.courseTitle.isNotEmpty) item.courseTitle,
      if (where.isNotEmpty) where,
    ].join(' · ');
    final actions = _actions(context, ref, l10n);
    Future<void> start() => startContinueItem(context, ref, item);
    void showActions() =>
        showCardActions(context, title: item.title, actions: actions);

    final scheme = theme.colorScheme;
    final type = context.typography;
    final fill = lead ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final onFill = lead ? scheme.onPrimaryContainer : scheme.onSurface;
    final muted = lead
        ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: '$label: ${item.title}. $subtitle',
      excludeSemantics: true,
      onTap: start,
      // A long-press opens the card's actions (there is no ⋮ on Home's
      // cards): said as a hint, and since the card hides its children from
      // screen readers the actions are offered on the card itself too.
      onLongPress: showActions,
      onLongPressHint: l10n.homeCardActionsHint,
      customSemanticsActions: {
        for (final a in actions)
          CustomSemanticsAction(label: a.label): a.onSelected,
      },
      child: HomePressable(
        key: ValueKey('continue_${item.trackId}'),
        color: fill,
        radius: kHomeCardRadius,
        onTap: start,
        onLongPress: showActions,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(kHomeArtRadius),
                child: SizedBox.square(
                  dimension: 64,
                  child: NetworkImageWidget(
                    url: item.coverUrl,
                    art: item.courseId != null
                        ? courseArt(item.courseId!)
                        : singleArt(item.trackId),
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
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: type.emphasized.titleMedium?.copyWith(
                        color: onFill,
                      ),
                    ),
                    if (item.courseTitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          item.courseTitle,
                          // One line: the text has the card's width now, and
                          // three cards should leave room for the mark.
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.baseline.bodyMedium?.copyWith(
                            color: muted,
                          ),
                        ),
                      ),
                    if (parts.isNotEmpty)
                      // Each part stays whole: it wraps between them.
                      Wrap(
                        key: ValueKey('continue_where_${item.trackId}'),
                        spacing: 4,
                        children: [
                          for (final (i, part) in parts.indexed)
                            Text(
                              i < parts.length - 1 ? '$part ·' : part,
                              style: type.baseline.bodyMedium?.copyWith(
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Play, alone at the right and centred on the card; the
              // card's other actions are a long-press away. A round button
              // with no word: the card says what it is, and "Resume"
              // (or "Start") is its tooltip and what a screen reader hears.
              // Every card has the same button; the first differs only by
              // the card's own colour.
              IconButton.filled(
                key: ValueKey('continue_play_${item.trackId}'),
                tooltip: label,
                style: IconButton.styleFrom(
                  backgroundColor: lead ? scheme.primary : scheme.secondary,
                  foregroundColor: lead ? scheme.onPrimary : scheme.onSecondary,
                ),
                onPressed: start,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
