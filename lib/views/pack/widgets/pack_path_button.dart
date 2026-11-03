import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/colors/color_constants.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/home/next_session.dart';
import 'package:medito/views/player/start_session.dart';

typedef StartSessionFn =
    Future<void> Function(
      BuildContext context,
      WidgetRef ref, {
      required String trackId,
      required String path,
      String? courseId,
    });

/// The course's one Play: a full-width filled button that plays the next
/// session ([nextSessionFor]) and names it, "▶ Resume  Second Jhāna…". It
/// sits above the header's icon row; the bottom bar shows a [compact] copy
/// once the header has scrolled away (#81). A finished course offers Play
/// again, from its first session. Home's Continue follows what the user
/// plays; pinning a course is a separate, deliberate action.
class PackPlayButton extends ConsumerStatefulWidget {
  const PackPlayButton({
    super.key,
    required this.pack,
    this.compact = false,
    this.onStartSession = startSession,
  });

  final PackModel pack;

  /// The bottom bar's height (48) instead of the header's (56).
  final bool compact;
  final StartSessionFn onStartSession;

  /// Whether [pack] gets a Play at all: it has something to play and holds
  /// only sessions (a pack of packs is walked from its rows).
  static bool isPlayable(PackModel pack) {
    final tracks = pack.items.where((i) => i.type == TypeConstants.track);
    return pack.playableTracks.isNotEmpty && tracks.length == pack.items.length;
  }

  @override
  ConsumerState<PackPlayButton> createState() => _PackPlayButtonState();
}

class _PackPlayButtonState extends ConsumerState<PackPlayButton> {
  // The row's fixed parts, around the action word and the title.
  static const _padStart = 14.0;
  static const _padEnd = 20.0;
  static const _iconSize = 28.0;
  static const _iconGap = 8.0;
  static const _titleGap = 10.0;

  bool _starting = false;

  PackModel get pack => widget.pack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tracks = pack.playableTracks;
    final completed = tracks.where((item) => item.isCompleted == true).length;
    final places = ref.watch(partialPlacesProvider);
    // Until the places are read the answer could be the wrong session (and
    // Start where it is Resume), so the button names nothing and waits; an
    // error reads as no places.
    final ready = places.hasValue || places.hasError;
    final next = nextSessionFor(pack, partial: places.value ?? const {});
    final first = tracks.firstOrNull;

    final String action;
    final PackItemsModel? session;
    if (!ready) {
      action = l10n.play;
      session = null;
    } else if (next == null) {
      // Finished: start over from the first session.
      action = l10n.coursePlayAgain;
      session = first;
    } else {
      // A session left partway also reads Resume, even in an unstarted
      // course.
      action = next.isResume ? l10n.packContinue : l10n.packStart;
      session = next.item;
    }
    final label = session == null
        ? action
        : next == null
        ? '$action: ${session.title}'
        : '$action: ${session.title}. '
              '${l10n.upNextProgress(completed, tracks.length)}';
    return _button(
      context,
      action: action,
      title: session?.title,
      label: label,
      replay: ready && next == null,
      onTap: session == null ? null : () => _start(context, session!),
    );
  }

  Widget _button(
    BuildContext context, {
    required String action,
    required String? title,
    required String label,
    required bool replay,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final foreground = context.onBrandAccent;
    final icon = _starting
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: foreground,
            ),
          )
        : Icon(
            replay ? Icons.replay_rounded : Icons.play_arrow_rounded,
            size: replay ? 24 : 28,
            color: foreground,
          );
    final actionStyle = theme.textTheme.labelLarge?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w700,
      fontSize: 15,
    );
    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: foreground.withValues(alpha: 0.85),
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
    );

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: title == null ? action : '$action: $title',
        excludeFromSemantics: true,
        child: Material(
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          color: context.brandAccent,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: widget.compact ? 48 : 56),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // What the row needs besides the words: its padding, the
                  // icon and the gaps. The action word gets at most 75% of
                  // the width, and never more than is left after those.
                  final fixed =
                      _padStart +
                      _padEnd +
                      _iconSize +
                      _iconGap +
                      (title == null ? 0 : _titleGap);
                  final width = constraints.maxWidth;
                  final actionMax = width.isFinite
                      ? math.max(0.0, math.min(width * 0.75, width - fixed))
                      : double.infinity;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _padStart,
                      6,
                      _padEnd,
                      6,
                    ),
                    child: Row(
                      mainAxisSize: widget.compact
                          ? MainAxisSize.min
                          : MainAxisSize.max,
                      children: [
                        SizedBox.square(
                          dimension: _iconSize,
                          child: Center(child: icon),
                        ),
                        const SizedBox(width: _iconGap),
                        // The action word stays whole; only the title gives way.
                        // (Capped, so even a huge text scale ellipsizes rather
                        // than overflows.)
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: actionMax),
                          child: Text(
                            action,
                            key: const ValueKey('play_action'),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: actionStyle,
                          ),
                        ),
                        if (title != null) ...[
                          const SizedBox(width: _titleGap),
                          Flexible(
                            child: Text(
                              title,
                              key: const ValueKey('play_title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context, PackItemsModel next) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      // A session several courses list counts towards this one, and takes
      // its cue scope: startSession writes it before the session starts.
      await widget.onStartSession(
        context,
        ref,
        trackId: next.id,
        path: next.path,
        courseId: pack.id,
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }
}
