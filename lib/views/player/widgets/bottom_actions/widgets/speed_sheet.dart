import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/player/audio_state_provider.dart';
import 'package:medito/providers/player/playback_speed_provider.dart';
import 'package:medito/providers/player/player_provider.dart';

/// "1×", "0.75×", "1.5×": no trailing zeros.
String formatSpeed(double speed) {
  var text = speed.toStringAsFixed(2);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '$text×';
}

/// Opens the speed sheet. In a session, [sessionKind] is the session's kind:
/// it is listed first and open, shows the speed the session is playing at,
/// and a change to it also goes to the player through [onSpeedChanged]. The
/// other kind's speed can be set from here too; it applies from the next
/// session of that kind. The sheet closes when the session changes (autoplay
/// moving on), since the next one may be of the other kind. Without a session
/// (from Settings) both kinds are listed, Practice first, and nothing plays.
Future<void> showSpeedSheet(
  BuildContext context, {
  CueKind? sessionKind,
  ValueChanged<double>? onSpeedChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
    builder: (_) =>
        SpeedSheet(sessionKind: sessionKind, onSpeedChanged: onSpeedChanged),
  );
}

/// Playback speed for each kind of session. Two tabs, Practice and Talks, each
/// showing its speed; the one being edited is filled. Below, every stop as a
/// button. A choice is saved for its kind at once, and is the speed the next
/// session of that kind starts at.
class SpeedSheet extends ConsumerStatefulWidget {
  const SpeedSheet({super.key, this.sessionKind, this.onSpeedChanged});

  final CueKind? sessionKind;
  final ValueChanged<double>? onSpeedChanged;

  @override
  ConsumerState<SpeedSheet> createState() => _SpeedSheetState();
}

class _SpeedSheetState extends ConsumerState<SpeedSheet> {
  late CueKind _editing = widget.sessionKind ?? CueKind.practice;

  /// The speed the session plays at. It can differ from the stored one (a
  /// lock screen or car changed it), and is set at once on a choice so the
  /// highlight does not wait for the engine's next report.
  double? _live;

  /// The session the sheet was opened in.
  String? _sessionTrack;

  bool get _inSession => widget.sessionKind != null;

  @override
  void initState() {
    super.initState();
    if (_inSession) {
      _sessionTrack = ref.read(playerProvider)?.trackId;
      _live = normalisePlaybackSpeed(ref.read(audioStateProvider).speed.speed);
    }
  }

  /// The speed shown for [kind]: the live one for the session's kind.
  double _speedOf(CueKind kind) => kind == widget.sessionKind && _live != null
      ? _live!
      : ref.watch(playbackSpeedProvider(kind));

  List<CueKind> get _kinds {
    final current = widget.sessionKind;
    if (current == null) return CueKind.values;
    return [current, ...CueKind.values.where((k) => k != current)];
  }

  void _choose(double speed) {
    final kind = _editing;
    if (kind == widget.sessionKind) {
      // Always applied: the engine may be at another speed than the stored
      // one, and choosing the stored speed must bring it back.
      setState(() => _live = speed);
      widget.onSpeedChanged?.call(speed);
    } else if (ref.read(playbackSpeedProvider(kind)) == speed) {
      return;
    }
    ref.read(playbackSpeedProvider(kind).notifier).set(speed);
  }

  void _close() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    Navigator.of(context).removeRoute(route);
  }

  String _kindName(AppLocalizations l10n, CueKind kind) =>
      kind == CueKind.practice ? l10n.speedKindPractice : l10n.speedKindTalks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    if (_inSession) {
      ref.listen(audioStateProvider.select((s) => s.speed.speed), (_, next) {
        setState(() => _live = normalisePlaybackSpeed(next));
      });
      ref.listen(playerProvider.select((r) => r?.trackId), (_, next) {
        if (next != _sessionTrack) _close();
      });
    }
    final speed = _speedOf(_editing);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // No Reset beside the title: 1× is one tap in the grid, and the
            // title keeps the whole width for long translations.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l10n.playbackSpeed,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (i, kind) in _kinds.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _KindTab(
                      key: ValueKey('speed_kind_${kind.name}'),
                      name: _kindName(l10n, kind),
                      speed: formatSpeed(_speedOf(kind)),
                      selected: kind == _editing,
                      onTap: () => setState(() => _editing = kind),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _SpeedGrid(
              key: ValueKey('speed_grid_${_editing.name}'),
              selected: speed,
              onSelected: _choose,
            ),
            const SizedBox(height: 12),
            Text(
              _editing == CueKind.practice
                  ? l10n.speedPracticeCaption
                  : l10n.speedTalksCaption,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13,
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindTab extends StatelessWidget {
  const _KindTab({
    super.key,
    required this.name,
    required this.speed,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String speed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final radius = BorderRadius.circular(12);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: '$name, $speed',
      excludeSemantics: true,
      child: Material(
        color: selected
            ? onSurface.withValues(alpha: 0.10)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: onSurface.withValues(alpha: selected ? 0.0 : 0.15),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: onSurface.withValues(alpha: selected ? 1 : 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    speed,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFamily: googleSans,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: onSurface.withValues(alpha: selected ? 0.85 : 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every stop, four to a row, each a 48 dp button.
class _SpeedGrid extends StatelessWidget {
  const _SpeedGrid({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final double selected;
  final ValueChanged<double> onSelected;

  static const _perRow = 4;

  @override
  Widget build(BuildContext context) {
    final rows = <List<double>>[
      for (var i = 0; i < playbackSpeedOptions.length; i += _perRow)
        playbackSpeedOptions.sublist(
          i,
          (i + _perRow).clamp(0, playbackSpeedOptions.length),
        ),
    ];
    return Column(
      children: [
        for (final (r, row) in rows.indexed) ...[
          if (r > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (final (i, speed) in row.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _SpeedButton(
                    speed: speed,
                    selected: speed == selected,
                    onTap: () => onSelected(speed),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({
    required this.speed,
    required this.selected,
    required this.onTap,
  });

  final double speed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final radius = BorderRadius.circular(12);
    final label = formatSpeed(speed);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        key: ValueKey('speed_option_$label'),
        color: selected
            ? context.brandAccent
            : onSurface.withValues(alpha: 0.06),
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  label,
                  maxLines: 1,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: googleSans,
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? context.onBrandAccent
                        : onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
