/// The identity palettes (round 2 of the exploration, `marks.js`), in the
/// page's order. The order is part of the daily palette's shuffle, so add
/// new palettes at the end.
///
/// Colours are 0xAARRGGBB ints, so this file stays free of Flutter and the
/// icon tool can read it. `constants/theme/palette_theme.dart` turns a
/// palette into the app's colour scheme.
class IdentityPalette {
  const IdentityPalette({
    required this.id,
    required this.name,
    required this.mood,
    required this.tile,
    required this.form,
    required this.stroke,
    required this.accent,
    required this.light,
    required this.dark,
  });

  final String id;
  final String name;
  final String mood;

  /// The mark's four roles: the tile it sits on, the form (pebble), the
  /// stroke and an accent.
  final int tile, form, stroke, accent;

  /// The app's neutrals, light and dark.
  final PaletteNeutrals light, dark;

  PaletteNeutrals neutrals({required bool dark}) => dark ? this.dark : light;
}

/// The app's surfaces and text under a palette.
class PaletteNeutrals {
  const PaletteNeutrals({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.text,
    required this.muted,
  });

  final int bg, surface, raised, text, muted;
}

abstract final class IdentityPalettes {
  /// The default (decision 21).
  static const defaultId = 'tide';

  static const all = <IdentityPalette>[
    IdentityPalette(
      id: 'clay',
      name: 'Clay',
      mood: 'Terracotta, ochre, cream and ink.',
      tile: 0xFFF6F1E8,
      form: 0xFFD2754E,
      stroke: 0xFF1C1916,
      accent: 0xFFD9A13F,
      light: PaletteNeutrals(
        bg: 0xFFFAF6EF,
        surface: 0xFFF1E9DD,
        raised: 0xFFEADFCF,
        text: 0xFF2A221B,
        muted: 0xFF7A6B5D,
      ),
      dark: PaletteNeutrals(
        bg: 0xFF191512,
        surface: 0xFF241E19,
        raised: 0xFF2E2620,
        text: 0xFFF2E9DD,
        muted: 0xFFA79482,
      ),
    ),
    IdentityPalette(
      id: 'dusk',
      name: 'Dusk',
      mood: 'Indigo, plum and a lamp of amber.',
      tile: 0xFF211E45,
      form: 0xFF7B4475,
      stroke: 0xFFF2B65E,
      accent: 0xFFE8846A,
      light: PaletteNeutrals(
        bg: 0xFFF6F3F8,
        surface: 0xFFECE6F1,
        raised: 0xFFE2D9EA,
        text: 0xFF211C3A,
        muted: 0xFF6C6585,
      ),
      dark: PaletteNeutrals(
        bg: 0xFF12102A,
        surface: 0xFF1C1938,
        raised: 0xFF262247,
        text: 0xFFEEE8F6,
        muted: 0xFFA097BA,
      ),
    ),
    IdentityPalette(
      id: 'forest',
      name: 'Forest',
      mood: 'Moss on bark under morning mist.',
      tile: 0xFFE8EBE2,
      form: 0xFF7E8E52,
      stroke: 0xFF2C241D,
      accent: 0xFFC9A15A,
      light: PaletteNeutrals(
        bg: 0xFFF3F4EE,
        surface: 0xFFE6E9DF,
        raised: 0xFFDBE0D2,
        text: 0xFF22271E,
        muted: 0xFF687160,
      ),
      dark: PaletteNeutrals(
        bg: 0xFF121611,
        surface: 0xFF1B211A,
        raised: 0xFF252C23,
        text: 0xFFE5EADE,
        muted: 0xFF949E8B,
      ),
    ),
    IdentityPalette(
      id: 'sumi',
      name: 'Sumi',
      mood: 'Ink on paper; value carries everything.',
      tile: 0xFFF3F0E9,
      form: 0xFFBCB5A8,
      stroke: 0xFF141413,
      accent: 0xFF6E685F,
      light: PaletteNeutrals(
        bg: 0xFFF7F5F0,
        surface: 0xFFECE8E0,
        raised: 0xFFE2DDD3,
        text: 0xFF161514,
        muted: 0xFF76716A,
      ),
      dark: PaletteNeutrals(
        bg: 0xFF111110,
        surface: 0xFF1B1A19,
        raised: 0xFF252422,
        text: 0xFFEDEAE3,
        muted: 0xFF8F8A82,
      ),
    ),
    IdentityPalette(
      id: 'riso',
      name: 'Lotus Riso',
      mood: 'Blush paper, lotus pink, blue ink.',
      tile: 0xFFF7EAE4,
      form: 0xFFEC9C8C,
      stroke: 0xFF24346E,
      accent: 0xFFF2C14E,
      light: PaletteNeutrals(
        bg: 0xFFFBF4F0,
        surface: 0xFFF4E6E0,
        raised: 0xFFEDDAD2,
        text: 0xFF1F2647,
        muted: 0xFF6E6A80,
      ),
      dark: PaletteNeutrals(
        bg: 0xFF121528,
        surface: 0xFF1B1F38,
        raised: 0xFF252A48,
        text: 0xFFF4E9E4,
        muted: 0xFFA39CB3,
      ),
    ),
    IdentityPalette(
      id: 'lagoon',
      name: 'Lagoon',
      mood: 'Night water and sand-coloured light.',
      tile: 0xFF0F2D33,
      form: 0xFF3F8C83,
      stroke: 0xFFF1E2C2,
      accent: 0xFFEE8D68,
      light: PaletteNeutrals(
        bg: 0xFFF1F5F3,
        surface: 0xFFE3ECE9,
        raised: 0xFFD5E3DF,
        text: 0xFF13292C,
        muted: 0xFF5F7472,
      ),
      dark: PaletteNeutrals(
        bg: 0xFF0B1C20,
        surface: 0xFF12282D,
        raised: 0xFF1A343A,
        text: 0xFFE9EFEA,
        muted: 0xFF8EA5A2,
      ),
    ),
    IdentityPalette(
      id: 'saffron',
      name: 'Saffron',
      mood: 'Robe saffron and maroon on temple stone.',
      tile: 0xFFF2ECE1,
      form: 0xFFE39A2E,
      stroke: 0xFF5B1F1D,
      accent: 0xFFB8452E,
      light: PaletteNeutrals(
        bg: 0xFFF8F4ED,
        surface: 0xFFEFE7DA,
        raised: 0xFFE6DBCA,
        text: 0xFF3A1715,
        muted: 0xFF7E655B,
      ),
      dark: PaletteNeutrals(
        bg: 0xFF1A1110,
        surface: 0xFF251917,
        raised: 0xFF30211E,
        text: 0xFFF3E7DA,
        muted: 0xFFAE9282,
      ),
    ),
    IdentityPalette(
      id: 'tide',
      name: 'Tidewater',
      mood: 'Sea glass, fog and slate ink, with one coral float.',
      tile: 0xFFE5EAEC,
      form: 0xFF86A9B1,
      stroke: 0xFF1E2C3A,
      accent: 0xFFDE8A62,
      light: PaletteNeutrals(
        bg: 0xFFF2F5F6,
        surface: 0xFFE4EAEC,
        raised: 0xFFD7E0E3,
        text: 0xFF18242F,
        muted: 0xFF5E6F7B,
      ),
      dark: PaletteNeutrals(
        bg: 0xFF0E151C,
        surface: 0xFF162029,
        raised: 0xFF1F2B36,
        text: 0xFFE6EDF0,
        muted: 0xFF8DA0AC,
      ),
    ),
    IdentityPalette(
      id: 'ember',
      name: 'Ember',
      mood: 'Charcoal, a banked fire and warm ash.',
      tile: 0xFF1D1715,
      form: 0xFF8E3E28,
      stroke: 0xFFF1C886,
      accent: 0xFFE8692F,
      light: PaletteNeutrals(
        bg: 0xFFF7F2EE,
        surface: 0xFFEEE5DE,
        raised: 0xFFE4D8CE,
        text: 0xFF2A1C17,
        muted: 0xFF7C675D,
      ),
      dark: PaletteNeutrals(
        bg: 0xFF141010,
        surface: 0xFF1F1918,
        raised: 0xFF2A2220,
        text: 0xFFF2E6DA,
        muted: 0xFFA8968A,
      ),
    ),
  ];

  static final _byId = {for (final p in all) p.id: p};

  /// The palette called [id], or the default for an unknown one.
  static IdentityPalette byId(String? id) => _byId[id] ?? _byId[defaultId]!;

  static IdentityPalette get fallback => byId(defaultId);
}
