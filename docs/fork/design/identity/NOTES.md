# Identity exploration, round 1: notes

`mark-explore.html` is the page to look at; it is built, so do not edit it by hand.

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
