# Local content and playback seams

The app launches without accounts, credentials or a network connection. The
bundled catalogue is empty; content comes from sources such as Dharma Seed,
whose catalogue ships inside the app, is unpacked offline on the first launch and
is read from an on-device database. The timer uses bundled bells and a locally generated silent
audio file. Track lookup asks the owning source (or the bundled catalogue)
first. If an entry is unavailable, it falls back to on-device downloaded track
metadata by matching ID. An ID missing from both raises
`CatalogueEntryUnavailable`; there is no Medito backend fallback. Other
catalogue errors propagate without this fallback.

## Content sources

`lib/services/local_catalogue.dart` defines the bundled `LocalCatalogue`
boundary, which is still empty. Everything else arrives through a
**source**: `ContentSource` in `lib/services/content/content_source.dart`.

```dart
abstract interface class ContentSource {
  String get prefix;                       // 'ds-', later 'lib-', 'yt-'
  Future<List<PackModel>> browsePacks();   // bounded, saved first
  Future<PackModel> pack(String id);       // a course: tracks in play order
  Future<Track> track(String id);          // one voice, one playable file
  Future<Map<String, List<String>>> packTrackIds({Set<String> startedTrackIds});
  Future<List<PackItemsModel>> searchPacks(String query);
  Future<List<TrackSearchModel>> searchTracks(String query);
}
```

`ContentRouter` sends each ID to the source whose prefix it carries and falls
back to `LocalCatalogue` for the rest. The repositories below build a router
from `contentSourcesProvider` (`lib/providers/dharma_seed/dharma_seed_providers.dart`),
so views and providers are unchanged. The interface's doc comment holds the
rules for a new source: stable IDs, `/tracks/<id>` item paths, URLs resolved
in `track()`, `CatalogueEntryUnavailable` for unknown IDs, and degrading to
stored data when offline. An RSS or YouTube adapter implements those seven
methods and joins the provider list.

A source whose courses, talks or teachers can be kept also implements
`SavableContentSource` (`canSave`, `isSaved`, `setSaved`); `ContentRouter`
asks only the owning source, and the Add to library button
(`lib/widgets/save_button.dart`) shows only when `canSave` is true. "Saving"
means adding to the **library** (below). A source that knows which course a
session belongs to also implements `ParentedContentSource`, so playing a talk
brings its course to the front of the library. What a source knows beyond the seven methods
reaches the screens through optional fields on the shared models, never through
the interface: `PackModel.teacher` and `.attribution`, `PackItemsModel.kind`,
`.teacher`, `.durationMs` and `.date`, and `Track.attribution` (carried into
`PlaybackRequest`). `SourceAttribution` (source, creator, page URL, licence name
and URL) is what a licence asks to be shown where content is played or viewed.

| Repository | Contract / destination |
| --- | --- |
| `lib/repositories/pack/packs_repository.dart` | `PacksRepository`: browsable packs, pack by ID, pack-to-track-ID map (limited for large sources) |
| `lib/repositories/track/track_repository.dart` | `TrackRepository`: source track lookup, then saved download metadata; current-track preferences |
| `lib/repositories/home/home_repository.dart` | `HomeRepository`: home sections; announcements are currently absent |
| `lib/repositories/explore/` | Pack and track search results across sources |
| `lib/repositories/tags/tags_repository.dart` | Tag catalogue and tracks by tag (local catalogue only) |
| `lib/repositories/background_sounds/` | Legacy single-sound catalogue (empty) and session-bell preferences; the bundled library and mixer are in `lib/providers/soundscape/` (see Sounds and the mixer) |

### Dharma Seed (`ds-`)

`lib/services/dharma_seed/`:

- `dharma_seed_client.dart`: the unofficial API (multipart POSTs to
  `/api/1/{teachers,retreats,talks}/`), a Meditejo User-Agent, timeouts and
  backoff on 429/5xx and network errors.
- `dharma_seed_database.dart`: drift over a bundled SQLite. Tables hold
  teachers (no contact fields), retreats (with their talk-ID list), talks,
  talk–teacher pairs, per-kind sync state (edition, pending edition, last
  synced), the fetch queue, and saved retreats and teachers. FTS5 tables
  (`ds_talks_fts`, `ds_retreats_fts`, `ds_teachers_fts`) use
  `unicode61 remove_diacritics 2`; user text becomes quoted prefix terms only.
- `dharma_seed_snapshot.dart` and `dharma_seed_snapshot_writer.dart`: the
  **bundled catalogue** (below).
- `dharma_seed_sync.dart`: teachers, then retreats, then talks. Each kind
  lists IDs (`detail=0`, with the stored edition after the first run), queues
  them in the database, and drains the queue in batches (250/250/500),
  one request at a time with a 750 ms gap. A killed app resumes from the
  queue. Opening a course or talk that is not stored yet fetches it, and its
  teachers, ahead of the background queue on the same lane. **Nothing syncs at
  launch.** `catchUpDharmaSeed` runs the (non-forced) sync when the user opens
  Search or Explore (including a launch that restores Explore), which is due
  when the last full sync is over 12 h old and asks only for what changed since
  the stored editions; pull-to-refresh in Explore and the settings row
  (`DharmaSeedSyncTile`, which shows progress, last sync or failure) force it.
