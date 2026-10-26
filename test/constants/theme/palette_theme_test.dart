import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/constants/theme/palette_theme.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/widgets/branding/mark_painter.dart';

/// Text roles and the surfaces they are read on. Every pair must reach
/// WCAG AA for body text (4.5:1).
List<(String, Color, String, Color)> _textPairs(ColorScheme s) {
  final surfaces = {
    'surface': s.surface,
    'surfaceContainerLowest': s.surfaceContainerLowest,
    'surfaceContainerLow': s.surfaceContainerLow,
    'surfaceContainer': s.surfaceContainer,
    'surfaceContainerHigh': s.surfaceContainerHigh,
    'surfaceContainerHighest': s.surfaceContainerHighest,
  };
  final onSurfaces = {
    'onSurface': s.onSurface,
    'onSurfaceVariant': s.onSurfaceVariant,
    'primary': s.primary,
    'secondary': s.secondary,
    'tertiary': s.tertiary,
  };
  return [
    for (final fg in onSurfaces.entries)
      for (final bg in surfaces.entries) (fg.key, fg.value, bg.key, bg.value),
    ('onPrimary', s.onPrimary, 'primary', s.primary),
    (
      'onPrimaryContainer',
      s.onPrimaryContainer,
      'primaryContainer',
      s.primaryContainer,
    ),
    ('onSecondary', s.onSecondary, 'secondary', s.secondary),
    (
      'onSecondaryContainer',
      s.onSecondaryContainer,
      'secondaryContainer',
      s.secondaryContainer,
    ),
    ('onTertiary', s.onTertiary, 'tertiary', s.tertiary),
    (
      'onTertiaryContainer',
      s.onTertiaryContainer,
      'tertiaryContainer',
      s.tertiaryContainer,
    ),
    ('onError', s.onError, 'error', s.error),
    (
      'onErrorContainer',
      s.onErrorContainer,
      'errorContainer',
      s.errorContainer,
    ),
    (
      'onInverseSurface',
      s.onInverseSurface,
      'inverseSurface',
      s.inverseSurface,
    ),
    ('inversePrimary', s.inversePrimary, 'inverseSurface', s.inverseSurface),
  ];
}

void main() {
  for (final palette in IdentityPalettes.all) {
    for (final brightness in Brightness.values) {
      test('${palette.name}, ${brightness.name}: text reaches WCAG AA', () {
        final scheme = paletteColorScheme(palette, brightness);
        final failures = [
          for (final (fg, a, bg, b) in _textPairs(scheme))
            if (contrastRatio(a, b) < 4.5)
              '$fg on $bg: ${contrastRatio(a, b).toStringAsFixed(2)}',
        ];
        expect(failures, isEmpty);
      });
    }
  }

  test("the palette's own neutrals are kept where they are legible", () {
    final tide = IdentityPalettes.byId('tide');
    final dark = paletteColorScheme(tide, Brightness.dark);
    expect(dark.surface, Color(tide.dark.bg));
    expect(dark.surfaceContainer, Color(tide.dark.surface));
    expect(dark.surfaceContainerHigh, Color(tide.dark.raised));
    expect(dark.onSurface, Color(tide.dark.text));
    expect(dark.onSurfaceVariant, Color(tide.dark.muted));
    final light = paletteColorScheme(tide, Brightness.light);
    expect(light.surface, Color(tide.light.bg));
    expect(light.onSurface, Color(tide.light.text));
    // Light muted text is 3.9:1 on its raised surface, so it is deepened.
    expect(light.onSurfaceVariant, isNot(Color(tide.light.muted)));
  });

  test('the theme carries its palette, and Tidewater is the default', () {
    expect(
      meditejoTheme(Brightness.light).extension<MeditejoPalette>()!.palette.id,
      'tide',
    );
    final dusk = IdentityPalettes.byId('dusk');
    final theme = meditejoTheme(Brightness.dark, dusk);
    expect(theme.extension<MeditejoPalette>()!.palette, dusk);
    expect(theme.colorScheme.surface, Color(dusk.dark.bg));
  });

  test('legibleOn leaves a legible colour alone and deepens a faint one', () {
    const white = Color(0xFFFFFFFF), black = Color(0xFF000000);
    expect(legibleOn(black, [white], toward: black), black);
    final grey = legibleOn(const Color(0xFFAAAAAA), [white], toward: black);
    expect(contrastRatio(grey, white), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(grey, white), lessThan(5.2));
  });

  test("on the app's background, a mark's cut-outs show the background", () {
    final tide = IdentityPalettes.byId('tide');
    final scheme = paletteColorScheme(tide, Brightness.dark);
    final colors = MeditejoPalette(tide).markColors(scheme);
    expect(colors.ground, scheme.surface);
    expect(colors.tile, Color(tide.tile));
    // On its own tile, the ground is the tile.
    expect(MarkColors.of(tide).ground, Color(tide.tile));
  });
}
