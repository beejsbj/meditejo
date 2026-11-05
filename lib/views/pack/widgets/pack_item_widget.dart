import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/meditation/downloaded_track_ids_provider.dart';
import 'package:medito/utils/utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:medito/views/pack/widgets/pack_complete_badge.dart';

class PackItemWidget extends ConsumerWidget {
  const PackItemWidget({
    super.key,
    required this.item,
    this.onSetComplete,
    this.badge,
    this.courseTeacher,
    this.courseTeacherId,
    this.courseByline,
    this.date,
  });

  final PackItemsModel item;

  /// Persists a track row's completion to an absolute value, returning whether
  /// the write succeeded (so the control can revert an optimistic flip).
  /// When null (e.g. pack rows, or a list outside a course) no completion
  /// control is shown; a finished session still shows its tick.
  final Future<bool> Function(bool complete)? onSetComplete;

  /// A small chip at the start of the meta line: the session's kind in a
  /// course that mixes kinds, or that its source lost it. Null for none.
  final String? badge;

  /// Who leads the course. The row leaves out a teacher who is the same, so
  /// a one-teacher retreat does not repeat the name on every session.
  final String? courseTeacher;

  /// The app ID of the course's teacher (`ds-teacher-96`,
  /// `yt-channel-…`). A session by the same ID is theirs even when its
  /// name is written differently (a channel's uploader string).
  final String? courseTeacherId;

  /// The name under the course's title, where it is a name (a podcast's
  /// author, a channel's uploader string); rows by it leave it out too.
  final String? courseByline;

  /// When the session was recorded, as the course page shows it ("Mar 5"),
  /// or null where the row does not say it (a retreat's day already does).
  final String? date;

  /// Whether the row has a meta line ("Ajahn Sucitto · Mar 5 · 42 min")
  /// rather than the plain subtitle of a pack without session details.
  bool get _detailed =>
      item.type == TypeConstants.track &&
      (item.kind != null ||
          item.teacher != null ||
          item.durationMs != null ||
          date != null ||
          badge != null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var hasSubtitle = item.subtitle.isNotNullAndNotEmpty();
    final detailed = _detailed;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Container(
            width: MediaQuery.of(context).size.width,
            padding: detailed
                ? const EdgeInsets.symmetric(vertical: 16)
                : EdgeInsets.only(top: hasSubtitle ? 24 : 20, bottom: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.title.isNotNullAndNotEmpty())
                        Text(item.title, style: textTheme.headlineMedium),
                      if (detailed)
                        _details(context)
                      else if (hasSubtitle)
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              item.subtitle ?? '',
                              style: textTheme.titleMedium,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (detailed && ref.watch(_isDownloaded(item.id)))
                  _downloadedMark(context),
                _getTrailing(context, ref),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The teacher when not the course's own, then the date and the length
  /// ("Sharon Salzberg · Apr 15 · 42 min"), after the [badge] if any.
  Widget _details(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final minutes = ((item.durationMs ?? 0) / Duration.millisecondsPerMinute)
        .round();
    final teacher = (item.teacher ?? '').trim();
    // A narrow row breaks the line between parts, never inside a name or
    // "42 min".
    final text = [
      if (teacher.isNotEmpty && !_byCourseTeacher(teacher)) teacher,
      ?date,
      if (minutes > 0) l10n.courseSessionLength(minutes),
    ].map((part) => part.replaceAll(' ', ' ')).join(' · ');
    final badge = this.badge;
    if (text.isEmpty && badge == null) return const SizedBox.shrink();
    final meta = Text(
      text,
      key: const ValueKey('session_meta'),
      style: Theme.of(context).textTheme.titleMedium,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: badge == null
          ? meta
          // The chip, then the line beside it, or under it when both do not
          // fit.
          : Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [_Badge(badge), if (text.isNotEmpty) meta],
            ),
    );
  }

  /// Whether the session's [teacher] leads the course: the same teacher ID
  /// first, else the same name as the course's teacher or byline.
  bool _byCourseTeacher(String teacher) {
    final id = item.teacherId;
    if (id != null && id.isNotEmpty && id == courseTeacherId) return true;
    return _sameName(teacher, courseTeacher) ||
        _sameName(teacher, courseByline);
  }

  static bool _sameName(String name, String? other) =>
      other != null && name.trim().toLowerCase() == other.trim().toLowerCase();

  Widget _downloadedMark(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Icon(
        Icons.download_done_rounded,
        size: 20,
        semanticLabel: l10n.courseSessionDownloaded,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _getTrailing(BuildContext context, WidgetRef ref) {
    if (item.type == TypeConstants.link) {
      // Tells link rows apart from sessions, which otherwise sound the same.
      return SvgPicture.asset(
        AssetConstants.icLink,
        semanticsLabel: AppLocalizations.of(context)!.externalLink,
      );
    }

    if (item.type == TypeConstants.track && onSetComplete != null) {
      return _CompletionToggle(
        isCompleted: item.isCompleted ?? false,
        onSetComplete: onSetComplete!,
      );
    }

    final played =
        item.isCompleted ??
        (item.type == TypeConstants.track &&
            ref.watch(playedTrackIdsProvider).contains(item.id));
    if ((item.type == TypeConstants.pack || item.type == TypeConstants.track) &&
        played) {
      // Same 48px slot and left gap as the track toggle, so ticks line up.
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Align(
            alignment: Alignment.centerRight,
            child: const PackCompleteBadge(),
          ),
        ),
      );
    }

    return const SizedBox();
  }
}

/// A session's kind, or that it is unavailable, as a small quiet chip.
class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          letterSpacing: 0.2,
          color: onSurface.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

final _isDownloaded = Provider.autoDispose.family<bool, String>(
  (ref, id) => ref.watch(downloadedTrackIdsProvider).contains(id),
);

/// Tappable completion indicator that replaces the old swipe-to-complete
/// gesture (which fought the Android system back gesture on the right edge).
/// The generous left/vertical padding both keeps a comfortable gap from the
/// title and gives the control a ~48px touch target.
///
/// The flip is optimistic — the icon changes the instant you tap, well ahead
/// of the local stats write behind it. Because a user can tap repeatedly, a single
/// converger loop runs at a time: extra taps just update the desired state,
/// and when the in-flight write finishes the loop persists again if the user
/// has since changed their mind. A failed write reverts to the real state.
class _CompletionToggle extends StatefulWidget {
  const _CompletionToggle({
    required this.isCompleted,
    required this.onSetComplete,
  });