- `dharma_seed_source.dart`: the `ContentSource`. A retreat
  (`ds-retreat-<id>`) is a pack whose items are its talks ordered by
  `rec_date`, then ID. A talk (`ds-talk-<id>`) is a track with one voice and
  one file: the original audio at `https://dharmaseed.org<audio_url>`,
  its duration, the teacher as guide, and the artist link set to the talk's
  dharmaseed.org page. `DharmaSeedKind` (in `dharma_seed_ids.dart`) reads
  `recording_type`; practice kinds allow background sound. Browse lists
  saved retreats, then the 40 most recent. `packTrackIds` covers only saved
  retreats and retreats containing a completed talk, using the retreat's own
  talk list.

#### The bundled catalogue

A fresh install would need all ~49k talks (125 requests, six minutes, 38 MB
transferred on 2026-10-19) before search worked, so the catalogue ships in the
app: `assets/dharma_seed/catalogue.sqlite.gz` (a `VACUUM INTO` copy of the
catalogue database with its FTS indexes merged, gzipped: 13 MiB for 49,007
talks, 35 MiB unpacked) and `catalogue.json` (the manifest: format and database
schema versions, `asOf`, the per-kind `edition` cursors, row counts, unpacked
size and SHA-256, and the `asset` pin, below). It holds catalogue text only,
never audio, and no user data (saved rows and the fetch queue are emptied).

**Only the manifest is in git.** The gzip is a git-ignored file, fetched at
build time from an asset on a `catalogue-YYYYMMDD` **prerelease** of
`beejsbj/meditejo`. `catalogue.json`'s `asset` section (`release`, `name`,
`bytes` and the `sha256` of the gzip) pins exactly which snapshot a commit
builds with, so a build is reproducible from the commit alone. A prerelease
because the in-app updater reads `releases/latest`, which never returns one,
and because the updater also refuses any tag that is not `v<MAJOR.MINOR.PATCH>`
(`docs/fork/UPDATES.md`). `tools/meditejo/catalogue.py` is the one tool:
`fetch`, `check`, `publish` and `verify-apk`.

- **Install** (`DharmaSeedSnapshot.installIfNeeded`): `DharmaSeedDatabase.open()`
  runs it inside the lazy opener, so it happens before the database file is
  first opened, with no network. It unpacks when the device has no complete
  catalogue (no file, or any kind never finished its first sync) or when the
  manifest's `asOf` is later than the newest per-kind `last_synced_at` on the
  device ("the snapshot is newer than local data"). A device that has synced
  any kind since the snapshot was made keeps its data, and its own incremental
  sync continues from its own cursors. The unpack runs in a worker isolate (the
  UI thread is not blocked by the inflate): it writes
  `dharma_seed.sqlite.installing`, checks size and `user_version` against the
  manifest, and carries the old `ds_saved` rows across when it replaces a file;
  a failure at any of these (including a locked or full disk while reading or
  copying the saves) abandons the install with the old database untouched. Only
  then is the old file renamed to `.previous`, stale `-wal`/`-shm`/`-journal`
  files removed, and the new one renamed into place; a crash between the two
  renames is undone on the next launch (`.previous` comes back if the database
  is missing, and is deleted if it is not). An old file that is not a readable
  catalogue holds nothing to keep and is replaced. Any failure leaves what was
  there and the app falls back to the ordinary first sync. A snapshot whose manifest or database schema this build
  does not read is ignored. It takes about 0.45 s on bjslab
  (`tools/meditejo/dharma_seed_install_time.dart`), then the first search takes
  about 60 ms.
- **Delta**: the unpacked database carries the sync state, so the ordinary
  incremental sync continues from the snapshot's editions: three ID listings
  and the detail records for what changed (3 requests, about 2 s when nothing
  has). It runs when the user opens Search or Explore, never at startup;
  startup only reads the state (`prepareDharmaSeed`), which is also what first
  touches the database and so triggers the install in the background.
- **Build** (`tools/meditejo/dharma_seed_snapshot.dart`, a `flutter test` file
  because the sync imports Flutter): runs the app's own polite sync (serial,
  750 ms apart) starting from the snapshot in `assets/dharma_seed` (which
  `catalogue.py fetch` put there), so a refresh is a delta of a few requests,
  or from nothing (`DS_FRESH=true`) a full sync. It refuses an unfinished
  sync, and leaves the files untouched when the sync changed no record.
  **`release.sh` runs it before the version bump only when the pinned snapshot
  is over 30 days old** (`--refresh-catalogue` forces it, `--skip-snapshot`
  never runs it). When the snapshot changed, `catalogue.py publish` uploads it
  as a new prerelease, checks it by downloading it back, and pins it in
  `catalogue.json`; the release commit holds the manifest alone.
- **Fetch.** `catalogue.py fetch` downloads the pinned asset over HTTPS from the
  public release URL (no token), refuses a size or SHA-256 mismatch, a missing
  asset or a manifest with no pin, and moves the file into place only once it
  verifies. It runs in `meditejo-apk.yml`, `ci-develop.yml` and the inherited
  `release.yml` and `smoke-test.yml` builds, and by hand for local work
  (`docs/fork/BUILD.md`). After the APK is built, `catalogue.py verify-apk`
  compares the packaged gzip and manifest with the pin. `build_apk.sh` and
  `release.sh` check the pin is downloadable before spending a CI run.
