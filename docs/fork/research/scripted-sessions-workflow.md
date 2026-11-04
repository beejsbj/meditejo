# Scripted guided sessions: an end-to-end workflow

Scout report, 2026-10-28, read from `origin/develop` at 703627e4. App facts cite `file:line` on that commit. Anything I could not check is marked **(unverified)**. Voices and licences are another scout's job and are not covered here.

## Recommended workflow (one paragraph)

Keep the **script** as the source of truth: a small versioned YAML file of `say`, `silence(min, max, weight)`, `bell` and `stage` items, written in our own words and reviewed by Burooj as a practitioner. A Python tool beside `generate_bells.py` renders each `say` line through a TTS voice, caches by hash of (text, voice, settings), loudness-normalises, and **bakes** two artifacts per (script, voice, language): one voice-only audio file with the *minimum* silences, and a sidecar JSON listing the points where more silence may be inserted, with weights and caps. The app plays the baked file as an ordinary local track and stretches the session to the chosen length by holding the voice at those points. That is the same mechanism BJS-583 (PR #49, open) builds for Dharma Seed recordings, except the pause map comes from the script instead of a silence detector. This reuses the whole existing player, cue engine, mixer, library and completion stack and needs one new native input (hold points from a sidecar). A runtime player that stitches individual clips on the phone is the more flexible design, but it costs a native clip pipeline plus on-device decoding, and nothing in the listening test needs it. Do it only if per-line swaps on the phone prove worth it.

## 1. What the app already has

**Cue system (bells, pulse, countdown, extension).**
- `CueSchedule` (`lib/services/audio/cue_schedule.dart:5,29,31`) is a pure reference for countdown, start/interval/pulse/end cues and the silent extension. Cue types are only `start, interval, pulse, end` (line 5). Each event carries a sound path and volume, nothing else.
- Execution is native. `NativeCueController` sends configuration over the `meditejo/cues` channel (`native_cue_controller.dart:9-10`). Android's `CueEngine` (`CueEngine.kt:22`) runs in the playback service on the main looper, follows ExoPlayer's media clock while the voice plays and the monotonic clock during countdown and extension, holds a `PARTIAL_WAKE_LOCK` (`CueEngine.kt:40`), and so is unaffected by the screen being off. Swift's `CueScheduler.swift` mirrors it but is unbuilt (DECISIONS.md:231-244; ARCHITECTURE.md "Session cues and Customize", line 810).
- Cue sounds go through a SoundPool bank: `setMaxStreams(6)`, `CONTENT_TYPE_SONIFICATION`, assets preloaded and decoded once (`CueSoundBank.kt:24-28`). A late-loaded sound plays only within 1.5 s (`:129`). DECISIONS.md:637 records a 1 MiB decode ceiling for bells.

**Answer: can it schedule arbitrary voice clips at times in a session? No.** The vocabulary is fixed (four cue types, a few bundled WAV paths). A SoundPool bank is built for short one-shots, not 5 to 40 s spoken lines (a 24 kHz mono 16-bit WAV is about 48 KB/s, so a 20 s line is about 1 MB, at the decode ceiling). Missing for clip playback: a clip cue type, a streaming-capable path (ExoPlayer or MediaPlayer, not SoundPool), on-device decode if clips ship compressed, and a per-session timeline sent over the channel. The *timeline arithmetic* (deterministic offsets, seeks consume missed cues without bursts, speed accounted for) is reusable.

**What already works for a scripted session if it is a single audio file.**
- **Primary audio is just a file.** The timer proves it: `TimerAudioFile` writes a silent WAV of exact length, a 44-byte header plus a sparse truncate (`timer_audio_file.dart:17-42`), and plays it through the normal player, because only real playback keeps iOS alive and keeps bells, fades, lock-screen controls and native completion following the position (comment at `:8-17`). A baked voice track is a normal local track and gets all of that free.
- **Bells in the script** can simply be the existing cues (start, interval, halfway, end are user settings, `cue_settings.dart`) or be baked into the file. I'd keep stage bells baked in the sidecar as an item type only if the practice needs a bell at a specific instruction, which the current cue types cannot do (they are time-based, not content-based).
- **Extend-with-silence** is `CueSettings.sessionDuration` plus a hold after EOF (`cue_settings.dart:255`, `CueEngine.kt:313` `runExtension`). Today that appends silence at the end only.

**BJS-583 and how it relates.** Linear BJS-583 / PR #49 (`fork/extend-pauses`, open, not merged, "Burooj reviews new features himself") spreads the Extend minutes into the recording's own pauses: a new `HOLD` phase in `CueEngine`, a `HoldPlan`, a pure-Dart distribution (weighted by pause length, holds at least 10 s, at most 5 min each, remainder to the end, totals unchanged so "Finishes at" and the end bell do not move), and a "Skip this pause" card. Its input is a *detected* pause map cached per recording, stored as time ranges with a `kind` (`silence` now) so other marker kinds can reuse the store. For scripted sessions the pause map is *authored*: exact, free, and richer (weights, per-pause caps, which pauses are sacred). **So the plan is: finish and phone-verify BJS-583, then let a scripted track supply its pause map from the sidecar instead of from `SilenceDetector`.** That is a small adapter, not a new engine. Caveat: I read the PR description, not the diff; the store's exact shape is **(unverified)**. Also note the PR's open decision (skipping a hold spends its time and finishes earlier) applies directly to us.

**Ducking and background sounds.** The soundscape runs in Dart on `flutter_soloud` (`soundscape_engine.dart:5,338`), with its own fades on pause (`PauseFade`, `:177`). I found no voice-activity ducking: the voice and the bed are two independent players at user-set volumes, and the bed is normalised to -27 LUFS (DECISIONS.md:281). That is fine for a quiet bed. Guided speech needs the voice to sit clearly above it: bake the voice louder rather than build ducking (see section 3). Android focus is handled so a running session owns the mixer (DECISIONS.md:296). A gentle duck while a line is speaking would need the sidecar's clip times, which a baked file with markers could supply later. **(Idea, not built.)**

**Screen-off and native timing.** Android: covered, because the baked file is one ExoPlayer track and holds run natively under the wake lock (as BJS-583). iOS: the Swift engine is unbuilt and iOS is shelved (BRIEF decision 24); a baked track plays there as any audio, and holds stay "at the end" until the Swift engine exists. A runtime clip player would need the Swift version of everything.

**Variable-length stretching.** Today only trailing silence. With BJS-583's hold plan, stretching into the authored pauses works for any target length at least the script's minimum. Shrinking below the minimum is not possible: the minimum is the sum of clips plus minimum silences, and the library entry should say so ("at least 14 min").

**How a scripted session appears in the library/course UI.** No UI work is needed for the first cut, because the seams are already there:
- `Track` has `voices: List<TrackVoice>` each with `guideName` and `audioFiles` (`lib/models/track/track.dart:38,51`). That is exactly "one script, several voices". Languages can be separate voices or separate tracks.
- A course is a `PackModel` with ordered `PackItemsModel` items (`pack_model.dart:9,32`). A TMI course (stages 1 to 10) is a pack whose items are scripted sessions; progress, Resume, "Session 4 of 10" and the Home Continue row work unchanged (BRIEF decision 4, 7).
- The cleanest source is a new content source with prefix `ts-` (scripted) behind `ContentSource` (DECISIONS.md:50), mapping the bundled manifest into `PackModel`/`Track`. The starter set (`starter_set.dart:32`) lists library items by source ID, so scripts can join it. A cheaper route for the prototype is the existing local-file import (`import_service.dart:90,113`), which turns a file into a track, and personal courses (`my-`, ARCHITECTURE.md:878) to group them.
- Length choice belongs in the Customize sheet's Time section as "Extend", which already exists for recordings. For scripted tracks, the label could read "Total length" with the minimum shown.
- Completion: 90% of the *audio file* heard (`CueMath.kt:90`). Holds are not listening (PR #49). A stretched session therefore completes when the voice has been heard to 90% of the baked file, which is a fine rule for us.

## 2. Script format

**Principles.** Text-first, diffable, versioned, no clip IDs authored by hand (they are derived), language and voice kept out of the script. Everything the cue system does not know about lives here; everything it does know (bells at start/end/interval, pulse) stays a user setting.

```yaml
# scripts/tmi/stage-3.yaml
format: 1
id: tmi-s3-breath-and-sensations        # stable; never reused
title: "Stage 3: staying with the breath"
lang: en
practice: tmi                            # category tag, see BJS-586
pace: calm                               # prompt for TTS style; part of the cache key
duration:
  min: auto                              # computed: clips + min silences
  max: 3600                              # seconds; ceiling the tool will stretch to
  default: 1200
items:
  - stage: settle                        # marker, no audio; names a section
  - say: "Settle into your posture. Let the body be supported."
  - silence: { min: 4, max: 20, weight: 1 }
  - say: "Take three slower breaths, and let the out-breath be longer."
  - silence: { min: 20, max: 120, weight: 2 }
  - bell: { sound: bowl_small, at: here }    # optional content-anchored bell
  - stage: practice
  - say: "Rest attention on the breath. When you notice you have wandered, return."
  - silence: { min: 30, max: 300, weight: 4, tag: sacred }   # lengthen last, never shorten below min
  - say: "Check: is attention small and clear?"
  - silence: { min: 10, max: 60, weight: 1 }
  - stage: close
  - say: "Slowly let the practice go. Notice sounds, and the room."
```

Rules, so that the format is testable:
1. `say` is plain text plus optional inline `[pause: 0.6s]` for micro-pauses *inside* a line (turned into SSML `<break>` or split sub-clips by the renderer, per engine). Longer gaps are always a `silence` item.
2. `silence.min` is always honoured; `max` caps stretching; `weight` is relative share when distributing extra time. `tag: sacred` means "stretch last".
3. **Fitting rule** (a pure function with unit tests, shared in spirit with BJS-583's distribution): `target = clamp(user length, min_total, max_total)`. Extra = target minus min_total, spread over silences in proportion to `weight * (max - min)` with per-item cap `max - min`, iterating when a cap is hit. If `target > max_total`, the remainder goes to a final trailing hold (as today's Extend). Deterministic: the same inputs give the same plan.
4. A `stage` item produces a marker in the sidecar (name, time at min length). It feeds the player's progress display, BJS-586's labels, and the "markers split a mixed recording" idea in BRIEF decision 16.
5. Validation: unknown keys rejected, `format` must equal a supported number (the app already treats unknown versions as defaults, `cue_settings.dart:62`; do the opposite here and refuse), every `say` under a sane length (renderers fail on long inputs; also a pacing check), the script must start and end with a `say` or `silence`.
6. Derived, not authored: clip ID = first 12 hex of SHA-256 of `(normalised text, voice id, model, settings, pronunciation-dictionary version)`.

**Sidecar (build output), also versioned:**
```json
{ "format": 1, "script": "tmi-s3-...", "voice": "voice-id", "lang": "en",
  "audio": "tmi-s3.en.voiceA.m4a", "minMs": 612000,
  "holds": [ {"atMs": 143200, "minMs": 0, "maxMs": 116000, "weight": 2}, ... ],
  "stages": [ {"name": "practice", "atMs": 61000} ],
  "bells": [ {"atMs": 130000, "sound": "bowl_small"} ] }
```
`holds[].atMs` is the midpoint of the minimum silence in the baked audio, so the engine pauses the voice there and resumes, exactly BJS-583's contract. The audio contains the minimum silences (not zero), so a user who picks the minimum just plays the file.

**Prior art checked.**
- **SSML.** `<break time="..."/>` and `strength` are standard in W3C SSML 1.1 (https://www.w3.org/TR/speech-synthesis11/, from memory, not re-fetched). ElevenLabs documents `<break time="1.5s" />` but says up to 3 s and not on Eleven v3/v4 (https://elevenlabs.io/docs/help-center/product/core-capabilities/text-to-speech/how-can-i-add-pauses). That is why long silences must be composed in post, not asked of the model. SSML is a good *input dialect per engine* but a poor *source format*: it fuses voice settings and timing, and it cannot express "stretchable".
- **Hobbyist tools** all converge on the same shape, text with pause markers, one TTS call per segment, silence inserted in post, ffmpeg or pydub concat: `jeffwright13/audio_program_generator` (https://github.com/jeffwright13/audio_program_generator), a pydub forum example (https://community.openai.com/t/adding-pauses-to-tts-for-generating-meditations/504634), a markdown format with `[pauses]` (https://gist.github.com/kiliman/a9a6c98642bd2b20b8c92a1e49a313d9), and the PyPI `meditation-audio-generator-openai`. All emit a fixed file. None has min/max/weight stretching, per-line caching or a sidecar (as far as I could see; I did not read their code). So the design above is ours, but it is conventional at the clip level.
- **Medito's own content model:** my search found nothing public on how its guided sessions are structured; the BRIEF says its audio is proprietary and the fork keeps only the app code. Nothing to borrow. **(Unverified: Insight Timer, Calm, Headspace, Waking Up scripted-timer internals; they are closed.)**
- **Request stitching** for prosody across separately rendered lines: ElevenLabs offers `previous_request_ids`, with IDs no older than two hours, and says it is unavailable on `eleven_v3` (https://elevenlabs.io/docs/eleven-api/guides/how-to/text-to-speech/request-stitching.md). This is in tension with per-line caching (a cached line was rendered with different neighbours). Practical answer: render stage by stage, cache at the *stage* level, and let single-line regeneration accept a small prosody seam.

## 3. Authoring pipeline

1. **Method to outline.** For each TMI stage, write a one-page outline in our own words: aim, the instructions the stage actually needs, the common pitfalls, a closing. Burooj, as the practitioner, signs the outline *before* any script exists. Never paste or closely paraphrase the book; the outline should be drawn from the method's structure and Burooj's own understanding.
2. **Script draft.** LLM-assisted from the outline against the format and a style sheet (second person, present tense, short sentences, no jargon not already introduced, one instruction per line, maximum words per line). The style sheet is the main quality lever and lives in the repo. Output goes to `scripts/<practice>/<id>.yaml`.
3. **Review.** A diff-style review by Burooj in the repo, per stage. Also a mechanical lint (reading-speed estimate, line length, banned phrases, silences present after every instruction). The review is content accuracy, not prose polish. Record sign-off in the script header (`reviewed_by`, `date`).
4. **Render.** Each `say` line through the chosen engine. The tool normalises text (numbers, "TMI"), applies a pronunciation lexicon for Pali and technical terms, and renders at the engine's native rate. Cached by `sha256(text, voice, model, settings, lexicon version)` under `tools/meditejo/.cache/tts/` (git-ignored, but shareable). Only changed lines re-render.
5. **Loudness.** Trim leading and trailing silence per clip (threshold, then keep a fixed 80 ms head and 200 ms tail so breaths don't clip), then normalise **per clip to one speech-loudness target** and verify the assembled file's integrated loudness. The app's -27 LUFS is the *soundscape bed* target (DECISIONS.md:281, `-27 LUFS` repeated in BRIEF decision 6), not a speech target. For a voice that sits above the bed I'd start the A/B at about -19 LUFS integrated (podcast speech is typically -16 to -20; this is my starting number, **unverified** against this app's bed and Burooj's ears), with a -1.5 dBTP ceiling, and decide by listening. The existing bells use a momentary-loudness match to the session bell (`generate_bells.py:38`), which tells us the house style: a measured target in the tool, `--check`/`--measure` modes, numbers in `bells_report.py`-style output.
6. **Assemble.** Concatenate clips with the *minimum* silences (generated digital zeros at the output rate, with a 20 ms fade at each join so no click), write the sidecar with hold midpoints and stage times. Encode to AAC (`.m4a`) or Opus at about 32 kbps mono for speech. Estimated size: 20 minutes of minimum-length audio is about 4.8 MB at 32 kbps (arithmetic, not measured), so a whole 10-stage course is tens of MB, not hundreds.
7. **Package.** Two options. *Bundled* in the APK: simplest, offline from the first launch, but the APK is already 62.5 MB (CUES_PROGRESS.md) and the release is arm64 only. *Downloaded on demand*: the same lazy-download pattern is already planned for sounds ("sounds as a separate download", BRIEF decision 24) and for the Dharma Seed catalogue, which lives as a prerelease asset of `beejsbj/meditejo` (DECISIONS.md:454). Recommended: ship the manifest and sidecars in the APK, and the audio as a GitHub release asset fetched and hash-checked on first use, reusing the catalogue tool's fetch/verify/publish approach (`tools/meditejo/catalogue.py`). That also lets a voice be swapped or a line fixed without an app release. Cost: the first session needs a network, which I think is fine since BRIEF decision 9 already treats audio as streamed or downloaded.
8. **Licence notice.** Add a section to `assets/audio/NOTICE`-style file (or a `NOTICE` beside the release asset), stating: the script text is original to Meditejo under CC0 or the repo licence (Burooj's decision), the audio is synthesised by *engine X, voice Y* with a link to that service's or model's terms, no recordings of real people unless a voice licence says so. The APK licence check (`check_apk_licenses.py`) verifies bundled assets against NOTICE; if audio is a download, add the equivalent check to the publish step. The voice terms (commercial use, redistribution, attribution, AI disclosure) are the other scout's output and decide which sentence goes here.

**Tool shape.** `tools/meditejo/render_session.py`, standard library plus `ffmpeg` and a pluggable engine adapter, modelled on `generate_bells.py` (`--check`, `--measure`, fixed output dir, deterministic output):
```
render_session.py scripts/tmi/stage-3.yaml --voice voiceA --engine elevenlabs
    [--out build/sessions]  [--only-changed]  [--dry-run]  [--check]  [--measure FILE]
    [--lang en|de|es]  [--translate-from en]
```
- `engines/{elevenlabs,gemini,kokoro,piper}.py`, each exposing `render(text, voice, settings) -> wav` and `cache_key_parts()`.
- A test file in the style of `test_catalogue.py`/`test_sounds.py`: parser, validation, fitting rule, silence maths (the sidecar's hold sum), cache-key stability, deterministic assemble from stub clips.
- Cloud engines need API keys: use the environment, never the repo, and a `--dry-run` that prints the characters and estimated cost before spending.
- `--check` for a local open model should reproduce byte-for-byte with a fixed seed. Cloud engines will not. Treat the cache as the artefact of record and commit the sidecar plus a manifest of hashes, not the audio.

## 4. Listening-test plan (cheap, before any app work)

Goal: choose a voice and a pace on Burooj's phone, with the real background sound, for one TMI stage.
1. Write one stage script (stage 3 or 4, about 8 minutes at minimum length), reviewed by Burooj. Same script for every voice.
2. Render 2 to 3 candidates (for example one cloud voice and one local model from the other scout's shortlist) with the same pace instruction. Assemble each at **one fixed 20-minute length** by distributing silences through the fitting rule, so the A/B is also a test of the pacing, not just the timbre. Output `ab-voiceA.mp3` etc. at 128 kbps, so any player on the phone works. (MP3 for the test only, since the import path and ExoPlayer accept it; the real artefact is m4a/opus.)
3. Get the files onto the S23+ with the remote-control tooling the BRIEF names (it can write to Downloads), then **add them with the app's existing local-file import** (`ImportOrigin.localFiles`, `import_service.dart:90`) into a personal course "Voice test". Run them in the dev flavor with Practice's background sound on, a bowl for start and end, and the screen off, because that is how the session will really be heard. Loudness balance against the bed is the first thing to judge.
4. Judge on a short form (write down each time): intelligibility at low volume; does the voice feel like a person asking or a machine reading; pace and breath; how the silences feel (too long invites sleep or rumination, too short rushes); mispronounced Pali/technical terms; fatigue after 10 minutes; whether the bell and voice collide.
5. Throwaway alternative: an HTML page with `<audio>` players and an A/B/X blind toggle served from the dev machine. Quicker to iterate, but it tests neither the phone speaker nor the background-sound mix, which is the point, so I'd use the import route.
6. Output of the test: a chosen voice and loudness number, a style-sheet tweak list, and a go/no-go on "AI voice feel" before any app code. That gate is cheap and honest.

## 5. Risks and open decisions for Burooj

1. **Content accuracy.** The whole point is trustworthy practice instructions. Burooj as the only reviewer is a bottleneck and a single point of failure; the Mind Illuminated has stage-specific details (e.g. the exact distinction between attention and awareness, and the order of stage goals) where a plausible LLM draft can be subtly wrong. Decide: reviewed by Burooj only, or also by a teacher or the community. Say in the app that the scripts are an independent adaptation, not the book or its author. Do not use the book's wording, diagrams or named exercises beyond naming the method. Whether using "The Mind Illuminated" or "TMI" in the title is acceptable is a trademark/endorsement question for Burooj to settle **(unverified, not legal advice)**.
2. **AI-voice feel.** Synthetic voices can be fine for instructions and unsettling for long guidance. Mitigated by the listening test and by keeping most of a session in silence. A real-voice option (Burooj records himself, same script, same sidecar) fits the pipeline with no change, since a clip is just audio. That is worth keeping as the quiet fallback.
3. **On-device vs pre-rendered TTS.** On-device (Piper, Kokoro) would allow arbitrary text and translations but adds a large model (tens of MB or more **(unverified)**), CPU cost and native work; pre-rendered gives fixed, curated quality, a smaller app, and the cost goes to build time. Recommendation: pre-render only. Only revisit if users (i.e. Burooj) want to type their own scripts.
4. **Cloud TTS terms and cost.** Per-character pricing, plan limits, and terms for redistributing synthesised audio in an open-source app all sit with the voices scout. The cache must make re-rendering cheap, because Burooj will edit scripts a lot.
5. **Prosody seams between separately rendered lines.** Stitching helps (not on Eleven v3), and conflicts with per-line caching. Accept small seams or cache per stage.
6. **Hold points are pauses in the voice track, not in a continuous soundscape.** The bed keeps playing through holds (as in PR #49), which is what we want. Check that the voice does not resume with a jolt after a long hold: a short fade-in at resume belongs in the native hold, probably a PR #49 follow-up.
7. **Coupling to PR #49.** The hold engine is unmerged and unverified on a phone (its description says so). Scripted sessions inherit its bugs and its open decision about skipping. Don't start phase 2 until #49 is merged or Burooj says to build on the branch.
8. **iOS later.** The Swift cue engine is unbuilt and iOS is shelved. A baked track plays on iOS as any audio. Holds need Swift work (BJS-583 says iOS stays at "At the end"). Because the sidecar is platform-neutral, nothing in the format blocks iOS.
9. **Feature PRs wait for Burooj** (memory: new-feature PRs are not merged by agents; new strings need real de/es translations). A `ts-` source and a new library surface are feature work, so each phase below ends at a PR for his review.
10. **Where scripts live.** In-repo `scripts/` under the AGPL or CC0 for the text? Output audio licence follows the voice terms. A licence for original scripts should be chosen deliberately so others can reuse and translate them.
11. **Naming and categories.** BJS-586 (categories/labels, in the v1 push) gives TMI a place to be a label; decide whether scripted sessions are "Practice" with a visible "voice: synthetic" mark. I'd mark them honestly.

## 6. Phased plan

| Phase | What | Reuses | Rough effort |
|---|---|---|---|
| 0. Voice prototype | One reviewed TMI stage script; render 2 to 3 voices with a throwaway script (no cache yet); fixed-length MP3s; A/B on the S23+ through local import. | Local-file import, personal courses, Customize bells and background sound | 1 to 2 days, mostly script review and listening. No app code. |
| 1. Authoring tool | `render_session.py`: format, validation, fitting rule, cache, loudness, assemble, sidecar, tests, NOTICE text. Output m4a plus sidecar. | `generate_bells.py` and `bells_report.py` shape, `test_*.py` style, `catalogue.py` for hosting | 3 to 5 days. Can run in parallel with BJS-583 review. |
| 2. Minimal in-app player | Sidecar read as the pause map for BJS-583's `HoldPlan`; "Total length" chooser; stages shown on the player. A scripted track still enters via import or a hard-coded `ts-` manifest. | PR #49 (`HoldPlan`, `CueEngine` HOLD, Skip card), `TimerAudioFile` idea, player, completion, mixer | 3 to 5 days if #49 is merged. Android only. Phone check needed (screen off, 20 min). |
| 3. Library integration | `ts-` content source mapping scripts to `PackModel`/`Track` with `voices[]`; TMI course in the starter set or Explore; download-on-demand with hash check; labels via BJS-586; voice and language pickers on the track page. | `ContentSource`/router, `starter_set.dart`, `Track.voices`, catalogue fetch/verify, categories | 1 to 2 weeks including de/es strings and a review round. |
| 4. Optional | Per-clip runtime player (clip cue type, streaming path, Swift port) for on-phone voice swap and ducking while speaking; on-device TTS; iOS holds. | Cue timeline maths | Weeks. Not recommended until phases 0 to 3 show a need. |

**Order of questions for Burooj:** (a) is the baked-file-plus-holds route acceptable, instead of a runtime clip player? (b) who reviews content beyond him? (c) bundled vs downloaded audio? (d) the script licence. Everything before phase 2 is reversible; phase 0 can start as soon as a voice shortlist exists.
