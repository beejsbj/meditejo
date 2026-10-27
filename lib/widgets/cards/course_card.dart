import 'package:flutter/material.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/pressable_card.dart';

/// How far along something is: a bar at [value] (0 to 1) and a short
/// [label] beside it ("3 of 12", "29:00 left").
@immutable
class CardProgress {
  const CardProgress(this.value, this.label);

  /// [done] of [total] sessions, labelled by [label]; null when there is
  /// nothing to show (nothing begun, or no sessions).
  static CardProgress? of(int done, int total, String label) =>
      done <= 0 || total <= 0 ? null : CardProgress(done / total, label);

  final double value;
  final String label;
}

/// A slim 2024-style progress bar with its label at the end.
class CardProgressBar extends StatelessWidget {
  const CardProgressBar(this.progress, {super.key});

  final CardProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: progress.value.clamp(0, 1),
            borderRadius: BorderRadius.circular(4),
            minHeight: 6,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            progress.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.typography.baseline.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// The small line above a card's title: where it comes from ("Dharma Seed",
/// "YouTube", "Playlist") or what it is.
class CardOverline extends StatelessWidget {
  const CardOverline(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.typography.emphasized.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// How big a [CourseCard] is drawn.
enum CourseCardSize {
  /// Explore's featured courses and the Library's in-progress cards: wide
  /// art and a large title.
  large,

  /// The Library's grid.
  medium,

  /// A strip of small cards ("In your library" on Explore).
  compact,
}

/// A course or playlist as a card: art on top, then its [overline] (source or
/// kind), its name, a line of [detail] and, once begun, its [progress].
/// [action] (Add to library, a menu, Play) sits on the art's top-right corner
/// and stays its own button.
class CourseCard extends StatelessWidget {
  const CourseCard({
    super.key,
    required this.title,
    required this.art,
    required this.onTap,
    this.size = CourseCardSize.medium,
    this.overline,
    this.detail,
    this.progress,
    this.action,
    this.badge,
  });

  final String title;
  final Widget art;
  final VoidCallback onTap;
  final CourseCardSize size;
  final String? overline;
  final String? detail;
  final CardProgress? progress;
  final Widget? action;

  /// A small mark on the art's bottom-right (pinned).
  final Widget? badge;

  static double _aspect(CourseCardSize size) => switch (size) {
    CourseCardSize.large => 16 / 9,
    CourseCardSize.medium => 4 / 3,
    CourseCardSize.compact => 1,
  };

  static int _detailLines(CourseCardSize size) =>
      size == CourseCardSize.compact ? 1 : 2;

  static TextStyle? _titleStyle(BuildContext context, CourseCardSize size) {
    final type = context.typography.emphasized;
    return switch (size) {
      CourseCardSize.large => type.titleLarge,
      CourseCardSize.medium => type.titleMedium,
      CourseCardSize.compact => type.titleSmall,
    };
  }

  static TextStyle? _detailStyle(BuildContext context, CourseCardSize size) {
    final type = context.typography.baseline;
    return size == CourseCardSize.compact ? type.bodySmall : type.bodyMedium;
  }

  static EdgeInsets _textPadding(CourseCardSize size) =>
      size == CourseCardSize.compact
      ? const EdgeInsets.fromLTRB(12, 8, 12, 12)
      : const EdgeInsets.fromLTRB(16, 10, 16, 16);

  /// The height a card [width] wide needs at the current text size, with
  /// room for every line it may show. Strips of cards are this tall, so a
  /// larger text size grows them rather than overflowing.
  static double heightFor(
    BuildContext context, {
    required double width,
    CourseCardSize size = CourseCardSize.medium,
    bool overline = true,
    bool detail = true,
    bool progress = false,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    double lines(TextStyle? style, int count) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ag', style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final height = painter.height * count;
      painter.dispose();
      return height;
    }

    final type = context.typography;
    final pad = _textPadding(size);
    final art = (width - 2 * kCardArtInset) / _aspect(size) + kCardArtInset;
    return (art +
            pad.vertical +
            (overline ? lines(type.emphasized.labelMedium, 1) + 2 : 0) +
            lines(_titleStyle(context, size), 2) +
            (detail
                ? 2 + lines(_detailStyle(context, size), _detailLines(size))
                : 0) +
            (progress ? 8 + lines(type.baseline.labelMedium, 1) : 0))
        .ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableCard(
      color: scheme.surfaceContainer,
      radius: kCardRadius,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kCardArtInset,
              kCardArtInset,
              kCardArtInset,
              0,
            ),
            child: AspectRatio(
              aspectRatio: _aspect(size),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(kCardInsetArtRadius),
                    child: art,
                  ),
                  if (action != null)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: CardActionDisc(action!),
                    ),
                  if (badge != null)
                    Positioned(bottom: 8, right: 8, child: badge!),
                ],
              ),
            ),
          ),
          Padding(
            padding: _textPadding(size),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (overline != null && overline!.isNotEmpty) ...[
                  CardOverline(overline!),
                  const SizedBox(height: 2),
                ],
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle(context, size),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    maxLines: _detailLines(size),
                    overflow: TextOverflow.ellipsis,
                    style: _detailStyle(
                      context,
                      size,
                    )?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  CardProgressBar(progress!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A card's action on its art: a quiet disc behind the button, so it reads on
/// any picture without shouting.
class CardActionDisc extends StatelessWidget {
  const CardActionDisc(this.child, {super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: scheme.onSurface),
        ),
        child: child,
      ),
    );
  }
}

/// A course or playlist as a wide row card: art at the start, then its
/// [overline], name, [detail] and [progress], with [trailing] (a menu) at
/// the end. The list form of [CourseCard]; Home's pinned cards are the same
/// shape.
class CourseRowCard extends StatelessWidget {
  const CourseRowCard({
    super.key,
    required this.title,
    required this.art,
    required this.onTap,
    this.overline,
    this.detail,
    this.progress,
    this.trailing = const [],
    this.artSize = 72,
  });

  final String title;
  final Widget art;
  final VoidCallback onTap;
  final String? overline;
  final String? detail;
  final CardProgress? progress;
  final List<Widget> trailing;
  final double artSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    return PressableCard(
      color: scheme.surfaceContainer,
      radius: kCardRadius,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, trailing.isEmpty ? 16 : 4, 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(kCardArtRadius),
              child: SizedBox.square(dimension: artSize, child: art),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (overline != null && overline!.isNotEmpty)
                    CardOverline(overline!),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: type.emphasized.titleMedium,
                  ),
                  if (detail != null && detail!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        detail!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: type.baseline.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (progress != null) ...[
                    const SizedBox(height: 8),
                    CardProgressBar(progress!),
                  ],
                ],
              ),
            ),
            ...trailing,
          ],
        ),
      ),
    );
  }
}
