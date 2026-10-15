<!-- Scout report, 2026-10-15 (Sonnet subagent; repo via gh api, upstream licence pages checked; audio not auditioned). -->

I read the repo through `gh api` (including the git history), the upstream Freesound, Free Music Archive, NPS and Acoustic Atlas pages, and `blankie.rest/credits`. I did not download any audio or compare files by ear. Page contents came through WebFetch summaries, except the Acoustic Atlas rights line, which I confirmed with raw curl.

## 1. Sound inventory (24)

All files are `Blankie/Resources/Sounds/<file>.m4a` (AAC; `scripts/blankifi.swift` transcodes to 44.1k stereo at 192 kbps). The metadata is in `Blankie/Resources/sounds.json`, and durations are the bundled loop lengths.

**Inherited from Blanket (14).** Sizes are in MB.
- rain, 92s, 2.3: alex36917, CC BY 4.0, freesound 524605
- storm, 26s, 0.6: Digifish music, CC BY 4.0, freesound 41739
- wind, 211s, 5.1: felix.blume, CC0, freesound 217506
- waves, 115s, 2.9: Luftrum, CC BY 4.0, freesound 48412
- stream, 148s, 3.7: gluckose, CC0, freesound 333987
- birds, 128s, 3.2: kvgarlic, CC0, freesound 156826
- summer-night, 47s, 0.9: Lisa Redfern, "Public Domain", SoundBible
- train, 568s, 1.5: SDLx, CC BY 3.0, freesound 259988. Blankie re-cut it into a longer loop.
- boat, 41s, 0.8: Falcet, CC0, freesound 439365
- city, 21s, 0.6: gezortenplotz, CC BY 3.0, freesound 44796
- coffee-shop, 13s, 0.4: stephan, "Public Domain", SoundBible
- pink-noise, 20s, 0.8
- white-noise, 20s, 0.9
- fireplace, 26s, 0.7

These are only partly inherited. Blanket's two noise files were Wikimedia CC BY-SA, and its fireplace was SoundBible "ezwa" (public domain). Blankie replaced all three, so they count as new below (source: Blanket's `SOUNDS_LICENSING.md`).

**New in Blankie (10 sounds, plus 3 replacements).** The changelog 2.0.0 says "Ten new built-in sounds". The first four rows are the noise files and fireplace.
- pink-noise and white-noise: "Blankie", CC0, self-generated with Python/numpy (per `sounds.json`)
- brown-noise (titled "Deep Noise"), 19.7s, 0.86: "Blankie", CC0. It is numpy cumulative-sum noise with a 15 Hz high-pass and 400 Hz low-pass.
- green-noise, 9.0s, 0.42: "Blankie", CC0. It is pink noise band-passed 120–600 Hz.
- fireplace, 26s: "NPS & MSU Acoustic Atlas", claimed Public Domain
- ambient-music ("Ambient Synth"), 158s, 3.8: ChristmasKrumble666, CC0, freesound 742808
- acoustic-guitar, 124s, 3.0: yunclas, CC0, freesound 653928
- fan, 66s, 1.6: LilMati, CC0, freesound 515859
- lo-fi-beats, 120s, 2.8: Holizna, CC0, Free Music Archive (track "Laundry On The Wire")
- forest, 52s, 1.3: sinewave1kHz, CC0, freesound 202989
- airplane, 55s, 1.0: ikbenraar, CC0, freesound 133496
- laundry-room, 32s, 0.8: moviebuffgavin, CC0, freesound 411914
- warm-piano, 132s, 2.6: Cody Bromley, CC0, freesound `blankie.rest/sounds/859607`

## 2. Licence verification

**Verified.** The upstream page matches the claim exactly (CC0, same uploader and title) for:
- 742808 (3:34 original), 653928 (3:10), 515859 (1:11), 202989 (1:34, recorded in Croatia), 133496 (1:01, Boeing 777)
- 411914 (0:33), 859607 (1:56, uploaded 2026-06-21 by the Blankie account)
- the Free Music Archive track, which states "CC0 1.0 Universal" and "AI generated: No"

**Mismatch: fireplace.**
- The NPS page (`nps.gov/media/video/view.htm?id=1E69FA23-…`) is credited "NPS & MSU Acoustic Atlas". It says media credited to any entity other than NPS "must not be presumed to be public domain".
- The Acoustic Atlas item (`https://acousticatlas.org/item/2513`) is by Jennifer Jerrett. Its audio rights are **CC BY-NC 4.0**, and it was shared with the NPS Yellowstone Sound Library.
- So Blankie's "Public Domain" label is very likely wrong. This is the main finding. Skip it.

**Unverifiable or weak.**
- **Noise files:** the generation script is not in the repo (`gh search code` for "numpy" finds only the `sounds.json` descriptions). CC0 is credible, because algorithmic white and pink noise carries essentially no authorship, but nobody has audited it. Deep and Green Noise are filtered noise, not true brown or green, but CC0 still holds. It makes little difference, since we synthesise our own noise.
- **Lo-fi beats:** the Free Music Archive page does not say whether the track contains third-party samples. Reasonable, but not provable.
- **Ambient Synth:** the CC0 label matches. The description says it is a collage layered with field recordings, so third-party material inside it can't be ruled out.
- **Warm piano:** the bundled loop (132s) is longer than the Freesound original (116s). The README says "composed for Blankie", while the Freesound page says "commissioned". The commit "fix license for warm-piano" shows a prior mislabel.
- No "CC0 without a link" cases remain apart from the noise files and the piano, which link to Blankie's own pages.

