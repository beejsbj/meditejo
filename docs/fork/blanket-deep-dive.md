<!-- Scout report, 2026-10-14 (Sonnet subagent; repo/history/issues read via gh api; legal reading is inference). -->

I read the Blanket repo, history, issues and code through `gh api` and web fetches, and wrote no files. Upstream licence pages were read through a summarising fetch tool, so treat them as "verified, not eyeballed". The legal reading is my inference, not legal advice.

## 1. Sounds and licensing
The 14 files are in `data/resources/sounds/*.ogg` (Vorbis, stereo, 44.1 kHz except train at 24 kHz). They total 17.6 MB, from ffprobe on raw.githubusercontent URLs. Licences come from `SOUNDS_LICENSING.md`, with upstream Freesound pages re-checked.

| File | Size | Duration | Source and licence |
|---|---|---|---|
| birds | 3.06 MB | 130 s | kvgarlic, CC0, edited |
| boat | 0.64 MB | 41.6 s | Falcet, CC0, edited |
| stream | 5.03 MB | 145.5 s | gluckose, CC0, unedited per the table |
| wind | 0.29 MB | 14.8 s | felix.blume, CC0, edited (an extract of a 3:32 clip) |
| rain | 3.13 MB | 124.6 s | alex36917, CC BY 4.0, edited |
| storm | 0.49 MB | 25.7 s | Digifish music, CC BY 4.0, edited |
| waves | 2.77 MB | 118 s | Luftrum, CC BY 4.0, edited |
| city | 0.36 MB | 24.7 s | gezortenplotz, CC BY 3.0, edited |
| train | 0.13 MB | 7.2 s | SDLx, CC BY 3.0, unedited per the table |
| coffee-shop | 0.27 MB | 16.7 s | stephan, SoundBible, "Public Domain" |
| fireplace | 0.33 MB | 25.5 s | ezwa, SoundBible, "Public Domain" |
| summer-night | 0.61 MB | 49.3 s | Lisa Redfern, SoundBible, "Public Domain" |
| pink-noise | 0.20 MB | 10 s | Omegatron, CC BY-SA 3.0, **excluded** |
| white-noise | 0.32 MB | 20 s | Jorge Stolfi, CC BY-SA 3.0, **excluded** |

- **Licence mismatches.** `SOUNDS_LICENSING.md` just says "CC BY" for rain, storm, waves and city. Freesound says 4.0 for the first three and 3.0 for city. `doc/Sound_documentation.md` still lists the old train (vahid, CC Sampling+) and "Unknown" licences.
- **"Edited by Porrumentzio".** The footnote defines it as making the sound meet `CONTRIBUTING.md#sounds`. That means:
  - Ogg Vorbis format.
  - Gain changes plus a limiter to hit loudness targets: integrated about -27 LUFS (range -35 to -23), true peak at most -6 dBTP, loudness range 7 or more, max momentary LUFS -25.
  - Per-sound changes logged in `doc/Sound_documentation.md`: waves -2.5 dB with a -6.5 dB limiter, birds +12 dB, boat +20 dB, city +11 dB, rain +2 dB with a limiter, wind -9 dB, storm -7 dB.
  - Loop trimming. The commit "Fitted recently added sounds for loop" supports this, and shipped lengths are shorter than the Freesound originals (stream is 145.5 s against 156 s, waves 118 s against 120 s). The repo documents no crossfade, which is my inference.
- **Licence of the edited files.** No document states one.
  - `COPYING` is GPL-3 and covers code.
  - There is no AUTHORS, REUSE, LICENSES or NOTICE file.
  - The metainfo says `project_license GPL-3.0-or-later` and `metadata_license CC0-1.0`, which covers the metadata only.
  - `blanket.spec` has `%license COPYING SOUNDS_LICENSING.md`.
  - The Flathub repo holds only its manifest, with no licence statement.
  - Debian's `debian/copyright` lists each ogg under its upstream licence and never mentions Porrumentzio. It records pink and white noise as CC-BY-SA-3.0.
  - On 2026-05-12 the maintainer wrote in issue #360 that every sound is third-party and "all of the licenses allow commercial use, they just require attribution".
  - My reading is that each edited file stays under its upstream licence. Gain, limiter and trim are unlikely to create separate copyright, and Blanket never relicensed them as GPL.
- **AGPL compatibility.** GPLv3 §13 and AGPLv3 §13 govern combining code, so they don't apply here. The sounds are separate data that you aggregate with the app. Ship them under their own licences, mark them as excluded from the AGPL, and don't claim AGPL covers them.
- **Residual risks.**
  - CC BY 3.0 (city, train) has an anti-technological-measures clause (from memory, unchecked), which matters for DRM-wrapped stores.
  - The "Public Domain" labels on SoundBible are unverifiable user claims. Debian accepted them.
- **Cleaner route.** Take the originals from Freesound and redo the trivial edits yourself. That removes any dependence on Blanket's edited copies.

