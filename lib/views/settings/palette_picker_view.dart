import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/services/identity/daily_mark.dart';
import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';

/// Settings › Appearance › Palette. Each board is a small piece of the app
/// under one palette (Home's mark, a Continue card, a row), drawn with that
/// palette's real theme in the current light or dark mode. "Daily" lets the
/// date choose. Choosing applies at once; the app's colours animate across.
class PalettePickerView extends ConsumerWidget {
  const PalettePickerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final choice = ref.watch(paletteChoiceProvider);
    final mark = ref.watch(homeMarkProvider);
    final today = DailyMark.paletteFor(ref.watch(identityDayProvider));
    final notifier = ref.read(paletteChoiceProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.paletteTitle)),
      body: GridView.extent(
        maxCrossAxisExtent: 240,
        childAspectRatio: 0.92,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: [
          PaletteBoard(
            key: const ValueKey('palette_daily'),
            palette: today,
            title: l10n.paletteDaily,
            subtitle: today.name,
            daily: true,
            mark: mark,
            selected: choice is DailyPalette,
            onTap: () => notifier.choose(const DailyPalette()),
          ),
          for (final p in IdentityPalettes.all)
            PaletteBoard(
              key: ValueKey('palette_${p.id}'),
              palette: p,
              title: p.name,
              mark: mark,
              selected: choice == FixedPalette(p.id),
              onTap: () => notifier.choose(FixedPalette(p.id)),
            ),
        ],
      ),
    );
  }
}

/// One palette, previewed as the app it would make.
class PaletteBoard extends StatelessWidget {
  const PaletteBoard({
    super.key,
    required this.palette,
    required this.title,
    required this.mark,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.daily = false,
  });

  final IdentityPalette palette;
  final String title;
  final String? subtitle;
  final MarkSpec mark;
  final bool selected;
  final bool daily;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outer = Theme.of(context).colorScheme;
    final theme = meditejoTheme(Theme.of(context).brightness, palette);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: subtitle == null ? title : '$title, $subtitle',
      child: Theme(
        data: theme,
        child: Material(
          color: scheme.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MeditejoShapes.extraLarge),
            side: selected
                ? BorderSide(color: outer.primary, width: 3)
                : BorderSide(color: outer.outlineVariant),
          ),
          child: InkWell(
            onTap: onTap,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _BoardContent(
                  palette: palette,
                  title: title,
                  subtitle: subtitle,
                  daily: daily,
                  selected: selected,
                  mark: mark,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardContent extends StatelessWidget {
  const _BoardContent({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.daily,
    required this.selected,
    required this.mark,
  });

  final IdentityPalette palette;
  final String title;
  final String? subtitle;
  final bool daily;
  final bool selected;
  final MarkSpec mark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    Widget bar(double width, Color color, [double height = 6]) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.emphasized.titleSmall?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.baseline.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 20, color: scheme.primary)
            else
              _Swatches(palette: palette, daily: daily),
          ],
        ),
        const Spacer(),
        Center(child: MeditejoMark(mark: mark, size: 64, still: true)),
        const Spacer(),
        // A Continue card.
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(MeditejoShapes.large),
          ),
          child: Row(
            children: [
              Icon(
                Icons.play_arrow_rounded,
                size: 20,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(72, scheme.onPrimaryContainer),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: 0.4,
                        minHeight: 4,
                        color: scheme.primary,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // A library row.
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(MeditejoShapes.medium),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(64, scheme.onSurface, 5),
                    const SizedBox(height: 4),
                    bar(40, scheme.onSurfaceVariant, 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The palette's four mark colours, or every palette's form for "Daily".
class _Swatches extends StatelessWidget {
  const _Swatches({required this.palette, required this.daily});

  final IdentityPalette palette;
  final bool daily;

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).colorScheme.surface;
    if (daily) {
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              for (final p in IdentityPalettes.all) Color(p.form),
              Color(IdentityPalettes.all.first.form),
            ],
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in [
          palette.tile,
          palette.form,
          palette.stroke,
          palette.accent,
        ])
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: Color(c),
              shape: BoxShape.circle,
              border: Border.all(color: border.withValues(alpha: 0.6)),
            ),
          ),
      ],
    );
  }
}
