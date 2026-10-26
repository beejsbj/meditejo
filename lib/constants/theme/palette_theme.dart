import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/widgets/branding/mark_painter.dart';

/// An identity palette as the app's Material 3 colour scheme (decision 21:
/// the palette is the app theme).
///
/// - **Ramps** grow from the palette's form colour with Material's neutral
///   variant ([MeditejoColorTokens.variant]); the tertiary roles grow from
///   its accent with tonal spot ([MeditejoColorTokens.accentVariant]), so
///   they carry its hue at tones that keep text legible.
/// - **Neutrals** are the palette's own: surface = bg, surfaceContainer =
///   surface, surfaceContainerHigh = raised, onSurface = text,
///   onSurfaceVariant = muted. The rest are mixed from those.
/// - **Contrast:** text roles are held at WCAG AA (4.5:1) on every surface
///   they sit on. Where a palette's muted text falls short (every light
///   palette does on its raised surface), it is deepened toward its text
///   colour just enough. `test/constants/theme/palette_theme_test.dart`
///   checks every palette, light and dark.
ColorScheme paletteColorScheme(IdentityPalette palette, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final n = palette.neutrals(dark: dark);
  final base = ColorScheme.fromSeed(
    seedColor: Color(palette.form),
    brightness: brightness,
    dynamicSchemeVariant: MeditejoColorTokens.variant,
  );
  final accent = ColorScheme.fromSeed(
    seedColor: Color(palette.accent),
    brightness: brightness,
    dynamicSchemeVariant: MeditejoColorTokens.accentVariant,
  );
  final bg = Color(n.bg), surface = Color(n.surface), raised = Color(n.raised);
  final text = Color(n.text);
  final lowest = dark
      ? _mix(bg, const Color(0xFF000000), 0.3)
      : _mix(bg, const Color(0xFFFFFFFF), 0.6);
  final low = _mix(bg, surface, 0.5);
  final highest = _mix(raised, text, 0.06);
  final surfaces = [lowest, bg, low, surface, raised, highest];
  return base.copyWith(
    onTertiary: accent.onPrimary,
    tertiaryContainer: accent.primaryContainer,
    onTertiaryContainer: accent.onPrimaryContainer,
    surface: bg,
    surfaceDim: dark ? bg : _mix(bg, text, 0.08),
    surfaceBright: dark ? _mix(raised, text, 0.08) : bg,
    surfaceContainerLowest: lowest,
    surfaceContainerLow: low,
    surfaceContainer: surface,
    surfaceContainerHigh: raised,
    surfaceContainerHighest: highest,
    onSurface: legibleOn(text, surfaces, toward: text),
    onSurfaceVariant: legibleOn(Color(n.muted), surfaces, toward: text),
    primary: legibleOn(base.primary, surfaces, toward: text),
    secondary: legibleOn(base.secondary, surfaces, toward: text),
    tertiary: legibleOn(accent.primary, surfaces, toward: text),
    inverseSurface: text,
    onInverseSurface: bg,
  );
}

/// [color], moved toward [toward] in small steps until it reaches [ratio]
/// against every one of [backgrounds] (unchanged if it already does).
Color legibleOn(
  Color color,
  List<Color> backgrounds, {
  required Color toward,
  double ratio = 4.5,
}) {
  bool ok(Color c) => backgrounds.every((b) => contrastRatio(c, b) >= ratio);
  for (var t = 0.0; t <= 1.0001; t += 0.02) {
    final c = _mix(color, toward, t);
    if (ok(c)) return c;
  }
  return toward;
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, math.min(t, 1))!;

/// The active identity palette, carried on the theme for the mark and the
/// art painters (`Theme.of(context).extension<MeditejoPalette>()`).
@immutable
class MeditejoPalette extends ThemeExtension<MeditejoPalette> {
  const MeditejoPalette(this.palette);

  final IdentityPalette palette;

  /// The mark's colours drawn straight on the app's background, with no
  /// tile: a stroke too faint there takes the text colour.
  MarkColors markColors(ColorScheme scheme) => MarkColors.onBackground(
    palette,
    background: scheme.surface,
    text: scheme.onSurface,
  );

  static MeditejoPalette of(BuildContext context) =>
      Theme.of(context).extension<MeditejoPalette>() ??
      MeditejoPalette(IdentityPalettes.fallback);

  @override
  MeditejoPalette copyWith({IdentityPalette? palette}) =>
      MeditejoPalette(palette ?? this.palette);

  /// Palettes switch, they don't blend: the theme's colours animate, and
  /// the mark follows at the halfway point.
  @override
  MeditejoPalette lerp(MeditejoPalette? other, double t) =>
      other == null || t < 0.5 ? this : other;

  @override
  bool operator ==(Object other) =>
      other is MeditejoPalette && other.palette.id == palette.id;

  @override
  int get hashCode => palette.id.hashCode;
}