- **Shipping choice**: a release asset fetched in CI, not committed and not
  Git LFS (BRIEF decision 17, 2026-10-26; before it the 13 MiB gzip was
  committed, which cost about 13 MiB of history per refresh. The old commits
  keep their copies; the history was not rewritten). An LFS pointer in an asset
  would build an app with no catalogue and no error, so every route fails loudly
  instead: `fetch` and `verify-apk` exit non-zero, and
  `test/services/dharma_seed/dharma_seed_snapshot_test.dart` fails on a missing,
  pointer-sized, wrong (hash differs from the pin) or schema-stale snapshot. The
  trade is that a checkout needs one network step before a full test run or
  build.

`DharmaSeedSource` also carries the Dharma Seed screens' reads, outside the
interface until a second source shows what is shared: `explore({group})`,
`search(query, {length})`, `teacherPage(id)` and `teacherTalks(id, offset)`.
They return the view models in `dharma_seed_models.dart` (`DsExplore`,
`DsSearchResults`, `DsTeacherPage`, `DsTeacherItem`). `DsContentGroup` (practice
or talks, from `recording_type`; `dsPracticeRecordingTypes` is the list the SQL
filters on) and `SessionLength` (`lib/models/explore/session_length.dart`, the
`[min, max)` minute buckets) are the filters. `lib/providers/dharma_seed/
dharma_seed_ui_providers.dart` holds the Explore chip, the saved toggle and the
Explore, search and teacher providers.

### The library and imports (`lib-`)

`lib/services/library/`. The user's library is **their own database**
(`meditejo_library.sqlite`, `LibraryDatabase`), apart from the Dharma Seed
catalogue database: that one is a replaceable copy of someone else's catalogue
(it is replaced by a newer bundled snapshot when one ships), this one is the user's data.

- `library_database.dart`: `LibraryEntries` (one row per kept thing: source ID,
  kind `course | single | teacher`, detected and overridden Practice/Talks group,
  title and a title override, subtitle, artwork, item count, length, added and
  last-played time), `PlaybackPositions` (Resume), `LibCourses` and `LibTracks`
  (imported content), `LibraryMeta` (flags).
- `library_store.dart`: `LibraryStore` over it. Entries are listed most recently
  added or played first; `revision` and `positionsRevision` notifiers drive the
  providers. Its `prepare` hook runs once before first use: the app passes
  three steps in `library_migration.dart`, each marked done in `LibraryMeta`:
  `migrateDharmaSeedSaves` copies `ds_saved` (old "Save course" / "Save teacher")
  into the library, keeping the saved time (the old table is left in place);
  `reclassifyLibraryDefaults` moves Dharma Seed retreats the user has not
  classified themselves to Practice, once; and `seedStarterSet` adds the starter
  set on a first run (below).
- `lib_source.dart`: `LibSource`, the `ContentSource` for `lib-`. A feed or a set
  of files is a pack (`lib-course-<hash>`); a URL, an episode or a file is a track
  (`lib-track-<hash>`). `pack()` lists sessions oldest first (or newest first, a
  per-course setting); `track()` returns one voice with the original audio
  address or the path of the copy in app storage. Every course carries an
  attribution (feed site, author, licence when the feed states one), so the page
  reads as a course. Removing an entry deletes the imported content and any
  copied file.
- IDs (`lib_ids.dart`) are stable: a feed or URL hashes its address (adding it
  twice finds the first), an episode hashes feed address plus the feed's own
  episode ID (the same episode has one ID alone or in its course), a local file
  gets a random ID when it is copied.
- `starter_set.dart` is the one small data file listing what a fresh install
  already holds (BRIEF decision 13): retreats 4496, 1084, 1183 and 1308 as
  Practice courses, and talk 60864 as a single that follows its own label. The
  YouTube slice appends its two playlists there (a TODO comment holds their
  URLs). `seedStarterSet` runs in the library's first-use hook: with no
  `starter_seeded` flag **and an empty library** it adds the items, described from
  the on-device catalogue with no network (a missing one is added under the
  title in the data file), the first leading the list; either way it sets the
  flag, so an install that already had things is left alone and nothing the user
  removes comes back.
