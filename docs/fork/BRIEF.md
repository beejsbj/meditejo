# Fork brief: Meditejo

This is a personal, open-source (AGPL-3.0) meditation app forked from Medito (`upstream` = meditohq/medito-app, branched from `develop` on 2026-10-13). Burooj owns the product decisions. This brief records what was settled in the founding conversation (Cockpit thread, 2026-10-13/14), so read it before planning.

**The name:** *Meditejo* is Esperanto for "place of meditation" (*medit-* + *-ej-*, the place suffix, as in *lernejo* "school" and *preĝejo* "church"). It keeps Medito's Esperanto lineage (*medito*, "a meditation"). Pronounced meh-dee-TEH-yo.

## Why it exists

Burooj's practice material is scattered across Dharma Seed, YouTube and courses (Rob Burbea retreats, QRI Qualia Mastery, metta and jhana series). Every tab and every awkward player costs him the thread, so he stops practising. Waking Up worked for him because everything lives in one familiar, calm place. This app should be that place for *his* material.

- Courses are first-class: an ordered multi-session pack with progress. The home screen leads with **"Continue your practice — <course> · Session 4 of 18"**.
- Meditation-focused and polished. **Not a podcast app.** No gamification, no busy dashboards.
- Fully personal: no account, no server-side stats, no donation ask, no shop.
- **Useful from the first launch.** Built-in catalogues (Dharma Seed first) and a starter set of courses and soundscapes mean no setup before the first sit. Importing should be "paste any link → preview → add as course or single", never a hunt for raw media URLs. Mindra fails on both counts; see `docs/fork/mindra-review.md` for what to borrow (its session-recording model) and what to avoid.

## Settled decisions

1. **No Medito content.** Their audio is proprietary (meditofoundation.org/license), and their API URL and key are private build-time values. Remove the Medito catalogue, auth/account, stats POSTing, donation paywall, merch shop, Stripe, Meta SDK and Firebase analytics. **Keep their app code and UX:** player, pack/course view, bells, timer, background-sound player, downloads, favourites (already local), stats and streaks (make them local-only).
2. **Rename** to Meditejo. Replace Medito's name, logos and app icons (`assets/*medito*`, iOS `.icon` bundles) and change the application ID. Keep AGPL notices and credit the Medito Foundation as the upstream project.
3. **Content sources**, each surfaced through the existing pack/track UI:
   - **Built-in Dharma Seed (first-party, searchable).** Unofficial API used by its official Android app: `POST https://www.dharmaseed.org/api/1/{talks,teachers,retreats}/` (multipart form). `detail=0` returns `{edition, items:[ids]}` for incremental sync (pass `edition` back). `detail=1&items=<ids>` returns full records.
     - Talks carry `title, teacher_id, retreat_id, audio_url` (relative, prefix `https://dharmaseed.org`), `duration_in_minutes`, `rec_date`, `recording_type`, `description`.
     - Retreats carry `name, start_date, talks:[ids]`. Teacher photos come from `/api/1/teachers/<id>/<photo>/?maxW=..`.
     - There are about 49k talks and no search endpoint, so sync metadata to an on-device DB (SQLite/drift with FTS) and search locally, as their app does.
     - Retreats map to courses; individual talks map to singles. Users can favourite talks and save retreats or teachers.
     - Licence: CC BY-NC-ND, so stream unmodified with attribution. Be a polite API client: incremental sync, no hammering.
   - **Other open catalogues**, after Dharma Seed works: dhammatalks.org (CC BY-NC; RSS plus yearly archive pages), the AudioDharma RSS feed, UCLA Mindful. Details and licences are in `docs/fork/content-sources.md`.
   - **User imports, one pipeline:** RSS/podcast feeds, a Dharma Seed retreat or teacher URL, a single audio URL, local files, and YouTube videos/playlists as courses or singles.
     - Every source produces the same course/session model.
     - YouTube streams by storing the video ID and resolving a fresh stream URL at play time, as NewPipe does; the URLs expire after about 6 hours. Use **NewPipeExtractor** through a small Android platform channel, with yt-dlp (youtubedl-android) as an optional fallback for other sites. Downloading for offline use is optional. Burooj accepts the YouTube ToS risk, but such an app can't go on the Play Store; distribute through GitHub releases or F-Droid.