  final bool isCompleted;
  final Future<bool> Function(bool complete) onSetComplete;

  @override
  State<_CompletionToggle> createState() => _CompletionToggleState();
}

class _CompletionToggleState extends State<_CompletionToggle> {
  /// What the checkbox currently shows. Seeded from the provider and then
  /// driven optimistically; resynced from the provider only while idle.
  late bool _shown;

  /// True while the converger loop owns persistence. Guards against starting a
  /// second loop and against stale provider rebuilds clobbering the optimism.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _shown = widget.isCompleted;
  }

  @override
  void didUpdateWidget(_CompletionToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt provider-driven changes only when we're not mid-write, so an
    // in-flight optimistic flip isn't overwritten by a stale rebuild.
    if (!_busy && widget.isCompleted != _shown) {
      _shown = widget.isCompleted;
    }
  }

  Future<void> _handleTap() async {
    setState(() => _shown = !_shown); // optimistic flip, instant
    if (_busy) return; // a converger is already running; it will pick this up
    _busy = true;
    try {
      while (true) {
        final target = _shown;
        final ok = await widget.onSetComplete(target);
        if (!ok) {
          // Persist failed — fall back to the real (provider) state.
          if (mounted) setState(() => _shown = widget.isCompleted);
          break;
        }
        // No further taps during the write → settled. Otherwise loop to
        // converge on the user's newest choice.
        if (!mounted || _shown == target) break;
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Semantics(
      button: true,
      checked: _shown,
      label: _shown ? l10n.markTrackIncomplete : l10n.markTrackComplete,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        // 48x48 hit area (platform minimum) with a left gap from the title.
        // The circle is right-aligned within it so it stays visually where it
        // was while the touch target extends left and vertically.
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 24,
                height: 24,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _shown ? context.brandAccent : Colors.transparent,
                    border: Border.all(
                      color: _shown
                          ? context.brandAccent
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  // Glyph in the accent's own foreground: the accent is
                  // near-white in dark mode, so plain white disappeared.
                  child: _shown
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: context.onBrandAccent,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
