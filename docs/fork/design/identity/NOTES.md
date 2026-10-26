# Identity exploration: notes

`mark-explore.html` is round 1 and `round2/identity-round2.html` is round 2 (see [Round 2](#round-2) below). Both pages are built, so do not edit them by hand.

- **Sources:** `generator.js` (the marks), `page.html` (the page) and `curated.js` (the opening seeds).
- **Build:** `node build.mjs` inlines the three into `mark-explore.html` (about 65 KB, with no external resources).
- **Screenshots:** append `?t=7` to start every mark 7 s in.

Nothing here touches the app. Burooj picks a seed and a palette first; the Flutter port and the launcher icon come after.

## Seeds

A seed is `<family>-<anything>`: `g-` is gesture on form, `a-` is atmospheric and `m-` is minimal. The whole string seeds a mulberry32 PRNG, so the same seed always draws the same mark. **Changing the order of `rng` calls in `generator.js` changes what every seed draws.** Once a seed is chosen, export its built geometry (below) rather than relying on the generator staying frozen.

## Families and the parameters that matter

**Gesture on form**, the Duet direction: a pebble (`makeBlob`) with one hand-drawn stroke (`makeStroke`) over it.

- **Pebble:** a polar curve, `r(θ) = R · (1 + Σ aₖ sin(kθ + φₖ))` for k = 2, 3, 4, with an aspect ratio and a rotation. R is 0.27 to 0.32 of the tile, and the pebble sits up to 0.055 off centre.
- **Stroke:** a centreline is resampled by arc length and given a slow wobble across the line (about 0.004). Its width follows a profile:
  - *marker*: blunt start, slight lift at the end;
  - *brush*: heavy landing, dry tail (the ensō);
  - *grow*: thin at the centre (the spiral);
  - *swell*: the wave.

  On top of the profile go ±13% pressure noise and an optional nib angle. Base width is 0.038 to 0.05 of the tile.
- **Centrelines:**
  - *loops*: a prolate trochoid, `x = t + d·sin t`, `y = −h(1 − cos t)/2`, with d 2.3 to 3.2 and h 4.4 to 5.8, eased in from a flat lead and out into a rising exit. This is the "ee";
  - *ensō*: an open circle of 300° to 340°;
  - *breath wave*;
  - *spiral*;
  - *arches*: a cycloid, the quiet "m";
  - *infinity*: an open lemniscate.
- **Drawing:** the ribbon is one polygon (left edge out, right edge back) filled nonzero, plus two round caps. Crossings stay solid and loop holes stay open.
- **Safe zone:** the composition is scaled until every point lies within 0.44 of the centre, which keeps it inside the adaptive icon's 66 dp safe circle.

**Atmospheric:** five scenes, each with one clear silhouette.

- *sunrise*: a disc over a horizon, with reflection bars;
- *mist*: three or four ridges, back layers pale and front layers deep, with light pooling above each ridge;
- *halo*: an orb with a glow and an ensō ring;
- *veil*: overlapping translucent discs, multiplied on light tiles and screened on dark ones;
- *ripple*: a moon over water, with rings opening.

Every scene gets a 128 px grain tile, overlaid at 7 to 8.5%. Colours are mixed from the four roles: the sky runs tile → accent, and depth comes from the darker of tile and stroke.

**Minimal:** two or three flat shapes, cut slightly by hand (`rough` 0.15 to 0.4 scales the pebble harmonics). The shapes are split sun, arch, pebble and bindu, crescent (an even-odd cut), vesica (a clipped intersection) and cairn.

**Motion:**

- **Gesture:** the form fades and grows in over 1 s. The stroke draws from 0.5 s over 2.1 to 3.6 s, eased in and out on a pen clock that slows in tight curves (cost = arc length + 0.014·|turn|).
- **Breathing:** 10 s per breath, six a minute, as the current mark does. The form scales by 2.8% and slowly morphs; the stroke lifts by 0.6%.
- **Reduced motion:** draws the settled frame (`o.still`).

**Palettes:** each has four mark roles (tile, form, stroke, accent) plus UI neutrals for light and dark (bg, surface, raised, text, muted). On the app's own background the mark has no tile, so a stroke under 2.2:1 contrast with the background switches to the text colour. Lagoon needs this in light mode and Clay in dark.

## Porting a chosen seed

1. **Freeze the geometry.** Run `MarkGen.build(seed)` once and dump the resampled stroke (`x`, `y`, `nx`, `ny`, `w`, `cost`; 420 samples) and the pebble parameters as Dart constants, in the way `mark_geometry.dart` keeps its constants now. Don't port the PRNG.
2. **CustomPainter.** `draw()` already speaks Canvas:
   - the pebble is a `Path` of 120 `lineTo`s;
   - the stroke is one `Path` (`PathFillType.nonZero`) plus two `drawCircle` caps;
   - a partial draw finds the sample where `cost[i] ≤ p` by binary search;
   - gradients map to `ui.Gradient.linear` and `ui.Gradient.radial`;
   - the even-odd cut is `PathFillType.evenOdd`;
   - multiply and screen are `BlendMode.multiply` and `BlendMode.screen`;
   - grain is an `ImageShader` with `BlendMode.overlay`.

   Reuse paths and paints across frames, as `MeditejoMarkPainter` does now, and drive it from the existing 60 s loop: breath is `0.5 − 0.5·cos(2π·6t)`.
3. **Adaptive icon.**
   - **Background layer:** the tile colour (a gradient drawable for atmospheric marks).
   - **Foreground:** the settled frame as a vector drawable, 108 dp viewport, with the mark scaled into the central 72 dp and kept inside the 66 dp circle. The page previews it at 0.9 content scale.
   - **Android 13 themed icon:** a `<monochrome>` layer of one silhouette. For gesture marks use the stroke alone, or the pebble with the stroke knocked out.
   - **Generation:** export the SVG from the frozen path, then run `scripts/regenerate_icons.py`.

## Round 2

Round 2 lives in `round2/`; `node round2/build.mjs` builds `identity-round2.html`.

- **Sources:**
  - `core.js`: randomness, colour, the stroke engine, breathing shapes and the print finish;
  - `marks.js`: marks, palettes and the daily pick;
  - `art.js`: sound scenes, presets and covers;
  - `page.html` and `curated.js`: the page and its opening seeds.
- **Round 1 seeds still work** in round 1's page. Round 2 seeds are a separate namespace: every round 2 seed is hashed with an `r2:` prefix.

### Breathing and place

- **Breathing:** every round shape is the pebble curve with its harmonics scaled by `imperf = 1 − breath`. At full inhale it is a true circle; on the exhale it relaxes into its organic shape. One breath takes 10 s, as the current mark does. The stroke stays still once it has drawn.
- **Gesture kinds:** each kind places its pebble with its line, so the two read as one place:
  - doorway, shelter, seat line ("cushion"), horizon with one loop, hearth curl, path home, window and threshold;
  - the round 1 kinds (ensō, breath wave and the double loop) stay at a low weight. The double loop is about 2% of draws.
- **Minimal:** adds window, hearth, clearing, cushion and shelter.

### Daily marks and pinning

- **Today's mark** comes from the local date: `daily(date)` hashes `day:YYYY-MM-DD` to pick a family (gesture 45%, minimal 40%, atmospheric 15%), and the seed is the date itself, e.g. `m-2026-10-26`.
- **Daily palette:** walks one fixed shuffle of the palettes a day at a time, so no palette repeats within nine days and nothing has to be stored.
- **Two independent settings:**
  - mark: `daily` or `pinned(seed)`;
  - palette: `daily` or `fixed(id)`.

  Today's mark is the pinned one if there is one, otherwise the daily one. Pinning a mark doesn't fix the palette, and the other way round.
- **Store a pin as frozen geometry, not only as a seed:** the stroke's 420 samples (x, y, nx, ny, w and cost) plus the pebble parameters come to about 7 KB of JSON. The generator will keep changing; a pinned mark must not.
- **Changing the day:** the app recomputes at local midnight (a timer to the next midnight) and on resume.
- **The launcher icon stays fixed.** Android can only swap icons through activity aliases that ship with the app, and each swap restarts the launcher entry. Choose one house mark for the icon; the daily mark lives inside the app.

### Palette as the app's theme

A palette has four mark roles (tile, form, stroke, accent) and neutrals for light and dark (bg, surface, raised, text, muted). In `lib/constants/theme/tokens.dart`, `MeditejoColorTokens.seed` becomes the active palette:

- **Accent ramps:** build the scheme with `ColorScheme.fromSeed(seedColor: palette.form, dynamicSchemeVariant: tonalSpot)`, then set `tertiary` from `accent`.
- **Neutrals:** overwrite the neutral roles from the palette, so they stay exactly as designed: `surface` = bg, `surfaceContainer` = surface, `surfaceContainerHigh` = raised, `onSurface` = text, `onSurfaceVariant` = muted.
- **Mark colours:** a `ThemeExtension` (`MeditejoPalette`) carries the four mark roles to the mark and art painters.
- **Switching:** a provider holds the mode (daily or fixed). The theme switch animates with `AnimatedTheme` over 400 ms, using the existing `MeditejoMotion.medium`.
- **On the app's background** the mark has no tile, so a stroke under 2.2:1 contrast switches to `onSurface`. This already happens in the page.

### Art generators in Flutter

- **Generators:** one `CustomPainter` per kind, each taking the seeded geometry and a `MeditejoPalette`:
  - `CoverPainter(kind, id)` for courses, playlists, teachers and singles;
  - `SoundScenePainter(soundId)` for sound cards;
  - `PresetPainter(layers)`, which paints the loudest layer's field, then every layer's elements at their volumes.
- **Seeds:** use FNV-1a over the ID, as `GeneratedArtwork.hash` already does, then a small PRNG (port mulberry32 with 32-bit masking so the results match the page).
- **Covers are static.** Paint once into a `PictureRecorder` and call `toImage` at display size × device pixel ratio. Keep the result in an LRU keyed by (kind, id, palette, size), and drop it when the palette changes. This replaces `GeneratedArtwork`.
- **Sound cards move.** Each card gets its own `RepaintBoundary`, driven by a 30 fps ticker. It pauses off screen (`VisibilityDetector` or the scroll position), when the app is in the background, and under reduced motion, where it draws a single frame.
- **Print finish:** one 256 px paper texture and one speckle texture per palette, used as `ImageShader`s (overlay and source-over). They are made once at start-up.

**Rough cost on a mid-range phone.** These are estimates from the page's drawing work, not measurements; measure in a profile build before relying on them.

| Item | Paint | Memory |
|---|---|---|
| A cover, painted once at about 450 px | 1–3 ms | about 0.8 MB as a 3× raster; a 60-entry LRU at 2× is about 25 MB |
| One frame of an animated sound card | 0.3–1 ms | |
| Six visible sound cards at 30 fps | 2–6 ms a frame, comfortably inside budget | |

Rain (70 lines) and café (18 radial gradients) are the heaviest sound cards. Fire and noise are the cheapest.

## Round 3: the art primitives

Round 3 lives in `round3/`; `node round3/build.mjs` builds `identity-round3.html`, reusing round 2's `core.js` (randomness, paper and ink) and its palettes.

- **Primitives** (`prims.js`): 22 small generators, each `build(rng, place, slot)` then `draw(ctx, params, inks, t, still)`: breath, fire, rings, mandala, strata, horizon, streaks, waves, scales, constellation, lotus, ammonite, cairn, threads, weave, moon, dot rhythm, cut-paper hills, sun and rays, stack, grove and disc. Each has one quiet motion. Those that can fill a card behind another are marked `ground`.
- **Grammar** (`compose.js`): a card is paper (light, mid or dark), then up to one ground, one figure and up to one accent on a second, misregistered plate. The seed picks structure first: value key, layout (centre, low, left, right or big), which primitives. Then each primitive gets its own seeded parameters. A meaning map per sound kind and cover kind lists the primitives allowed in each slot. A preset keeps its loudest layer's card and adds the quieter layers' figures as accents.

### Port

- **One `CustomPainter` per primitive.** Each takes a frozen parameter object built from the seed, an `Inks` value (paper, main, alt, line, glow) and `t`. Drawing is plain `Path`, `drawCircle`, `drawArc` and gradients, as in the page; the hand-cut edge is the same polygon roughening as round 2's `cutPoly`.
- **A pure composition function:** `compose(kind, id) → Composition { paperKey, layout, layers: [(primitive, slot, params)] }`. Seed it with FNV-1a over `kind:id` and the mulberry32 PRNG, as round 2 notes, so a course keeps its cover. Keep the meaning maps as a constant table beside it. `CardPainter` paints paper, then each layer (the accent with an offset and `BlendMode.multiply` on light paper or `screen` on dark), then the shared paper and speckle shaders.
- **Lists use a raster cache.** Draw the still frame once into a `PictureRecorder`, call `toImage` at display size × device pixel ratio, and keep it in an LRU keyed by (kind, id, palette, size). Covers are always still.
- **Motion only where it is seen.** Live sound cards repaint at 30 fps from one ticker, behind a `RepaintBoundary`. They stop off screen, in the background and under reduced motion, which falls back to the cached still.