4. **Seam.** The player only needs a `PlaybackRequest` (`lib/models/player/playback_request.dart`). Packs and tracks reach the UI through `PacksRepository`/`TrackRepository` (`lib/repositories/pack`, `lib/repositories/track`), and pack progress is computed locally from `tracksChecked` IDs (`lib/providers/pack/pack_provider.dart`).
   - Route by ID prefix per source (`ds-`, `lib-`, `yt-`, …) to local or source-specific repositories that map into `PackModel`/`Track`, so PackView, the player, downloads and completion keep working.
   - `MockHttpApiService` (`lib/mock/`) shows how all HTTP is intercepted today; replacing the Medito backend is the larger version of the same move.
   - The home screen is composed from `HomeWidgetType` sections (`lib/providers/home/widget_order_provider.dart`), and that's where "Continue your practice" goes.
5. **Waking Up-style practice features.**
   - Medito already has start, middle and end bells (`lib/services/audio/session_bell_schedule.dart`), a timer and a background-sound layer.
   - Generalise bells into a **cue system**: one scheduler for start, end and interval cues. The **pulse** belongs there too, a rhythmic cue (heartbeat, chirp, footstep, click) with BPM and an optional slow "settle" ramp, since it's just a very short interval. Burooj suggested this unification. Noice's segment model (random silence gaps between segments) fits sparse cues.
   - Add **interval bells** and **"extend with silence"**: after a track ends, continue for N minutes with the background sound, then ring the closing bell.
6. **Soundscapes: the sound library comes first, the mixer second.**
   - Sources are in `docs/fork/soundscape-sources.md` , `docs/fork/blanket-deep-dive.md` and `docs/fork/blankie-review.md` (licence-as-data `sounds.json`, per-sound LUFS normalisation to about -27, baked loop crossfades; its fireplace is really CC BY-NC, so skip it) (Blanket: take originals from Freesound and redo its documented edits — loudness targets in its CONTRIBUTING.md; sounds ship under their own licences, outside the AGPL, with a NOTICE and in-app credits): Freesound CC0 picks, BigSoundBank, OpenGameArt, and Blanket's loop-edited set (Blanket is GPL-3.0; its files are CC0, CC BY or PD per its `SOUNDS_LICENSING.md`; avoid its CC BY-SA noise files). Keep a credits screen for CC BY items.
   - **Synthesize, don't ship:** noise colours (white/pink/brown, ideally as a myNoise-style multi-band generator with per-band sliders), drones and **binaural beats** (myNoise has these). The pulse lives in the cue system and mixes like a layer.
   - No heart-rate sync: Burooj doesn't wear a watch, and Health Connect only delivers batches (decided 2026-10-15). Adaptive behaviour, if any, comes from time of day and session phase.
   - Mixer: several layers, each with its own volume, an optional slow "animate" drift and saved presets. `flutter_soloud` (MIT) is the leading candidate engine for gapless loops and synthesis; verify its API before committing.
   - myNoise's own recordings are proprietary. Learn from its design but never copy its audio.
7. **Learned from Waking Up** (decided 2026-10-16; evidence in `docs/fork/research/waking-up-ux.md`).
   - **Home:** keep the "Continue your practice" hero. Below it, add a Waking Up-style **Customize**: a short set of "Today" supports the user can switch on and off (timer, soundscape, and so on), up to **three pinned courses**, and a quiet continue-listening row.
   - **Stats:** take the consistency score and streaks off Home and put them on the stats screen. Word them as feedback, not a score, in the spirit of *"These stats are feedback, not a score."*
   - **Explore:** content-kind chips separate **Practice** (guided meditations) from **Talks** (dharma talks, Q&A). Dharma Seed's `recording_type` supplies the kind.
   - **Player settings:** a Waking Up-style **Customize sheet** in the player, shared with the timer. It is the single home for the cue system and soundscapes:
     - countdown;
     - starting, ending and interval cues, including the pulse;
     - extend with silence;
     - background sounds with a volume mix, with separate defaults for practice and talks;
     - autoplay with an optional interlude;
     - a live "Finishes at …" line.

     Each row shows its current value and opens a small sub-sheet. Burooj singled out this UX.
   - **Completion:** mark completion on real listening, not when a session is opened. A session counts as completed once **90%** of it has been heard (decided 2026-10-17), so a long talk stopped near the end still counts.
