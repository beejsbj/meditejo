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
  const PackItemWidget({super.key, required this.item, this.onSetComplete});

  final PackItemsModel item;

  /// Persists a track row's completion to an absolute value, returning whether
  /// the write succeeded (so the control can revert an optimistic flip).
  /// When null (e.g. pack rows, or a list outside a course) no completion
  /// control is shown; a finished session still shows its tick.
  final Future<bool> Function(bool complete)? onSetComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var hasSubtitle = item.subtitle.isNotNullAndNotEmpty();
    final detailed = item.kind != null && item.type == TypeConstants.track;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Container(
            width: MediaQuery.of(context).size.width,
            padding: EdgeInsets.only(
              top: hasSubtitle || detailed ? 24 : 20,
              bottom: 20,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (detailed) _kindLabel(context),
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

  /// "GUIDED MEDITATION": what the session is, before its title.
  Widget _kindLabel(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        item.kind!.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  /// "Rob Burbea · 42 min"
  Widget _details(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final minutes = ((item.durationMs ?? 0) / Duration.millisecondsPerMinute)
        .round();
    final text = [
      if (item.teacher.isNotNullAndNotEmpty()) item.teacher!,
      if (minutes > 0) l10n.courseSessionLength(minutes),
    ].join(' · ');
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }

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
