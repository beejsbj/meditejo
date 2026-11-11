import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/home/next_session.dart';
import 'package:medito/utils/episode_title.dart';
import 'package:medito/views/player/start_session.dart';
import 'package:medito/widgets/play_bar.dart';

typedef StartSessionFn =
    Future<void> Function(
      BuildContext context,
      WidgetRef ref, {
      required String trackId,
      required String path,
      String? courseId,
    });

/// The course's one Play: the page's bottom bar ([PlayBar]). It plays the
/// next session ([nextSessionFor]) and names it in small text beside the
/// icon. The icon says which: a play disc to start, the disc inside a ring
/// of the sessions played to resume, a quiet replay inside a closed ring for
/// a finished course (played again from its first session). The words
/// "Start", "Resume" and "Play again" are the screen reader's label and the
/// tooltip. Home's Continue follows what the user plays; pinning a course is
/// a separate, deliberate action.
class PackPlayButton extends ConsumerStatefulWidget {
  const PackPlayButton({
    super.key,
    required this.pack,
    this.onStartSession = startSession,
    this.maxWidth = 600,
  });

  final PackModel pack;
  final StartSessionFn onStartSession;

  /// The page body's width on a wide screen ([PlayBar.maxWidth]).
  final double maxWidth;

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
    final replay = ready && next == null;
    // The ring is the sessions played. A session left partway in a course
    // with none finished still shows a sliver, so it reads as a resume.
    final progress = ready && next != null && next.isResume && tracks.isNotEmpty
        ? math.max(completed / tracks.length, 0.06)
        : null;
    final onTap = session == null ? null : () => _start(context, session!);
    return PlayBar(
      label: label,
      tooltip: session == null ? action : '$action: ${session.title}',
      // The session's own name, without what every session of the course
      // repeats, so the short line says the most.
      caption: session == null
          ? null
          : episodeTitle(
              session.title,
              courseTitle: pack.title,
              teacher: session.teacher ?? pack.teacher?.name,
              siblings: [for (final item in tracks) item.title],
            ),
      progress: progress,
      replay: replay,
      busy: _starting,
      onTap: onTap,
      maxWidth: widget.maxWidth,
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