- **Practice or Talks by default** (`LibraryDraft.group`, the `detected_group`
  column; the user's choice is `group_override`): a Dharma Seed **retreat is
  always Practice**, since Dharma Seed files most of Rob Burbea's guided retreat
  sittings as "Talk"; a **single Dharma Seed talk follows its own
  `recording_type`** (guided meditation and chanting → Practice; talk, Q & A,
  other and untyped → Talks); the host-based Talk default
  (`isKnownTalkHost`) is kept only for feeds and audio links on dhammatalks.org
  and audiodharma.org; everything else is Practice.
- `link_classifier.dart` (text only, no network): Dharma Seed retreat, teacher or
  talk page; audio by extension; YouTube; Apple Podcasts; a service with no
  readable feed (Spotify); any other web address; a local path. `firstLinkIn`
  finds the link in shared text.
- `feed_parser.dart`: RSS 2.0 and Atom, iTunes tags, enclosures (audio only),
  `media:content`, durations as seconds / `mm:ss` / `hh:mm:ss` (or missing),
  RFC 822 and ISO dates, Creative Commons licence links, relative URLs. Episodes
  come out oldest first: a serial feed follows its episode numbers, otherwise
  dates, otherwise the feed is read backwards.
- `import_service.dart`: `resolve(text)` and `resolveFiles` return an
  `ImportPreview` (title, source, artwork, count, total length and whether it is
  complete, first items, attribution, whether it is already kept, the allowed
  kinds); `add(preview, choice)` stores it and adds the library entry. Looking
  stores nothing. A link costs one request, two when a web page must be searched
  for its feed or an Apple Podcasts link looked up; Dharma Seed links cost what
  opening them already does. Failures are `ImportFailure(reason)`, which the
  screen turns into a plain sentence. Files are moved (a picker or share cache
  copy) or copied into `<support>/library/<id>.<ext>`; audio is never changed.
- `import_http.dart`: the one HTTP client for imports: a Meditejo User-Agent, a
  timeout, an 8 MiB body cap, redirects followed, no body read for audio or a 304.
- `feed_refresher.dart`: looks for new episodes in kept feeds 10 s after launch,
  a feed at most every 12 h, one at a time, with `If-None-Match` /
  `If-Modified-Since`; a failure is remembered with its time.
- `playback_position_tracker.dart`: fed by the player's state from the main
  screen. While playing it saves at most every 5 s without notifying; a pause
  saves and notifies; a finished session forgets its place; the first play
  touches the session and its course. A place under 10 s or within 20 s of the
  end is not kept. `PlaybackRequest.startPositionMs` carries it to the player,
  which seeks once the file is loading.
- `share_intake.dart` and `MainActivity.kt`: the Android share target (see below).

Providers are in `lib/providers/library/`. `ImportService` takes the pickers,
clipboard reader and share intake as providers, so tests need no platform.

### Library screens

- **Library tab** (`lib/views/library/library_view.dart`): Practice, Talks,
  Teachers; a row menu to move between Practice and Talks, rename (library only),
  pin a course to Home, or remove (an import asks first, since its audio is
  deleted). It is the third of four tabs (below), where Home used to link to it.
- **New course** (the Library app bar): makes a personal course (below) and
  opens it.
- **Add** (`import_view.dart`): a link field with Paste and Preview, a clipboard
  suggestion, Choose files / Choose a folder, then the preview and one primary
  action, Add to library. Course/Single appears where both make sense (a feed:
  the whole feed or just its latest episode; several files: a course or separate
  singles); Practice/Talk defaults to the detected group, Practice when unknown.
- **Share target**: `AndroidManifest.xml` registers `text/plain`, `audio/*`
  (send and send-multiple) and an audio view filter on `MainActivity`. The
  activity copies shared audio into `cache/shared_audio` off the main thread
  (the sender's read permission ends with the share), then hands the link or
  files to Dart over the `meditejo/share` channel: once for the share that
  started the app (`getInitial`), then `onShare` for later ones.
  `ShareIntakeHost` wraps the main screen and opens Add, previewed.

### Screens

- **Tabs** (`lib/views/bottom_navigation/`): **Home · Explore · Library ·
  Settings**. `MainTab` and `mainTabProvider` (`lib/providers/main_tab_provider.dart`)
  hold the selected tab, so any screen or link can move it; the main screen
  listens, drops the keyboard, and on Explore loads its lists and runs the
  Dharma Seed catch-up. Android back from any other tab returns Home. The
  saved tab (`last_main_tab_index`, with `main_tab_layout` = 2 saying which bar
  wrote it) restores Home, Explore or Library, never Settings. The first bar
  (Home · Explore · Search · Settings) only ever saved 0 or 1, which mean the
  same now; any other value opens Home, and the first launch rewrites the pair.
  `meditejo://home`, `explore`, `library` and `search` (Explore with the cursor
  in its field, via `exploreFocusRequestProvider`) select a tab and close what
  is open above it (`tabForLink` in `lib/routes/routes.dart`). Track and pack
  links, the Up Next widget and the share target push pages as before.
- **Explore** (`lib/views/explore/`) is find-something-to-add, with a **search
  field at the top**. Nothing typed: Practice and Talks chips and the starter
  suggestions (`searchSuggestions`), then the library's courses ("In your
  library", under any chip: a filter never hides what the user kept), courses
  (`PackGridSliver`), saved teachers and teachers (`TeacherStrip`), and, with a
  chip chosen, the latest sessions (`SessionRowsSliver`). `LibraryStateCard`
  explains the first sync. Pull to refresh runs an incremental sync. Typing
  (400 ms debounce, not ASCII-filtered) replaces that with `SearchResults`
  (`lib/views/search/`): Teachers, Courses, Talks, with the length pills over
  the talks, and the usual `AddToLibraryIcon` on courses and talks.
  `exploreSearchProvider` (`lib/providers/explore/`) merges the library into
  Dharma Seed's result: courses and talks from the other sources (imports,
  YouTube) first, then anything else already in the library, then the rest of
  Dharma Seed, each item once; followed teachers lead. Library imports carry no
  length, so the length filter leaves them out while it is on.
- **Course page** is `PackView` (`lib/views/pack/`). A pack with a teacher, an
  attribution or session kinds is a course: progress line, next session, Save
  course, Sessions / Summary / Teacher tabs, day headings for long retreats
  (`_dayGroups`) and the credit footer. The play button is the existing
  `PackPlayButton`. Rows are `PackItemWidget`, which shows kind, title, teacher,
  length, downloaded and played state when the item carries them.
- **Teacher page** (`lib/views/teacher/teacher_view.dart`): photo, bio, Save
  teacher, courses, talks (30 at a time). Opened with
  `handleNavigation(TypeConstants.teacher, [id])`.
- **Track details and player** show `AttributionNotice` from
  `Track.attribution` / `PlaybackRequest.attribution`.
- **Artwork:** `GeneratedArtwork` is the fallback for anything without a
  picture. `NetworkImageWidget(seed: …)` draws it for a missing or failed image.

Guide and duration preferences live in `lib/providers/guide_name_preference_provider.dart`
and `lib/providers/duration_preference_provider.dart`. Session bell preferences
belong to `BackgroundSoundsRepository`.

Catalogue metadata belongs behind these repositories. Remote audio download is
separate: `lib/services/download_service.dart` streams generic URLs to a temporary
file, then renames it only after success. It sends no Medito credentials.

## Player

`lib/models/player/playback_request.dart` is the resolved playback boundary:
track/file IDs, title, description, artwork, URL or local path, duration,
background-sound support and optional guide/artist metadata.
`PlaybackRequest.fromTrack` copies a `Track` and an already selected voice/file
into the request; variant selection happens before this call. A source with
expiring URLs should resolve them when creating the request. Timer requests use
the same player, generated by `lib/models/timer/timer_session.dart`.

Keep source IDs stable through requests, downloads, favourites and completion.
The player and native completion queue must see the same track ID. A session
left partway is resumed: `startSession`, the track page and Downloads read the
saved place (`withResumePosition`) into `PlaybackRequest.startPositionMs`.
A track with one voice and one file plays at once from a course's main action;
only a track with real choices and no remembered preference opens its page. The player
shows `PlaybackRequest.attribution` (a compact credit under the title) and, for
a track with no cover, its generated art blurred behind the controls.

## Sounds and the mixer

Background soundscapes are a bundled **library** of looped recordings played
by a **mixer** of layers. Synthesised layers (noise colours, drone, binaural)
arrive through the same mixer in slice 7's second PR.

**Generated layers** (`lib/models/soundscape/synth.dart`) use the ids
`synth-noise`, `synth-drone` and `synth-binaural`, with their settings as JSON in
`SoundLayer.params`, so presets and the Customize sheet carry them like any
other layer.

* **Noise** (`lib/services/soundscape/synth/noise_generator.dart`): a colour
  (white, pink or brown: power falls 0, 3 or 6 dB an octave) and ten octave
  bands, 31 Hz to 16 kHz, interpolated in dB. It is built as a spectrum with
  seeded random phases and an inverse FFT of 2^20 samples, a 21.8 s stereo
  loop that is periodic and therefore seamless. Its BS.1770 loudness is
  computed from the spectrum through the K-weighting response and set to
  −27 LUFS. It is generated in a `compute` isolate and loaded as an in-memory
  WAV. A settings change regenerates it and crossfades it in near the old
  loop's position, with equal power.
* **Drone**: SoLoud sine oscillators for a chord on the root: the root, a
  0.15% detuned twin, the octave and the fifth, plus upper partials for warm
  and bright. Each voice swells on its own incommensurate period, scaled by
  `movement`.
* **Binaural beats**: two sines, `carrier ± beat/2`, panned absolutely, one
  per ear. They need headphones, and every view of them says so.
  Oscillators retune in place, phase-continuously.

**Library.** `assets/sounds/*.opus` (Ogg Opus loops) and
`assets/sounds/sounds.json`, the licence-as-data the app reads
(`SoundLibrary`, `lib/models/soundscape/sound_library.dart`). Each entry has its
id, title, category (`rain · water · wind · forest · fire · room · night`),
asset, licence (`CC0-1.0 | CC-BY-3.0 | CC-BY-4.0 | PD`, anything else is
ignored), author, source page, and its processing record.
`tools/meditejo/sounds/process_sounds.py` writes the JSON, `assets/sounds/NOTICE`
and `tools/meditejo/sounds/commands.log` from `tools/meditejo/sounds/sources.json`.
Never edit the outputs by hand; change the manifest and rerun (see the script's
docstring for the loop, loudness and encoding steps). The sounds keep their own
licences, outside the AGPL; Settings › licences lists the mixer's native code
(`assets/licenses/soloud-native-components.json`), and **Sound credits** (from
the Sounds sheet) lists every recording.

**Engine.** `SoundscapeEngine` (`lib/services/soundscape/soundscape_engine.dart`)
is implemented on **flutter_soloud 4.1.7** (pinned; see DECISIONS 2026-10-19,
slice 7). Recordings are decoded into memory and loop sample-accurately; every
change fades; *drift* is SoLoud's LFO on the layer volume; the master volume is
SoLoud's global volume. SoLoud plays its own output stream beside the session
player's ExoPlayer; Android mixes them. Without the native library (a test
host) the engine plays nothing rather than throwing. A layer is one or more
voices (one per oscillator for a drone or binaural beats); every voice,
including the old loop of a noise crossfade, goes through the same pause fade,
stop and idle shutdown as a recording's.

