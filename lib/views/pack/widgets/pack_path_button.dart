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

/// The course's one Play: a filled button that plays the next session
/// ([nextSessionFor]) and names it, "Resume: Second Jhāna". It leads the
/// header's action row; the bottom bar shows a [compact] copy once the header
/// has scrolled away (#81). Home's Continue follows what the user plays;
/// pinning a course is a separate, deliberate action.
class PackPlayButton extends ConsumerStatefulWidget {
  const PackPlayButton({
    super.key,
    required this.pack,
    this.compact = false,
    this.onStartSession = startSession,
  });

  final PackModel pack;

  /// One line ("Resume: Second Jhāna…") at the bottom bar's height, instead
  /// of the header's two (the action over the session's title).
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
  bool _starting = false;

  PackModel get pack => widget.pack;

  @override
  Widget build(BuildContext context) {
    final tracks = pack.playableTracks;
    final completed = tracks.where((item) => item.isCompleted == true).length;
    final places = ref.watch(partialPlacesProvider);
    final next = nextSessionFor(pack, partial: places.value ?? const {});
    // Until the places are read the answer could be the wrong session, so
    // the button waits (an error reads as no places).
    final ready = places.hasValue || places.hasError;
    return _playButton(context, next, completed, tracks.length, ready);
  }

  Widget _playButton(
    BuildContext context,
    NextSession? nextSession,
    int completed,
    int total,
    bool ready,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final next = nextSession?.item;
    final done = nextSession == null;
    // A session left partway also reads Resume, even in an unstarted course.
    final action = done
        ? l10n.yourPathAllDone
        : nextSession.isResume
        ? l10n.packContinue
        : l10n.packStart;
    final label = done
        ? action
        : '$action: ${next!.title}. ${l10n.upNextProgress(completed, total)}';
    final foreground = done ? onSurface : context.onBrandAccent;
    final height = widget.compact ? 48.0 : 56.0;

    final icon = _starting
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: foreground,
            ),
          )
        : Icon(
            done ? Icons.check_rounded : Icons.play_arrow_rounded,
            size: done ? 22 : 28,
            color: foreground,
          );

    final actionStyle = theme.textTheme.labelLarge?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w700,
      fontSize: 15,
    );
    final Widget text;
    if (done) {
      text = Text(action, maxLines: 1, style: actionStyle);
    } else if (widget.compact) {
      text = Text(
        '$action: ${next!.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: actionStyle,
      );
    } else {
      text = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(action, maxLines: 1, style: actionStyle),
          Text(
            next!.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: foreground.withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
              height: 1.25,
            ),
          ),
        ],
      );
    }

    return Semantics(
      button: !done,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: done ? action : '$action: ${next!.title}',
        excludeFromSemantics: true,
        child: Material(
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          color: done
              ? Color.alphaBlend(
                  onSurface.withValues(alpha: 0.08),
                  theme.cardColor,
                )
              : context.brandAccent,
          child: InkWell(
            onTap: done || !ready ? null : () => _start(context, next!),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(dimension: 26, child: Center(child: icon)),
                    const SizedBox(width: 6),
                    Flexible(child: text),
                  ],
                ),
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