## 2. History
- Sounds were added on 2020-09-18 to 09-20: birds, waves, rain, train, stream, boat, city.
- No sound has been removed outright. There were four replacements:
  - Rain was replaced on 2020-09-18.
  - Wind on 2021-08-07 (`e5514530`).
  - Pink noise had its loop gap fixed on 2023-05-01 (PR #305).
  - Train changed to SDLx on 2023-09-03 (`391379d1`), because Debian rejected CC Sampling+ as non-free (#297).
- `SOUNDS_LICENSING.md` was created on 2021-02-22 after Debian asked for it (#85), and corrected on 2022-03-29 (#235: CC0 had been mislabelled for the Public Domain files).
- Sound-related issues:
  - Loudness spec: #20 (open).
  - Gap on looping: #111 (closed).
  - Rain artefacts: #231, #335 and #354 (open).
  - Short loops: #387 (open).
  - Brown noise: #112 (open).
  - Distant church bells: #376 (open).
  - Randomised or probabilistic playback: #81 and #397 (open).
- On master after the 0.8.0 release (2025-07-27) there are two changes. They are commits dated 2026-07-30 (single mixed pipeline) and 2026-08-18 (runtime noise generation). Both are post-release, which is inference from the release list.

## 3. Features, UX and loop engineering
- **Mixer model.** One GStreamer pipeline feeds an `audiomixer`. Each sound is its own branch (decode, convert, resample, volume), and the master volume uses GStreamer's cubic mapping.
- **Detach on silence.** A sound at volume 0 detaches its decoder after 5 seconds (`blanket/sound.py`).
- **Presets.** They are named snapshots of per-sound volume and mute, stored per preset in GSettings. Next and previous preset map to MPRIS next and previous.
- **Custom sounds.** They are stored as name-to-URI links, which is why they break after reboot or a Flatpak path change (#348, #384).
- **Missing.** There is no sleep timer (#243 open), no random or interval triggers, and no crossfade.
- **Background and MPRIS.** Both are present.
- **Gapless loop trick** (`blanket/audio/bins.py`):
  - Seek with the `SEGMENT` flag and an explicit end equal to the duration.
  - Catch `SEGMENT_DONE` in a pad probe, drop it, and re-seek without flushing.
  - Drop `EOS` so it doesn't end the whole pipeline.
  - Retry while the duration is unknown.
  - The gapless result depends on the files being cut cleanly.
- **Noise.** White and pink noise are now synthesised with `audiotestsrc` instead of the CC BY-SA oggs. The oggs are still in the gresource file, so they are likely vestigial (inference).
- **Crossfade idea.** Issue #11 sketches playing random sections of a clip with overlapping fades. It is a good approach for your layers.

## 4. Ecosystem
- **No Flutter port found.** My GitHub searches turned up none.
- **Blanket-derived apps.** All reuse Blanket's sound set:
  - Blankie, macOS: MIT code, 24 sounds, `Blankie/Resources/sounds.json` with per-sound licences, and a credits page.
    - It swapped the noise files for its own CC0 versions.
    - It added brown and green noise, a fan, a forest and an airplane, all labelled CC0.
    - It uses a National Park Service (NPS) fireplace sound.
  - Blankee: Android, GPL-3.
  - Aria: Kotlin Multiplatform, GPL-3, byte-identical oggs.
  - NoiseLooper: Android, GPL-3, with a `credits.xml` and a Wikipedia brown-noise clip marked public domain.
  - blanketforandroid: MIT, on Play.
  - CozySpace: no licence.
  - Blankie's CC0 labels are its own claims, so verify each one on Freesound.
- **Anoise.** GPL-3 covers the code. The `debian/copyright` says nothing separate about sounds, so it is not reusable as audio.
- **Noice.**
  - The code is GPL-3, but the sound library is served from a CDN and isn't in any repo.
  - The manifest type in `trynoice/website/src/api/cdn.ts` does carry SPDX licence and author per source clip.
  - I found no public per-sound list, so treat the audio as not reusable.
  - Its manifest design is worth copying: segments with a `maxSilence` random gap, plus bridge segments.
- **Not found.** I couldn't identify any GNOME app called "Ambience", and Kooha is a recorder.

## 5. Recommendation
1. **Take, CC0, no attribution legally required:** birds, boat, stream, wind. Re-cut wind longer from the 3:32 original.
2. **Take with CC BY credit:** rain (audition it first, given the buzz complaints), waves, storm, city. Skip train: 7 s is too short. Re-cut from the 9:28 original (SDLx) only if you want it.
3. **Optional, lower assurance:** fireplace and summer-night (SoundBible "Public Domain").
4. **Exclude:** pink and white noise, and coffee-shop.
5. **Attribution.** Add a `NOTICE` file and an in-app credits screen. Each entry gets title, author, source URL, licence link and "trimmed/gain-adjusted". CC BY 4.0 requires indicating modifications. State in the repo that sounds are excluded from the AGPL.
6. **Still needed:**
   - Synthesised noise colours: white, pink, brown, with brown being the common ask (#112).
   - Drones from detuned sines.
   - Binaural beats, as two sine channels offset by a few Hz.
   - A synthesised heartbeat, chirp and footstep for the pulse cue.
   - Real recordings of bells and bowls, from Freesound filtered to CC0. Blanket has none (#376 is an open request).
7. **Copy the design.** Use the Blanket loudness table as an asset QA gate. Use per-sound volume plus presets. Add the timer and random-interval cues Blanket lacks. Use Noice's silence-gap segment model for the pulse cue.

Key files: `SOUNDS_LICENSING.md`, `CONTRIBUTING.md`, `doc/Sound_documentation.md`, `blanket/audio/bins.py`, `blanket/main_player.py` and `blanket/sound.py`, all in rafaelmardojai/blanket, plus `Blankie/Resources/sounds.json` in codybrom/Blankie.
