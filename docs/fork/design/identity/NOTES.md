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
- **A pure composition function:** `compose(kind, id) → Composition { paperKey, layout, layers: [(primitive, slot, params)] }`. Seed it with FNV-1a over `kind:id` and the mulberry32 PRNG, as round 2 notes, so a course keeps its cover. Keep the meaning maps as a constant table beside it. `CardPainter` paints paper, then each layer (the accent with an offset and `BlendMode.multiply` on light paper or `screen` on dark), then one baked finish raster.
- **Lists use a raster cache.** Draw the still frame once into a `PictureRecorder`, call `toImage` at display size × device pixel ratio, and keep it in an LRU keyed by (kind, id, palette, size). Covers are always still.
- **Motion only where it is seen.** Live sound cards repaint at 30 fps from one ticker, behind a `RepaintBoundary`. They stop off screen, in the background and under reduced motion, which falls back to the cached still.
- **Bake the print finish.** Grain, speckle and vignette go into one transparent image per (paper colour, size), drawn with a single `drawImage`. Redrawing round 2's overlay pattern fills on every frame held a page of live cards to 7–11 fps in the browser, against 34–62 fps with the baked raster. Expect the same proportions on a phone.

## Round 4: atmosphere, a tight map, curation

Round 4 lives in `round4/`; `node round4/build.mjs` builds `identity-round4.html` from round 2's `core.js` and palettes and round 4's own sources:

- `grounds.js`: the ten grounds;
- `prims.js`: the seventeen figures;
- `compose.js`: the meaning map, the candidates and the frozen form;
- `shipped.js`: everything Meditejo ships;
- `export.js`: the `curated_art.json` format.

### Rules (decision 22)