**Keep-alive.** Sounds playing *on their own* hold `SoundscapeService`
(`android/.../SoundscapeService.kt`, a `mediaPlayback` foreground service with a
Stop action and audio focus) over the `meditejo/soundscape` channel. Under a
session the session's `AudioPlayerService` keeps the app alive and the mixer
follows `audioStateProvider.isPlaying`; Dart never holds both.

**Controller.** `soundscapeProvider` (`SoundscapeController`,
`lib/providers/soundscape/soundscape_provider.dart`) owns the state and
reconciles it to the engine, one pass at a time. Persistence: shared
preferences `soundscape_mix`, `soundscape_presets`, `soundscape_volume`,
`soundscape_session_defaults`.

### API for the player's Customize sheet

The sheet's **Background sound** row should drive the mixer only through these
(stable) members; the Sounds sheet (`showBackgroundSoundSheet`) is the place to
build or edit a mix.

```dart
// What to play, as a string the cue settings can store:
//   'mix' or ''      the current mix (as left on the Sounds sheet;
//                    CueSettings.soundscape keeps '' for "kind default")
//   'preset:<id>'    a preset (state.presets: starters + the user's)
//   'sound:<id>'     one library sound
//   'none'           silence
SoundscapeSelection.parse(String) / selection.encode()

final state = ref.watch(soundscapeProvider);   // SoundscapeState
state.mix, state.presets, state.playing, state.owner, state.volume (0–1)
state.sessionDefault(SoundscapeSessionKind.practice | .talks)
ref.watch(soundLibraryProvider)                // FutureProvider<SoundLibrary>

final mixer = ref.read(soundscapeProvider.notifier);
mixer.startSession(kind, {SoundscapeSelection? selection,   // session starts
                           SoundscapeSessionDefault? override});
mixer.setSessionPaused(bool) / mixer.endSession();             // follows session
mixer.play(SoundscapeSelection, {double? volume});             // play now
mixer.togglePlay() / pause() / resume() / stop();
mixer.setVolume(double);          // under a session: that kind's level
mixer.sessionDefault(kind) / mixer.setSessionDefault(kind, value);
mixer.setSessionVolume(kind, double);  // that kind's level, live if it runs
```