## 3. Repo licence and credits

- **Code:** MIT. The name, logo and icons are all-rights-reserved. The README says sounds are under "various open licenses (see credits)". There is no separate sounds licence file.
- **Data structure:** `SoundCredit`, a `License` enum (cc0, ccBy3, ccBy4, publicDomain, custom, fairUse, allRightsReserved, each with a canonical URL) and `SoundCreditsManager` all read from `sounds.json`. Each entry carries author, authorUrl, soundName, soundUrl and license. `Blankie/credits.json` holds translators, testers and dependencies. The website renders `blankie.rest/credits`, where titles link to the source, authors to their profiles and licences to the official pages. Custom imports get their own credit fields.
- **Reusable:** the schema idea carries over to a Flutter app. I'd add `licenseVerifiedOn` and the uploader's original URL. Don't copy the Swift.

## 4. Features and UX

- **Beyond Blanket:** custom imports with loudness matching, favourites, Quick Mix, "music loop" tagging (only one plays at a time), and a sleep timer with add-time.
- **Also new:** menu bar, CarPlay, Control Center and AirPods controls, space and arrow keyboard shortcuts, experimental spatial audio, animated lock-screen artwork, and exportable `.blankie` presets.
- **Per-sound settings:** fade in/out, loop and randomise start.
- **Normalisation:** documented in `docs/Sound_normalization.md`. It uses BS.1770-4 integrated loudness with a **-27 LUFS target**, true-peak protection at -1 dBTP, and a tanh soft limiter. Per-sound `lufs`, `truePeakdBTP` and `normalizationFactor` are stored in `sounds.json`.
- **Gapless looping:** `Blankie/Managers/Audio/SoundPlayer.swift` fully decodes files of 90 s or less into one buffer and loops it with `AVAudioPlayerNode` `.loops`. Longer files stream in chunks. Loops are cut and crossfaded offline (`loopCut` records the method and crossfade length).
- **Not present:** binaural beats (issue #22 is open) and bell cues. "Stacks" and "Dynamic Volume" are planned but not built (#103, #104).

## 5. Activity and health

- 383 stars, 9 forks, 9 open issues, and 18 releases (v2.0.2 on 2026-06-28).
- The last push was **2026-10-15**, so it is very active, and it is effectively a solo-maintainer project.
- There are no open sound or licence issues. The closed ones are #34 (clicks and gaps at loop seams) and #76 (train loop too short).
- The upshot: loop seams were a repeated problem, which supports baking crossfades into assets.

## 6. Recommendation

**Safe to take (verified CC0).** CC0 needs no attribution, so these are courtesy lines in the form `"<title>" by <author>, CC0 — <url>`.
1. Warm Piano: `"Sleepy Upright Piano Seamless Loop" by blankie.rest (Cody Bromley), CC0 — https://freesound.org/people/blankie.rest/sounds/859607/`. Use the Freesound original, not the m4a.
2. Forest: `"Wind_pine.wav" by sinewave1kHz, CC0 — https://freesound.org/s/202989/`
3. Fan: `"Air Conditioner Fan Hum.wav" by LilMati, CC0 — https://freesound.org/s/515859/`
4. Airplane: `"Interior airplane.WAV" by ikbenraar, CC0 — https://freesound.org/s/133496/`
5. Laundry Room: `"Laundry Room Ambience.wav" by moviebuffgavin, CC0 — https://freesound.org/s/411914/`
6. Ambient Synth (a drone, good for meditation): `"Couple' Morning.wav" by ChristmasKrumble666, CC0 — https://freesound.org/s/742808/`
7. Gentle Guitar (open D): `"acoustic guitar in open D" by yunclas, CC0 — https://freesound.org/s/653928/`

Take these from the Freesound originals, which are the lossless source. Blankie's m4a files are re-cut AAC and add nothing.

**Skip.**
- **Fireplace:** CC BY-NC 4.0, which conflicts with our needs.
- **Lo-fi beats:** it is a beat, not meditation material, and sample provenance is unconfirmed.
- **Blankie's noise files:** we synthesise noise ourselves.
- **All inherited CC BY sounds:** these need attribution lines, and they are available from Blanket anyway.

**Design ideas, ranked.**
1. Licence-as-data: a `sounds.json` with a `License` enum, canonical URLs, and a credit sheet auto-built from it.
2. Store loudness metadata per sound and normalise to one target (about -27 LUFS), with a true-peak guard.
3. Bake loop crossfades offline and record them as `loopCut` metadata.
4. Tag music-like layers so only one plays at a time.
5. Per-layer fade in/out.
6. A "Dynamic Volume" swell for the layers (#103, which they haven't built).

**Inference to confirm.** If we want the Warm Piano, check that the Freesound upload is the same piece as the shipped loop. I couldn't verify the audio, only the page.