8. **Background sounds may play over Dharma Seed audio** (decided 2026-10-17). Mixing at playback leaves the original file untouched and distributes nothing, so it is allowed. Default it on for Practice and off for Talks. *Refined 2026-10-26 (decision 17):* Practice now starts with nothing chosen, like Talks. Never export or share mixed audio.
9. **Dharma Seed sync is catalogue text only, never audio** (2026-10-17). The app keeps the title, teacher, length and retreat of every talk on the phone, about 38 MB once, because Dharma Seed has no search API. After that it fetches only small updates, on any network. Audio always streams, and downloads only when the user chooses to download a talk.
10. **Meditejo is the user's library, not a Dharma Seed frontend** (2026-10-17).
    - Easy import from any link is the core of the app: Dharma Seed, YouTube, RSS, audio URLs and files.
    - Dharma Seed is a convenient way to find things to add. Explore reads as "find something to add", and Home and the library show what the user has added.
    - **Catalogue delivery:** ship the Dharma Seed catalogue inside the app as a compressed database, refreshed each release. Fetch only the additions since that snapshot, and do it when the user opens search or browse, not at startup.
    - **Design pass:** palette, type, motion, and the player, course list and home surfaces come **after the import slice lands**, with Burooj in the loop from the moodboard on.
11. **Practice comes before talks**. *Refined 2026-10-19:* Practice/Talk labels can be wrong, especially Dharma Seed's, so the labels only set a soft default order. Anything the user chose explicitly outranks them: pins, manual order, and items in progress. Relabelling must stay one tap away. Original wording: (Burooj, 2026-10-17: "practice >>>> talks"). Guided practice leads everywhere a choice exists: Home, Explore, search ordering, the starter set and import defaults. Talks, Q&A and the rest are secondary.
12. **In-app updates** (requested 2026-10-17, modelled on the Nuvio Android app). The app checks for a newer signed build, downloads it and hands it to Android's installer, so Burooj doesn't fetch APKs from GitHub by hand. This needs a published, durably signed APK somewhere the app can reach, for example GitHub Releases on `beejsbj/meditejo`. **Hosting: GitHub Releases on public `beejsbj/meditejo`** (Burooj, 2026-10-17).
    - Each release carries an APK signed on bjslab with the durable key.
    - The app checks the latest release, downloads the APK and **verifies that its signing certificate matches the pinned digest** before handing it to Android's installer. Meditejo holds the "install unknown apps" permission itself.
    - Publishing a release is approved as a routine step of this channel. Each release is reported to Burooj, with its notes.