`SoundscapeSessionDefault` is `{enabled, selection, volume}`; both kinds start
off, with nothing chosen (BRIEF decision 17; decision 8 had Practice on). A
one-time migration (`SoundscapeStore.migrateSessionDefaults`, rule in
DECISIONS.md, 2026-10-26) moves an untouched existing install the same way and
leaves anyone who chose a sound alone. It is the single source of truth
for a kind's on/off, selection and volume: Customize's Background sound row
writes kind-wide choices through `setSessionDefault` and `setSessionVolume`.
A course override keeps only a selection, in `CueSettings.soundscape` (empty:
the kind's default); the player passes it to `startSession(kind, selection:)`,
which uses it for on/off and what plays but keeps the kind's volume.
`override:` replaces the whole default and is kept for callers with their own
setting.

**Session wiring today.** `PlayerView` sets the kind
(`BackgroundSoundsNotifier.setSessionKind`, with the scope's Customize
selection, from the session's cue scope, so a
course's Practice/Talks classification wins over the recording's
`hasBackgroundSound`) and calls `playBackgroundSoundFromPref()`, which starts
the soundscape session; `stopBackgroundSound()` ends it, and a session that
ends natively (the end screen opens without stopping the player, so the end
bell's tail survives) ends it directly. Bells belong to the cue scheduler
(Session cues and Customize); the legacy ambient layer follows Customize
through `applyCueSettings`. The player's bottom row keeps the sound button,
which opens the Sounds sheet, beside Customize.

## Completion, stats and favourites

`lib/providers/pack/pack_provider.dart` combines raw pack items with
`LocalAllStats.tracksChecked`. A track item is checked when its ID is present.
A nested pack is checked when its nonempty track-ID set is entirely checked;
`fetchPackTrackIds()` must include descendant tracks. Repeated tracks contribute
to each containing pack, which is how a session listed in several personal
courses counts in each (see "Sessions in several courses"). No server marks completion.

A session is complete when playback reaches its end (ExoPlayer `STATE_ENDED`,
or `completed` on iOS, with `SessionCompletionGate`'s 5 s guard). There is no
percentage threshold. Opening a course, a talk or the player writes nothing;
only that path, a row's toggle and "mark all" write `tracksChecked`.

`StatsManager` persists `local_all_stats`; `completed_tracks_storage` retains
native completions until they are processed. Additive `completionReceipts` in the
same stats record acknowledge `[kind, trackId, originalEndTimestampMs]` events,
where kind is `completion` or `repeat`. Old records default to no receipts.
Receipts survive session deletion so delayed native replay cannot restore a
deleted session. Writes are serialized; callbacks join pending work and only
acknowledge a successful save. Queue drains remove acknowledged entries from
the current queue, preserving newly enqueued completions.

Local day-boundary, streak and
consistency calculations, manual sessions, home widgets, local reminders and
optional Health writes remain. Favourites use SharedPreferences only.

Existing on-device downloads, their full saved `Track` metadata and favourites
are preserved without deleting data or filtering IDs by source. Downloads builds
playback requests directly from this metadata; favourite track links resolve it
through `TrackRepository.fetchTrack` when the catalogue entry is unavailable.
Favourites alone store card metadata, not a playable track: a favourite without
a catalogue entry or saved download remains unavailable. Pack favourites still
require a catalogue pack entry. The player prefers the downloaded audio file
when present and otherwise uses the saved URL; retaining metadata does not
ensure that an old remote URL still works.

The local unavailable exception currently becomes a generic error with retry
in track and pack views. Those views do not yet show a dedicated unavailable
state.

## Home composition

Home is a launchpad (BRIEF decision 14), not a catalogue. `HomeWidgetType`
(`lib/constants/enums/home_widget_type.dart`) names its sections, which the
user can switch on or off and reorder in Customize (the Organize Home Layout
screen, from the button beside the title). `homeWidgetOrderProvider` keeps the
order (`homeWidgetOrder`) and `homeHiddenWidgetsProvider` the sections switched
off (`homeWidgetHidden`). Defaults, all on: **upNext → quickLinks → pinned**.
`upNext` keeps its old saved name for what is now **Continue**. Sections an
earlier version saved (shortcuts, carousel, quote) are ignored. The consistency
score and streak are not on Home; they live on the stats screen (reached from
Settings), whose copy says the numbers are feedback, not a score.

- **Continue** (`continueItemsProvider`, `lib/services/home/continue_rules.dart`
  for the ordering). Up to three items, from any source:
  (1) a session left partway (a saved place in the library database; it resumes
  there), and (2) a library course with some sessions done and some not, with
  no session left partway (its next session). A course shows once. Order:
  Practice before Talks (the entry's group, else the course's, else whether the
  session allows background sound), then most recently played. One tap runs
  `startSession`, which resumes. With nothing in progress it offers the next
  unfinished session of the first pinned course, else of the first course in the
  library (the starter set leads a fresh install), so Home is not empty. The
  first item also feeds the Android Up Next widget.
- **Quick links**: Timer (Medito's timer), Sounds (the background-sound
  picker) and Add (import).
- **Pinned courses** (`pinnedCoursesProvider`, `pinned_course_ids`): at most
  three, each with its progress, opening the course. Pinned from a library
  row's menu or a course page; a fourth is refused with a message. The course
  that used to be Home's single "Up Next" pin becomes the first pin.
- Playing a course no longer pins it; Continue follows what is played.

### YouTube (`yt-`)

`pigeons/youtube.dart` defines the Android `YoutubeExtractorApi`: complete
playlist metadata, single video metadata and a fresh best audio-only stream.
`YoutubeExtractorBridge` uses pinned NewPipeExtractor v0.26.5 off the main
thread. Typed extraction failures never expose stack traces to the UI.

`lib/services/youtube/youtube_source.dart` registers beside `ds-` and `lib-`.
The library database's schema 2 adds `YoutubeVideos` and `YoutubePlaylists`;
ordered ID lists permit shared and repeated videos. Track IDs are
`yt-video-<id>`, courses `yt-playlist-<id>`, and a single video kept as Course
uses a synthetic `yt-playlist-single-<id>`. `track()` resolves an audio-only URL
and caches it only in memory with an expiry margin. `PlayerProvider` and the
downloader re-enter the source before playback/download, so cached UI models
cannot replay expired addresses. Persistent track and end-screen metadata
strip signed URLs. Local download filenames are stable by ID (`.audio`).

The existing Add screen handles YouTube paste and share text through the same
classifier and preview. Whole-title talk/lecture words select Talks;
otherwise Practice. Watch links with a playlist can keep the full ordered
course or only the addressed video. Playlist attempts are throttled for 12 h,
including failures; opening a course or the delayed feed-refresh pass checks
when due, and the course's pull to refresh forces a check.

## Session cues and Customize

`lib/models/cues/cue_settings.dart` describes the shared cue settings;
`CueSettingsStore` persists defaults by Practice/Talks and optional course ID.
The stored JSON carries `version` 1 (unversioned reads as 1); a newer version,
or anything that fails to decode, reads as the kind's defaults.
`cueScopeForRequestProvider` resolves a course's effective library group before
playback. `CueSchedule` is the pure reference for countdown, start/end bells,
fixed/random intervals, integrated pulse ramps and silent extension.

`CustomizeSheet` is used by `TimerView` as its setup screen and by the player's
sliders action. `PlayerView` optionally shows it before starting; edits update
the active native configuration and the existing ambient player; the
Background sound row drives the soundscape mixer (Sounds and the mixer). The timer
continues to use a sparse local WAV as its primary audio.

`NativeCueController` sends plain configuration over `meditejo/cues`.
Android's `CueEngine` lives in `AudioPlayerService`, with predecoded SoundPool
assets and pure scheduling/listening maths in `CueMath.kt`. It follows media
advance while playing and elapsed realtime during countdown/extension holds.
Swift's `CueScheduler.swift` mirrors those phases, preloads AVAudioPlayers and
receives transport reports from `IosAudioHandler`; its countdown and extension
run without per-beat Dart messages. Both consume missed cues after seeking and
keep the final bell alive through its tail. Native status reports let the UI
show a countdown and the remaining extension without repurposing the source
recording's duration.

Listening completion is independent of terminal playback state. Rendered
ranges are merged so repeated sections count once; a seek rebases the cursor.
An unfinished track's ranges persist with their save time; receipts older than
180 days, or beyond the 200 most recent, are pruned when a session starts.
A 90% receipt records progress while playback continues. A timer qualifies at
its end; a finished extension never stands in for listening. The terminal
state is sent at every true end, earned or not, and opens the end screen only
then. Existing resume positions continue to be saved by the library's
position tracker.

## Personal courses (`my-`)

A course the user makes from sessions anywhere: a Dharma Seed talk, a YouTube
video, a podcast episode, a local file. A course and a playlist are the same
thing (DECISIONS, 2026-10-19 "My courses").

- **Model** (`lib/services/my_courses/my_course_models.dart`): a course is
  `my-course-<16 random hex>`, an ordered list of rows. A row is a session
  reference (any source's track ID, kept as it is: `ds-talk-…`, `yt-video-…`,
  `lib-track-…`) or a heading ("Day 1"). It has a title, a description, a cover
  (one of its sessions' artwork, or empty for `GeneratedArtwork` seeded by the
  course ID) and a Practice/Talks kind, which is its library entry's group
  (default Practice). A session appears at most once per course.
- **Storage**: the library database's schema 3 adds `MyCourses`,
  `MyCourseItems` (rows in `position` order; a heading is a row with an empty
  `item_id`) and `SessionContexts` (below). Each session row keeps a snapshot
  of the session as it was added (title, teacher, artwork, length, kind) and
  an `unavailable` flag. The course is also a library entry (kind `course`),
  so it is listed, pinned and ranked like any other.
- **Source** (`my_course_source.dart`, `MyCourseSource`, registered last in
  `contentSourcesProvider`): `pack()` returns the rows as `PackItemsModel`s with
  their own IDs and paths, so PackView, the player, downloads, Resume and
  completion need no changes. Each session is re-read from its own source
  (8 s limit) and its snapshot refreshed; only `CatalogueEntryUnavailable`
  from the owning source marks it unavailable, and being offline or slow
  shows the snapshot as it was. A heading becomes `PackItemsModel.section` on
  the sessions under it; PackView draws the headings (`_sectioned`) instead of
  its date grouping. `track()` owns nothing. `packTrackIds()` lists every
  personal course (few, all the user's own) with its available sessions.
  `searchPacks` matches titles and descriptions for Explore search. Changes bump
  `revision`, which `packDataProvider` (for `my-` IDs) and `packTrackIdsProvider`
  follow.
- **Unavailable sessions**: `PackItemsModel.unavailable`. The row stays, faded
  and labelled "Unavailable" in words; a tap explains instead of opening it.
  `PackModel.playableTracks` (in `pack_model.dart`) is the sessions that can
  be played. The play button, the progress line and edge, "mark all", Continue
  and `packTrackIds` count only those. A session that comes back is available
  again the next time the course opens.
- **Making and editing** (`lib/views/my_courses/`): `my_course_actions.dart`
  holds the New course dialog (name, Practice/Talks), the "Add to course…"
  sheet (the user's courses, ticked when they already hold everything being
  added, plus New course), Make my own copy, Delete, and `ContentActionsButton`,
  the row "⋮" that offers them. `my_course_edit_view.dart` edits title,
  description, kind and cover, and drags, removes or adds headings; nothing is
  written until Save, and leaving with changes asks.
- **Entry points**: the Library tab's New course button; "⋮" on library rows
  (not teachers), on course and session rows from Dharma Seed, Explore search and
  teacher pages, and on a course page's session rows (which also offer "Remove
  from this course" in a personal course); the course page's bottom-bar "⋮"
  (Add to course…, Make my own copy, and Edit and Delete for the user's own);
  the track page's bottom bar (Add to course). The player is untouched.
- **Copying a course** (`duplicate`) reads any source's course in its order
  (with headings, from a personal course) into a new personal one called
  "<title> (my copy)", with the original's kind, description and cover, then
  opens it and its editor. The original is not changed.
- **Deleting** removes the course's rows, its session contexts and its library
  entry. The sessions, their own library entries, saved places and downloads
  stay. Removing an import from the library warns when personal courses list
  it; they keep its row, which then shows as unavailable.

**Sessions in several courses.** Completion and Resume belong to the session
ID, as everywhere else: finishing a session ticks it in every course that lists
it, and its saved place is the same from any of them. What depends on the
course is attribution. Opening a session from a course page (its row or the
play button) records that course in `SessionContexts`. Continue then credits
the session ("Session 2 of 6", the course's title and progress) to that course
while it still lists it, and otherwise to the session's own source course
(`ParentedContentSource`). Playing it brings both courses to the front of the
library.
