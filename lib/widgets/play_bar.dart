import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:medito/constants/constants.dart';

/// The bottom bar of a course's or an episode's page: its one primary
/// action, in the thumb's reach, always on screen.
///
/// It is led by its icon, not by a word. A play disc starts; the same disc
/// inside a ring that shows how far in the user is resumes; a quiet replay
/// disc inside a closed ring plays a finished course again. Beside it, in
/// small text, is what will play ([caption]). The word ("Resume", "Start",
/// "Play again") is the screen reader's [label] and the tooltip.
class PlayBar extends StatelessWidget {
  const PlayBar({
    super.key,
    this.actionKey,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.caption,
    this.progress,
    this.replay = false,
    this.busy = false,
    this.trailing,
    this.maxWidth = 600,
  });

  /// The key of the tappable action itself.
  final Key? actionKey;

  /// What a screen reader says: the action word and what it plays.
  final String label;
  final String tooltip;

  /// Null while the action cannot run (not ready yet, or already starting).
  final VoidCallback? onTap;

  /// What will play: a session's name, or "from 12:34". One line.
  final String? caption;

  /// How far in, 0 to 1, drawn as a ring around the disc: this is what
  /// says "resume". Null for a plain start.
  final double? progress;

  /// A finished course: play it again.
  final bool replay;

  /// Starting: the disc shows a spinner.
  final bool busy;

  /// A small secondary control at the bar's end ("From the beginning").
  final Widget? trailing;

  /// The page body's width on a wide screen, so the bar lines up with it.
  final double maxWidth;

  /// The disc alone, and smaller inside its ring, in the same 48 dp box.
  static const _disc = 44.0;
  static const _ringed = 34.0;
  static const _ring = 48.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Material(
      color: theme.scaffoldBackgroundColor,
      shape: Border(top: BorderSide(color: onSurface.withValues(alpha: 0.1))),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(child: _action(context)),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: InkWell(
          key: actionKey,
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _ring),
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  _icon(context),
                  if (caption != null) ...[
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        caption!,
                        key: const ValueKey('play_title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onSurface.withValues(alpha: 0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The disc, and around it the ring when there is progress to show.
  Widget _icon(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final accent = context.brandAccent;
    final ring = replay ? 1.0 : progress;
    final foreground = replay ? onSurface : context.onBrandAccent;
    return SizedBox.square(
      dimension: _ring,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (ring != null)
            CustomPaint(
              key: const ValueKey('play_progress'),
              size: const Size.square(_ring),
              painter: _RingPainter(
                progress: ring.clamp(0.0, 1.0),
                track: onSurface.withValues(alpha: 0.2),
                color: accent,
              ),
            ),
          Container(
            width: ring == null ? _disc : _ringed,
            height: ring == null ? _disc : _ringed,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: replay ? onSurface.withValues(alpha: 0.08) : accent,
            ),
            alignment: Alignment.center,
            child: busy
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: foreground,
                    ),
                  )
                : Icon(
                    replay ? Icons.replay_rounded : Icons.play_arrow_rounded,
                    size: replay ? 20 : (ring == null ? 28 : 22),
                    color: foreground,
                  ),
          ),
        ],
      ),
    );
  }
}

/// How far in: an arc from twelve o'clock, clockwise, over a faint full
/// circle.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.track,
    required this.color,
  });

  final double progress;
  final Color track;
  final Color color;

  static const _stroke = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.track != track || old.color != color;
}
