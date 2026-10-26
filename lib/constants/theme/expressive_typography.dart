import 'package:flutter/material.dart';
import 'package:medito/constants/theme/tokens.dart';

/// The M3 type scale, baseline and emphasized, coloured for the theme. A
/// theme extension rather than `ThemeData.textTheme`, because the screens
/// not yet redesigned use the text roles with Medito's own sizes (see
/// `text_theme.dart`); each redesigned screen moves to these, and when the
/// last one has, these become the `textTheme`.
@immutable
class ExpressiveTypography extends ThemeExtension<ExpressiveTypography> {
  const ExpressiveTypography({
    required this.baseline,
    required this.emphasized,
  });

  factory ExpressiveTypography.from(ColorScheme scheme) => ExpressiveTypography(
    baseline: MeditejoType.baseline().apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    emphasized: MeditejoType.emphasized().apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
  );

  /// The baseline M3 scale.
  final TextTheme baseline;

  /// Expressive's emphasized styles: same sizes, heavier.
  final TextTheme emphasized;

  @override
  ExpressiveTypography copyWith({TextTheme? baseline, TextTheme? emphasized}) =>
      ExpressiveTypography(
        baseline: baseline ?? this.baseline,
        emphasized: emphasized ?? this.emphasized,
      );

  @override
  ExpressiveTypography lerp(covariant ExpressiveTypography? other, double t) {
    if (other == null) return this;
    return ExpressiveTypography(
      baseline: TextTheme.lerp(baseline, other.baseline, t),
      emphasized: TextTheme.lerp(emphasized, other.emphasized, t),
    );
  }
}

extension ExpressiveTypographyContext on BuildContext {
  /// The M3 type scale; see [ExpressiveTypography]. Falls back to building it
  /// from the ambient scheme, so a widget tested under a bare `ThemeData`
  /// still lays out.
  ExpressiveTypography get typography {
    final theme = Theme.of(this);
    return theme.extension<ExpressiveTypography>() ??
        ExpressiveTypography.from(theme.colorScheme);
  }
}
