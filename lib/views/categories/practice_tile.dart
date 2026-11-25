import 'package:flutter/material.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';

/// The three sizes of a practice's tile (Burooj, 2026-11-02): one anatomy
/// (figure, name, where the name comes from, one line) at three densities.
enum PracticeTileSize {
  /// Explore's carousels: a card with the figure above two or three lines.
  card,

  /// The practices page's grid: a taller card with the whole line.
  tall,

  /// The labels sheet: the figure as the background, the name over a scrim,
  /// no line; tapping ticks it.
  compact,
}

/// The groups, in the order the screens show them.
const practiceGroups = [
  'heart',
  'concentration',
  'insight',
  'awareness',
  'body',
  'devotion',
  'imagination',
];

String practiceGroupName(AppLocalizations l10n, String group) =>
    switch (group) {
      'heart' => l10n.practiceGroupHeart,
      'concentration' => l10n.practiceGroupConcentration,
      'insight' => l10n.practiceGroupInsight,
      'awareness' => l10n.practiceGroupAwareness,
      'body' => l10n.practiceGroupBody,
      'devotion' => l10n.practiceGroupDevotion,
      'imagination' => l10n.practiceGroupImagination,
      _ => group,
    };

/// [categories] by group, in [practiceGroups]' order, empty groups left out.
/// A category with no group (an older asset) goes last, under its own.
List<(String group, List<PracticeCategory> items)> groupPractices(
  Iterable<PracticeCategory> categories,
) {
  final by = <String, List<PracticeCategory>>{};
  for (final c in categories) {
    (by[c.group] ??= []).add(c);
  }
  return [
    for (final g in practiceGroups)
      if (by[g] case final items?) (g, items),
    for (final MapEntry(:key, :value) in by.entries)
      if (!practiceGroups.contains(key)) (key, value),
  ];
}

/// The small line under a practice's name: its languages (translated) or
/// its originals or founder (as written), then its own script.
String practiceMeta(AppLocalizations l10n, PracticeCategory c) {
  final from = c.label.isNotEmpty
      ? c.label
      : [
          for (final code in c.langs)
            switch (code) {
              'pi' => l10n.practiceLangPali,
              'sa' => l10n.practiceLangSanskrit,
              'bo' => l10n.practiceLangTibetan,
              'ja' => l10n.practiceLangJapanese,
              _ => code,
            },
        ].join(' · ');
  return [from, c.script].where((s) => s.isNotEmpty).join('  ');
}

class PracticeTile extends StatelessWidget {
  const PracticeTile({
    super.key,
    required this.category,
    required this.size,
    this.onTap,
    this.selected,
  });

  final PracticeCategory category;
  final PracticeTileSize size;
  final VoidCallback? onTap;

  /// Compact tiles only: ticked or not; null when the tile is not a choice.
  final bool? selected;

  ArtSubject get _art => ArtSubject.practice(
    category.id,
    ground: category.ground,
    figure: category.figure,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final meta = practiceMeta(l10n, category);
    final line = category.blurbFor(
      Localizations.localeOf(context).languageCode,
    );
    final radius = BorderRadius.circular(
      size == PracticeTileSize.compact ? 16 : 18,
    );
    final semantics = [
      category.name,
      meta,
      if (size != PracticeTileSize.compact) line,
    ].join('. ');

    final metaStyle = type.baseline.labelSmall?.copyWith(
      letterSpacing: 0.4,
      color: scheme.onSurfaceVariant,
    );

    Widget body;
    if (size == PracticeTileSize.compact) {
      final on = selected ?? false;
      body = Stack(
        fit: StackFit.expand,
        children: [
          ArtCover(subject: _art, scrim: true, live: true),
          Positioned(
            left: 12,
            // Clear of the tick's badge.
            right: (selected ?? false) ? 36 : 10,
            bottom: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: type.emphasized.titleSmall?.copyWith(
                    color: Colors.white,
                    shadows: const [
                      Shadow(blurRadius: 6, color: Colors.black38),
                    ],
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: metaStyle?.copyWith(color: Colors.white70),
                  ),
              ],
            ),
          ),
          if (on)
            Positioned(
              top: 8,
              right: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(Icons.check, size: 16, color: scheme.onPrimary),
                ),
              ),
            ),
          if (on)
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: scheme.primary, width: 3),
              ),
            ),
        ],
      );
    } else {
      final tall = size == PracticeTileSize.tall;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: tall ? 170 / 148 : 148 / 132,
            // Live, but only while some of the tile is on screen and the
            // app is in front; reduce motion gives the still frame
            // (ArtCover). Burooj, 2026-11-02.
            child: ArtCover(subject: _art, live: true),
          ),
          // The slot's height is fixed (a carousel row, a grid cell), so the
          // words take what is left and clip under large text.
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  tall ? 12 : 10,
                  10,
                  10,
                  tall ? 14 : 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: type.emphasized.titleSmall,
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: metaStyle,
                      ),
                    ],
                    if (line.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        line,
                        maxLines: tall ? 4 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: type.baseline.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // One node for a screen reader, with the tap kept: excluding the
    // children drops the InkWell's action, so Semantics carries it.
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: semantics,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            body,
            // Over the art, so the ripple shows on the figure too.
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
