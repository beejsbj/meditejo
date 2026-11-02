# Practice figures, round 2

Burooj on round 1 (2026-11-02): the varied grounds stay; figures are abstract, quiet and graceful on a slow ~10 s breath, and say something true about the practice; **no human silhouettes**.

Round 2 redraws Insight Dialogue, Noting, Effortless mindfulness, Kāyagatāsati, Prāṇa · Qì, Focusing, Yoga nidrā and the Headless Way. It also splits the two shared tiles into Dzogchen / Mahāmudrā and Trāṭaka / Kasiṇa. Each practice has two or three variants. Nothing in the app has changed.

## Files

- `figures-r2.js`: the new figures (`PracticesR2`), in `figures.js`'s contract: `{ label, says, build(r, place), draw(ctx, p, k, t, still) }`. It has its own copies of the small helpers, so it stands alone for porting.
- `r2.json`: per practice, round 1's tile (`was`), the variants (figure and ground), and `pick`, the variant I'd ship. It also lists the `flags` (round 1 figures worth revisiting) and the `fixes`.
- `figures.js`: two small fixes to round 1.
  - The ensō's tail keeps a visible width.
  - Open awareness's clouds are soft veils, not dark ellipses.
- `app-r2.js`, `page-r2.html`, `r2-recommend.html`: the comparison page.
- `build_r2.py`: builds the page (same fonts and needs as `build.py`).
- `shoot_r2.mjs`: takes PNG stills, one per practice, plus `fixes` and a `sheet`.
- `check_r2.mjs`: the seam check. It paints every tile at 1/30 s steps for 60 s and ranks each one's biggest frame-to-frame change against its usual change. A pop shows as a lone spike.

```sh
python build_r2.py --out /tmp/meditejo-runbooks/practice-figures-r2.html
node shoot_r2.mjs /tmp/meditejo-runbooks/practice-figures-r2.html /tmp/meditejo-runbooks/practice-figures-r2
node check_r2.mjs /tmp/meditejo-runbooks/practice-figures-r2.html
```

## Rules the figures keep, for the Dart port

- **No canvas filters.** Soft edges and blur are radial gradients (`soft`, `softE`, stacked blob fills), as the Dart engine draws them.
- **No hard switches.** A colour change at a threshold is a pop, so inks change by `mix` on a smoothstep.
- **Only what `canvas2d.dart` has:** `arc`, `ellipse`, `roundRect`, clipping, `setLineDash`, and linear and radial gradients.
- **Kinship is shared form.** Dzogchen and Mahāmudrā share `clearDisc`. Trāṭaka and both flame figures share `tear` and `closeIn`, the dark closing in from the edges that stands for closed eyes, with no eyes drawn.
- **Kasiṇa's fire reuses `Prims.fire`** (round 4), seen through the hole in the mat.

## Open

- **The category split.** `assets/categories/categories.json` still has one `dzogchen` and one `gazing` category. Splitting them is Burooj's call, and an app change.
- **Flagged, not redrawn.** See `flags` in `r2.json`: Caṅkama's footprints (the last people-shape), Forgiveness, TMI, Anussati, Karuṇā's still, and Jhāna's still.