- **Shipped items are curated.** Every built-in sound (30 from PR #41 plus the five synth layers), the five starter presets and the starter set (six courses and one single) has a hand-picked card. That is 47 items, all in `curated_art.json`.
- **Everything a person adds, imports or creates is generated** from its id by the same map.
- **Dharma Seed's Explore rows aren't a fixed list.** They show recent retreats and the teachers behind them, so they follow the course and teacher rules. A teacher's own photo, when there is one, wins.

### Grounds and figures

- **Grounds (10).** Round 2's atmospheres become grounds: paper, mist, dawn, rain field, canopy, night field, hearth glow, sea, room bokeh and texture (noise only).
- **Figures (17):**
  - breath, fire (tongues or embers), rings (ripple, target or interference), mandala;
  - streaks, waves, scales, star shape;
  - lotus, ammonite, cairn;
  - threads, grass, flock, petals;
  - moon, disc (plain, halo or rayed).
- **Dropped from round 3:** dot rhythm, strata, stack, grove, weave, the moon row, and the sun as its own figure (it is now the disc's rayed kind).
- **The star shape** places bright stars to suggest a dipper, a W, a cross, a swan, a lotus or a ring, with faint companions around them. Nothing joins the stars.
- **Motion:** every ground and figure moves slowly and loops without a seam. Motion is a sine of time, or a phase that wraps while the element is faded out. The breath-paced figures use the 10 s breath. Reduced motion draws a still frame.

### The meaning map

Only these may meet. A variant after a colon is pinned.

| Class | Ships as | Grounds | Figures | Accents |
|---|---|---|---|---|
| Rain | the six rain sounds | rain field, mist | streaks, rings:ripple, disc:halo | none, disc |
| Stream and river | Mountain stream, River | mist, paper | waves, threads | none |
| Forest brook | Forest brook | canopy, mist | waves, threads | none, flock |
| Sea | Small waves, Beach at Dellec, Gentle ocean | sea, dawn | disc, flock, scales | none, flock |
| Wind | Wind in an open field | mist, dawn | threads, grass | none, flock |
| Wind in the pines | Wind in the pines | canopy, mist | threads | none, flock |
| Birds | Forest birds, Dawn chorus, Evening birds, Wood thrush | canopy, dawn | flock, petals | none, disc |
| Fire | Crackling fire, Wood stove | hearth glow | fire:tongues, fire:embers | none |
| Rooms | Quiet house, Café, Laundry room | room bokeh, paper | disc:halo, breath, rings:target | none |
| Fan | Fan hum | paper, mist | mandala, rings:target | none |
| Trains | Metro carriage, Yamanote Line train | night field, room bokeh | threads, disc:halo | none |
| Night | Night insects | night field | star shape, moon | none, star shape |
| Frogs | Frogs by a pond | night field | rings:ripple, moon, star shape | none, star shape |
| Crickets by the sea | Crickets by the sea | night field | waves, moon, star shape | none, star shape |
| Meadow at night | Meadow at night | night field | grass, star shape, moon | none, star shape |
| Noise | White, pink, brown | texture (tinted by colour) | none | none |
| Drone | Drone | night field, mist | rings:target, mandala, breath | none |
| Binaural | Binaural beats | paper, night field | rings:interference | none |
| Courses | starter courses; retreats by rule | dawn, mist, paper | mandala, lotus, cairn, ammonite, disc:rayed, breath | none, disc, star shape |
| Singles | the starter single; talks by rule | paper, mist | disc, breath, lotus, rings:ripple, ammonite | none |
| Teachers | by rule (a photo wins) | paper | mandala, lotus | none |
| Playlists | by rule | paper, mist | cairn, scales, mandala, rings:target | none |
| Presets | the five starters | the loudest layer's ground and figure | | the next layer's figure |

Fire is always drawn in warm inks, whatever the palette's form colour.

### Curation and port

- **Candidates.** Each item gets eight candidate compositions from its row of the map, seeded `id#0` to `id#39`. They are chosen to cover as many different (ground, figure) pairs as the row allows.
- **Choosing.** The page's curation view lets Burooj change any pick and export the file.
- **The first pass:**
  - `picks.json` holds the chosen candidate index for every item;
  - `node round4/curate.mjs` freezes them into `curated_art.json`: for each item, its ground, figure and accent with their variants, layout, seeds and every numeric parameter;
  - the page's export writes the same file byte for byte.
- **In the app, ship `curated_art.json` as an asset.** Painters read the frozen params for shipped items and never re-derive them, so later generator changes can't alter what ships. Anything else calls `compose(kind, id)` with the same map.
- **Painters:** one `CustomPainter` per ground and per figure, plus `CardPainter` (ground, then figure, then the accent with a small offset and `multiply` on light grounds or `screen` on dark ones, then the baked finish).
- **Lists, motion and cost:** as in round 3. Lists use a raster cache; motion runs only where it's seen, at up to 30 fps, and stops under reduced motion.

## Round 5: places and bells

Round 5 lives in `round5/`; `node round5/build.mjs` builds `identity-round5.html`. It loads round 4's `grounds.js`, `prims.js` and `shipped.js` unchanged, then its own sources:

- `places.js`: the new grounds and figures, the bell figure and the noise colours;
- `compose.js`: round 4's composition, plus place classes, ground variants and bells;
- `export.js`: the `curated_art.json` format, now with bells;
- `bell_params.py` → `bells.json`: each shipped bell's sound, read from the generator;
- `bellsynth.js`: a browser sketch of the bell sound, for the bell maker.

### New grounds and figures

- **Grounds (6):**
  - window (rain beads and trickles on the glass, with the room's light behind);
  - balcony (a railing against the city, in rain or at dusk);
  - terrace, its own place, in two variants: `tiles` (looking down on wet stone or terracotta, puddles with rain rings opening and closing, one or two potted plants with leaves stirring) and `eave` (under the eave, drops beading and running off its edge in a line onto the wet floor, a garden beyond in the rain);
  - car (the windscreen's curve, with drops beading and sliding);
  - metro (a window band with lights streaming past, and a pole; the carriage sways);
  - room (a wall, a floor and a lamp's warm pool).
- **Figures (10):** lamp (table or pendant), window (with rain or a moon), cup with steam, washing-machine porthole (turning), fan (turning blades behind a guard), umbrella, railing with drips, droplets, hanging straps (rings or triangles), and a doorway with light.
- **Weakest:** the room ground is plain on its own. It works as a backdrop for a figure, which is how the map uses it. The car ground reads as rain on dark glass more than as a car.

### Noise in its colour

The texture ground keeps its round 4 parameters, so nothing frozen changes; only its tone and grain are drawn differently:

- white is `#F3F1EC`, with a light multiply grain;
- pink is `#E6B3AA`, with an overlay grain;
- brown is `#4F3426`, with a heavier, coarser grain.

Each leans 18% toward the palette (its tile, accent or deep colour). The Stillness preset is mostly brown noise, so it now draws brown too, with its frozen entry unchanged.

### Bells: drawn from their sound

Each shipped bell is a preset of five controls. These are the same five a custom-bell editor (BJS-587) would expose, and the figure draws from them:

| Control | From the generator | Drawn as |
|---|---|---|
| pitch | Hz of the loudest mode | size relative to the family's preset; a bowl gets wider and deeper as it goes lower, and chime tubes get longer (a bar's pitch falls with its length squared) |
| bright | the upper modes' share of ring energy (a²τ) | body tone, rim colour and weight, the sheen down the body, the highlight |
| ring | the loudest mode's decay τ, in seconds | how long the motion lasts (0.45 + 1.25 τ s); how many ripples open, and how far they spread |
| strike | the strike's low-pass on a log scale, 300 Hz (soft) to 10 kHz (hard) | how far the mallet swings back and how hard the knock or sway is; how fast the tone blooms; the mallet head (a big felt head when soft, a small bare tip when hard) |
| shimmer | the loudest mode's beat, in Hz | the rim's flicker, at that very rate, with depth growing with it |

`bell_params.py` imports `tools/meditejo/generate_bells.py` (develop, eda420ae) and swaps its `render()` and `strike()` for recorders. It then runs each sound's build, so the numbers come from the generator itself rather than from a copy of its tables. The Swell bell is Medito's recording, so its modes are measured from `session_bell_v2.wav`. It has no mallet setting; its 1.2 s swell before the peak stands in for a soft strike (0).

| Bell | Family | pitch | bright | ring | strike | shimmer |
|---|---|---|---|---|---|---|
| Swell bell | swell | 221 Hz | 4% | 1.23 s | 0 | 0.24 Hz |
| Singing bowl, small | bowl | 640 | 20% | 1.05 | 0.51 | 0.91 |
| Singing bowl | bowl | 392 | 20% | 1.45 | 0.51 | 0.61 |
| Singing bowl, deep | bowl | 196 | 20% | 2.00 | 0.51 | 0.34 |
| Temple bell | temple | 196 | 50% | 3.20 | 0.24 | 1.30 |
| Hand bell | hand | 1318 | 21% | 1.20 | 0.85 | 1.10 |
| Chime | chime | 1568 | 6% | 1.70 | 0.97 | 0.70 |
| Tingsha | tingsha | 3120 | 12% | 1.60 | 0.97 | 5.50 |
| Wood block | block | 1180 | 18% | 0.03 | 0.70 | 0 |
| Wooden fish | fish | 520 | 7% | 0.12 | 0.46 | 0 |
| Gong | gong | 118 | 65% | 4.20 | 0.12 | 0.80 |

- **The family is the shape:** a swell bell with a halo, a singing bowl on its cushion with a mallet, a bonshō with a hung log, a hand bell, tubular chimes, tingsha (two cymbals face on, on one cord), a wood block, a wooden fish and a gong in its frame.
- **Each moves once, as its sound does:**
  - the bowl's rim shimmers as a glint runs round it;
  - the temple bell and the hand bell sway once;
  - the chimes swing and settle;
  - the tingsha meet edge to edge, part, and tremble at their 5.5 Hz beat;
  - the woods take one knock;
  - the gong's ripples open across its face and beyond.

  All of it starts at the strike (t = 0) and decays with the ring. At rest the bell is still: in lists, in the picker, and under reduced motion.
- **The bell maker** (page section 05) is BJS-587's prototype: start from any bell, move the five controls, and the card and the 40 dp icon redraw live; letting go strikes them. Its sound is `bellsynth.js`: the same modal model, starting from the preset's own modes and moved by the controls (pitch scales every frequency; ring scales every decay; shimmer scales every beat; brightness rescales the upper modes until their energy share matches; strike sets the noise burst's low-pass). It leaves out the fish's pitch glide and the gong's noise wash, so it's a sketch, not the shipped sound. What the editor would save is `{from, pitch, bright, ring, strike, shimmer}`.

### The meaning map, round 5

Round 5's place classes list (ground, figure) pairs, because a place only reads when the two belong together. Round 4's rows stay, with the same random draws, so round 4's curated items rebuild identically. Rain, Rooms, Fan and Trains now ship nothing directly: presets still read their layers through round 4's classes (`classOf(id, kind, true)`), so the curated presets don't move.

| Class | Ships as | Ground + figure pairs |
|---|---|---|
| Rain on a terrace | Rain on a terrace | terrace:tiles alone; terrace:tiles + droplets; terrace:eave alone; terrace:eave + streaks |
| Rain on an umbrella | Rain on an umbrella | rain field + umbrella; mist + umbrella |
| Rain at the window | Rain at the window | window + droplets; room + window |
| Rain on a car roof | Rain on a car roof | car + droplets; car + streaks |
| Rain from indoors | Rain from indoors | room + window; room + lamp; window + droplets |
| Rain on a balcony | Rain on a balcony | balcony:balcony + streaks; balcony:balcony alone; rain field + railing |
| Café | Café | room + cup; room bokeh + cup; room + lamp |
| Quiet house | Quiet house | room + doorway; room + lamp; room bokeh + doorway |
| Laundry room | Laundry room | room + porthole; paper + porthole |
| Fan hum | Fan hum | room + fan; paper + fan; mist + fan |
| Trains | Metro carriage, Yamanote Line train | metro + strap; room bokeh + strap; metro + threads |
| Bells | the eleven bells' cards | paper, mist, dawn or night + bell (pinned to the bell's controls) |
| Bell icons | the eleven bells' icons | paper, mist or night + bell, in the icon layout |
| Noise | White, pink, brown | texture, in the noise's own colour |

All the other rows are as in round 4.

### Curation and port

- **`round5/curated_art.json` supersedes round 4's.** It has 58 items:
  - 32 untouched items, which `curate.mjs` checks freeze byte-identically to round 4's;
  - 15 re-curated: the six rain sounds, Café, Quiet house, Laundry room, Fan hum, Metro carriage, Yamanote Line train, and the three noises (pink kept its round 4 candidate, which now draws pink);
  - 11 bells.
- **A bell's entry** is `{title, kind: "bell", asset, preset, knobs, pick: {card, icon}, card, icon}`. `card` and `icon` are frozen compositions like any other; `knobs` repeats the five controls the figure draws from.
- **The picks:** cards on varied grounds; every icon on the night ground, so the picker reads as one set. Changing that is one index per bell in `picks.json`.
- **In the app:**
  - `BellPainter` takes the family and the five controls, plus `t` since the strike.
  - It is still (t = 0, nothing struck) except for one play after a preview or a selection, lasting 0.8 + 3 × (0.45 + 1.25 × ring) s, capped at 16 s.
  - The icon is the same painter at 40 dp, in a 12 dp-radius rounded square, rasterised once per palette and redrawn only while it plays.
  - A custom bell (BJS-587) is the same painter fed the user's controls, so its art comes free.
- **The picker mock** (page section 06) shows the Customize bell list: Off, the eleven bells with their icons, and a "Design your own…" row for BJS-587. Choosing a row strikes its icon once.

### Follow-up: the terrace, reimagined

The first terrace was the balcony ground's `terrace` variant: a parapet against the same skyline, so the two read as one place. The terrace is now its own ground, `terrace`. Three ideas were tried, and all three are shown on the page (section 01, "Terrace, before and after"):

- **tiles, chosen:** looking down on wet tiles. Nothing else in the set is seen from above, which is what sets it apart.
- **eave, kept as a candidate:** the drip line is a good motion, but the garden beyond is plain.
- **court, dropped:** a walled roof garden at evening with a lamp. Its sky over a wall still reads as the balcony. The code stays in `places.js` for reference; no class uses it.

"Rain on a terrace" is re-picked to `rain-terrace#6`: terracotta tiles, two puddles and two potted plants, with no extra figure. The balcony ground's own `terrace` variant is no longer used but stays, so the field keeps its meaning in frozen params.

`curate.mjs` now runs two checks:

- every item round 5 doesn't re-curate must match round 4's freeze, as before;
- every item whose pick is unchanged must match this round's previous `curated_art.json`.

Only "Rain on a terrace" changed. The first pick's frozen entry is kept in `terrace_before.json` for the page's strip.


## Round 6: an M in the roof

Burooj picked B, the minimal shelter `m-2026-10-26`, as the app icon (beejsbj/meditejo PR #45, `fork/identity`). He then asked: what if the top corner bent inwards, making a subtle M? Round 6 lives in `round6/`; `node round6/build.mjs` builds `identity-round6.html` (24.5 KB).

### The fold

- **The slopes stay the shipped ones.** The roof is still `shelterRoofCommands`' two quadratic slopes and its 0.07 thickness. With a notch, each slope stops `nw` short of the centre (cut exactly with de Casteljau), and the apex folds down between those two shoulders.
- **The first try was wrong.** I first redrew each half as an arch rising to the old apex height. That turned the low gable into two round humps, a gull rather than a roof, so I dropped it. Folding the corner keeps B's silhouette and changes only its top.
- **The inside follows at the roof's thickness.** Its shoulders are on the shipped inner slope. Under a V, the inner notch is lower by the thickness across the V's arm (`0.07 × √(nw² + notch²) / nw`); under a round bottom, it is lower by 0.07.
- **Four optional numbers in `values`** (tile units; absent or 0 is B):
  - `notch`: how far the apex folds down below the shoulders;
  - `nw`: how far each shoulder sits from the centre;
  - `soft`: 0 for a sharp V, otherwise a dip with a round bottom, its curve reaching this far out;
  - `gap`: a hairline between the two halves, each cut square.

| Variant | notch | nw | soft | gap | File |
|---|---|---|---|---|---|
| B, as shipped | — | — | — | — | `marks/b.json` (identical to `house_mark.json`) |
| Whisper | 0.018 | 0.05 | — | — | `marks/m1-whisper.json` |
| Clear V | 0.045 | 0.065 | — | — | `marks/m2-clear.json` |
| Deep M | 0.075 | 0.08 | — | — | `marks/m3-deep.json` |
| Soft dip | 0.05 | 0.07 | 0.035 | — | `marks/m4-soft.json` |
| Split | 0.045 | 0.065 | — | 0.016 | `marks/m5-split.json` |

### Port: verified end to end

- **The JSON drops in as `assets/branding/house_mark.json`.** It uses the same format, seed and blob, with the new keys in `values`. `MarkSpec.decode` keeps unknown `values` keys, so nothing else changes.
- **`shelter_notch.patch` is required.** It teaches `shelterRoofCommands` (`lib/services/identity/mark_outline.dart`) to draw the fold. Without it the shipped code ignores the keys and draws B. With no notch it returns the shipped commands exactly, so B is unchanged.
- **`shelter.js` is a JS port of `blobOutline`, `shelterRoofCommands`, `settledOutline` and `house_mark.dart`'s icon mapping.** For B it reproduces the shipped `house_mark.svg`, `_glyph.svg` and `_square.svg` byte for byte.
- **The patch was checked on a throwaway worktree of `fork/identity` at 44b2fc6e:**
  - with the patch applied, `house_mark.dart` writes the same three SVGs as `freeze.mjs` for all six variants (18 files, byte for byte);
  - `make_icons.py` renders the split variant, the oddest path (two subpaths), into correct launcher PNGs;
  - `house_mark_test.dart` and `mark_reference_test.dart` pass (21 tests).
- **To ship one:** `git apply round6/shelter_notch.patch`, copy `round6/marks/<id>.json` over `assets/branding/house_mark.json`, then `uv run tools/meditejo/branding/make_icons.py`.
- **Home's mark** is `MarkPainter`'s minimal shelter with the same roof: the roof spreads once (`open`), then the pebble breathes between round and organic every 10 s. The page draws exactly that, on Tidewater's light and dark backgrounds; on dark, the roof takes the text colour.
- **The SVG comment still names the seed `m-2026-10-26`.** The fold is frozen values, not a new seed: `--freeze` would rebuild B.