13. **Built-in starter set** (Burooj, 2026-10-19). These ship with the app, already in the library on first launch, with no sync or import needed. Audio streams as usual.
    - Dharma Seed retreat 4496, *Practising the Jhānas* (2019, 32 talks). https://dharmaseed.org/retreats/4496/
    - Retreat 1084, *The Loving Kindness (Metta) Retreat* (2010, 10 talks). https://dharmaseed.org/retreats/1084/
    - Retreat 1183, *The Art Of Concentration (Samatha Meditation)* (2008, 9 talks). https://dharmaseed.org/retreats/1183/
    - Retreat 1308, *Samatha Meditation* (2007, 7 talks). https://dharmaseed.org/retreats/1308/
    - Talk 60864, *Developing Piti, Developing Focus, Developing Wellbeing* (Rob Burbea, 89 min, from retreat 4496). https://dharmaseed.org/talks/60864/
    - YouTube playlist *Meditating with John Vervaeke* (John Vervaeke's Lectern). https://www.youtube.com/playlist?list=PLND1JCRq8VujAHvDA482SXF1cJTQrwlx3
    - YouTube playlist *Qualia Mastery: Building Your Toolkit for Navigating the State-Space of Consciousness* (Qualia Research Institute). https://www.youtube.com/playlist?list=PLbmYHvGI-YSvnpbh3ppQqcG72lpw4aQdE
    - Shipped in PR C2 for the Dharma Seed items (`lib/services/library/starter_set.dart`); the YouTube items join with the YouTube slice.
    - The YouTube items depend on the YouTube slice. Their playlist item lists can be bundled at release time, and audio is resolved at play time.
14. **Four tabs: Home · Explore · Library · Settings** (Burooj, 2026-10-19).
    - **Explore and Search are merged.** Explore has a search bar at the top. With nothing typed it shows browse (Practice/Talks chips, saved courses, Dharma Seed courses and teachers). Typing shows grouped results with "Add to library".
    - **Library gets its own tab,** because the user's library is the core of the app.
    - **Home is quick links,** a launchpad rather than a catalogue (Burooj, 2026-10-19):
      - one-tap starts for **Timer** and **Sounds**, plus other supports from the Customize set;
      - **Continue** items for whatever is in progress. There can be several ("continue this or that"), practice first, each resuming in one tap.
      - This refines decision 7's single hero into a short list of continues plus quick links. Browsing belongs in Explore, and everything added lives in Library.
15. **Order after navigation and Home: cues and the Customize sheet first** (Burooj, 2026-10-19). Build the full player Customize sheet and the cue system now, in Medito's current look. The design pass restyles them later. After that come soundscapes and then more catalogues. The design pass follows cues.
16. **The design pass starts now, in Material 3 Expressive** (Burooj, 2026-10-26, after testing 0.1.3 on the phone). Use Material's Expressive design language largely as it stands; visual taste can be fixed afterwards, so don't wait on Burooj for each choice.
    - **Home**, from the top: an **animated logo mark**, top centre as in Waking Up (an abstract, minimal SVG-style mark of simple shapes in slow motion, in the spirit of Claude's abstract illustrations); then the **quick links**, which may include saved sound presets that start the Timer; then **pinned**.
    - **The Customize and Sounds sheets are too cramped** ("suffocating": a drawer full of pills). Sounds should feel first-party, possibly as its own tab. **Explore's cards** need improving.
    - **A stats page:** time spent practising.
    - **More bowl and bell sounds,** chosen separately for the start, interval and end cues.
    - **Labels** such as Metta, Jhāna and Vipassanā on what's kept.
    - **Practice/Talk:** easy switching while listening ("this is actually a talk"), and possibly markers in the player that split mixed recordings into practice and talk sections.
17. **Smaller calls** (Burooj, 2026-10-26):
    - Move the Dharma Seed catalogue snapshot out of git.
    - Practice's background sound starts with nothing chosen.
    - Removing an imported course confirms before deleting its audio (the current behaviour).
    - Ask Hermes Amāra, QRI and Plum Village for permission to stream their recordings. Don't ask AudioDharma for a catalogue export, since slice 8 builds its catalogue anyway.
18. **Answers after testing cues** (Burooj, 2026-10-26):
    - **Tabs:** Home · Explore · Sounds · Library · You. Stats and Settings sit under You. This supersedes decision 14's four tabs.
    - **Settings needs reorganising.** Check for updates belongs on the main Settings screen, not two levels down.
    - **Naming:** what the user makes is a **Playlist**. What comes from a source (retreats, YouTube playlists, feeds) stays a **Course**.
    - **Number and time selection** uses a scroll-wheel picker: a centred, highlighted value with its neighbours faded above and below. It replaces sliders and pills for durations and counts.
    - **Interval bells can be set to "halfway",** a single bell at the session's midpoint.
    - **Import:**
      - a pasted feed or playlist defaults to the whole list as a Course;
      - Single means picking one episode, with the latest preselected;
      - folder import must work on Android.
    - **Saved teachers** stay in the Library as a Teachers filter. "New from teachers you follow" can come later.
    - **AudioDharma is skipped** (superseded the same day, 2026-10-26). Users can still import its feed themselves.
    - **Permissions:**
      - Hermes Amāra was asked by email (sent 2026-10-26 to info@hermesamara.org).
      - QRI and Plum Village are not being asked. QRI's YouTube playlists stay in the starter set, at the same accepted risk as Vervaeke's.
      - Plum Village's own terms forbid sharing, so it is not built in.
19. **After seeing design pass 1** (Burooj, 2026-10-26):
    - **The Timer starts silent by default.** Users set their own defaults. Later the Timer may reuse whatever was used last time.
    - **Home's hierarchy is right; the visuals are not finished.**
      - The mark is weak, and so are the colours.
      - There is no logo or app icon yet.
      - A dedicated identity pass comes next: a seeded generator that builds many marks (gesture-on-form in the spirit of Claude's "Duet" icon, plus atmospheric ones), palettes, and an app icon. Burooj picks before anything is ported into the app.
    - **"Quick links" is the wrong name.** Its tiles can also be guided practices (a session, possibly with a sound preset), not only Timer presets.
20. **Identity and layout feedback** (Burooj, 2026-10-26):
    - **Bells:** all ten synthesised bells approved. Designing your own bell is a future issue (BJS-587).
    - **Home has no section headings under the mark.** The tiles and cards sit straight under it.
    - **The Sounds tab shows three cards per row.**
    - **The mark breathes.**
      - It is inspired by Claude's Duet icon but must not copy it. The Duet-like loop may turn up in the random pool but is not featured.
      - Imperfect circles breathe between perfect and imperfect.
      - Marks should evoke the name: Meditejo, "place of meditation".
      - The gesture and minimal families are liked. The atmospheric family needs another iteration.
    - **Daily variety:** the mark changes each day, and so can the palette. The user can also pin a mark or palette, since the palette themes the whole app.
    - **Generated art everywhere there's no curated artwork,** "less digital" than today's covers:
      - the Sounds and preset cards get atmospheres driven by their sounds;
      - courses, playlists, teachers and singles get seeded covers.
    - **Categories:** curating practices by category (Metta, Vipassanā, Sankalpa, Jhāna, TMI…) is a future issue (BJS-586).
21. **Identity picks** (Burooj, 2026-10-26, after round 2 of the identity exploration on `fork/mark-explore`):
    - **App icon: the shelter mark** (a roof line over a resting pebble). It is the fixed launcher icon and house mark.
    - **On Home, the mark changes daily and can be pinned.** It breathes between perfect and imperfect.
    - **The palette is fixed by default: Tidewater.** "Daily palette" is an option in Settings, and the mark and palette are pinned separately.
    - **Generated art is the right direction but needs more primitives.** Sound cards and covers read too alike. Add breaths, fire, concentric circles and minimal mandalas, among others.
    - **Freesound:** all eleven originals and the three replacements are approved by ear.
22. **Generated art rules** (Burooj, 2026-10-26, after identity round 3):
    - **Random generation is for what the user adds, imports or creates.** **Everything Meditejo ships is curated**: built-in sounds, presets, the starter set, and featured catalogue items each get a hand-chosen composition.
    - **Round 2's atmosphere returns** as grounds under round 3's figures.
    - **A tight meaning map:** each sound or kind has only a few fitting grounds and figures, so no arbitrary pairings.
    - **Drop the weak primitives.** Constellation becomes a scatter of stars forming a shape, not stars linked in sequence.
    - **Every primitive animates gracefully.**

## Build and run

- **bjslab** is the main working machine: code, codegen and light checks. Flutter isn't installed yet; install the SDK under the user (not system-wide), matching `pubspec.yaml` (Flutter ≥ 3.47, Dart ^3.8).
- **Heavy builds** (Gradle/APK) go elsewhere; read `cockpit handbook bjslab/capabilities/daytona` first.
  - **Daytona** (`cockpit compute run --profile android`) can reach Flutter's SDK host (storage.googleapis.com), Google Maven (dl.google.com) and Maven Central, but **pub.dev is blocked** (probed 2026-10-14). Run `flutter pub get` on bjslab and ship the pub cache with the upload (the runner excludes dependency directories by default, so check `--dry-run`).
  - **Mac** (`ssh macbook`, M1 with 16 GB; see `cockpit handbook bjslab/capabilities/macbook-ssh-access`) has `adb` but no Flutter or Android SDK. It's Burooj's live machine, so get his OK before installing toolchains there.
- Medito's **mock mode** (`--dart-define=MOCK_MODE=true`, flavor `dev`) runs without keys and is a useful baseline before the backend is removed. The README covers the codegen steps (pigeon, build_runner) and the keystore placeholder.
- **Test device:** Burooj's Samsung S23+, reached through its remote-control MCP over Tailscale. See the handbook's `s23+` section.
  - That MCP can download or write files into Downloads and drive the UI, so an APK can be installed by placing it in Downloads and tapping through the installer.
  - It has no uninstall tool. Its bearer token comes from `bjs-env bjss23`; never print it.

## How to work

- Keep the canonical checkout clean and work on feature branches or worktrees. Commit small, coherent slices with honest verification notes. Prefer one focused PR per slice on `beejsbj/meditejo`, and never open PRs against meditohq.
- Suggested order:
  1. Get the app building, plus the rename and de-Medito work (backend, account, paywall, shop, analytics removed; local-only stats).
  2. Source/repository seam plus the Dharma Seed built-in (sync, search, retreats as courses, favourites).
  3. Import pipeline (RSS/Dharma Seed URL/audio URL/files).
  4. "Continue your practice" home.
  5. YouTube.
  6. Interval bells and extend-with-silence.
  7. Sound library, then the mixer and synth (noise colours, drone, beater).
  8. More open catalogues.
- Bring product forks back to Burooj (naming, what the home shows, anything irreversible or outward-facing). Decide implementation details yourself and record them.
