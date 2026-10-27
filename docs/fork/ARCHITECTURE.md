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
  (imported content; a track has `license_name` / `license_url` too, since schema 4,
  for an episode added on its own: a session in a course reads its course's licence),
  `LibraryMeta` (flags). Schema changes are `onUpgrade` steps in `library_database.dart`;
  `test/services/library/lone_episode_licence_test.dart` shows how to test one against an
  older file.
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
  reads as a course; a lone episode carries the feed's licence on its own row
  and `trackAttribution` uses it when there is no course. Removing an entry deletes the imported content and any
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
- `import_defaults.dart`: the one table of what each kind of link or pick
  arrives as (`importDefaults`, keyed by `ImportShape`): every list is a Course
  by default, one recording is a Single, and it says which of the two the user
  may choose between. The resolvers read it; they do not decide.
- `folder_import.dart`: folder import on Android (below): `FolderImporter`,
  its `ChannelFolderImporter` over `meditejo/folder`, and `FolderProgress`.
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

- **Library tab** (`lib/views/library/library_view.dart`). From the top:
  **In progress** (`inProgressItemsProvider`: everything Continue would offer,
  unlimited and without its fallback) as large cards that start the session;
  the kind chips (All, Courses, Playlists, Singles, Teachers, Downloads);
  Practice or Talks (a segmented switch, neither chosen shows both), the sort
  (Recent, A–Z, Progress) and the grid or list switch; then Practice before
  Talks, each with courses and playlists as cards (art, source, detail,
  progress) and singles as compact rows, then saved teachers. The options are
  `libraryViewOptionsProvider` (`lib/providers/library/library_view_provider.dart`);
  the sort and layout are kept in preferences (`library_sort`,
  `library_layout`), the filter and Practice/Talks are not. `arrangeLibrary`
  there is the pure filter and sort, unit-tested. Every entry keeps its menu
  (`LibraryEntryMenu`): move between Practice and Talks, rename (library
  only), pin a course to Home, add to a playlist, copy as playlist, edit or
  delete a playlist, or remove (an import asks first, since its audio is
  deleted; a catalogue item has Undo). Downloads lists singles that are
  downloaded and courses with a downloaded session
  (`libraryDownloadedIdsProvider`). An empty library, or an empty filter,
  points to Explore (selects the tab) and Add.
- **New course** (the Library app bar): makes a personal course (below) and
  opens it.
- **Add** (`import_view.dart`): a link field with Paste and Preview, a clipboard
  suggestion, Choose files / Choose a folder, then the preview and one primary
  action, Add to library. Course/Single appears where both make sense (a feed or
  playlist: the whole list, or one episode; several files: a course or separate
  singles); Practice/Talk defaults to the detected group, Practice when unknown.
  **Single from a list means picking an episode.** The preview carries the list
  as `ImportEpisode`s (a feed's newest first, a playlist in its own order) with
  `defaultEpisodeId` chosen: a feed's latest, the video in a watch link, else a
  playlist's first. The Episode row names the current pick and *Change* opens
  `EpisodePickerSheet` (`episode_picker.dart`: title, date, length; a search
  field above 12 episodes). The pick travels as `ImportChoice.episodeId`, and
  `ImportService.selectedId` says which library ID the choices would add, so the
  preview knows whether *that* episode is already kept. A picked episode has the
  same ID alone or inside its course (`lib_ids.dart` / `youtube_ids.dart`), so
  adding it again, in either form, finds it.
- **Folder import (Android)**: since Android 11 an app cannot list a folder by
  path, so *Choose a folder* goes through the Storage Access Framework.
  `FolderImportBridge` (`android/.../folder/`, channel `meditejo/folder`) opens
  `ACTION_OPEN_DOCUMENT_TREE`, and `AudioTreeScanner` walks the granted tree
  with `DocumentsContract` queries (one per folder, subfolders included,
  hidden entries skipped, playlists that merely carry an audio MIME type
  ignored), collecting audio by MIME type and extension in natural name order,
  folder by folder. `FolderCopier` then copies it off the main thread into
  `cache/folder_import` as `001-name.ext`, reporting progress, skipping files
  it cannot read (reported, not hidden) and removing everything if the user
  cancels or the phone fills. Dart drives the calls in order (`pick`, `scan`,
  `copy`; `cancel`, `discard`) and gets ordinary `PickedFile`s, so the preview,
  Course or separate Singles, and Add are the existing path. On Add, files in a
  temporary directory are **moved** into app storage when they can be (a
  failure moves them back), so a big folder is never on the disk twice. The
  permission is temporary and is never persisted; there is no "keep in sync".
  Limits: 1,000 audio files and 16 folders deep (a sentence, not a crash).
  Leaving the Add screen calls `discard`. iOS and desktops still list the
  folder by path (`resolveDirectory`).
- **Share target**: `AndroidManifest.xml` registers `text/plain`, `audio/*`
  (send and send-multiple) and an audio view filter on `MainActivity`. The
  activity copies shared audio into `cache/shared_audio` off the main thread
  (the sender's read permission ends with the share), then hands the link or
  files to Dart over the `meditejo/share` channel: once for the share that
  started the app (`getInitial`), then `onShare` for later ones.
  `ShareIntakeHost` wraps the main screen and opens Add, previewed.

### Screens

- **Tabs** (`lib/views/bottom_navigation/`): **Home · Explore · Sounds ·
  Library · You** (BRIEF decision 18). `MainTab` and `mainTabProvider`
  (`lib/providers/main_tab_provider.dart`) hold the selected tab, so any screen
  or link can move it; the main screen listens, drops the keyboard, on Explore
  loads its lists and runs the Dharma Seed catch-up, and on Sounds retries a
  failed legacy background-sound fetch. Android back from any other tab
  returns Home, except that on Sounds an open mix panel folds first
  (`SoundsViewState.collapseMix`, through a `GlobalKey`). **`MainTab`'s order
  is a saved format** (`last_main_tab_index`, with `main_tab_layout` saying
  which bar wrote it; now 3). `MainTab.restore` maps a saved index through
  the bar that wrote it (`_olderLayouts`): the first bar (Home · Explore ·
  Search · Settings, no layout) saved only 0 or 1; layout 2 (Home · Explore ·
  Library · Settings) keeps Home, Explore and Library, and its Settings is
  You. You is never restored or saved (nor Settings before it); an index that
  names nothing, or an unknown layout, opens Home; the first launch rewrites
  the pair in layout 3's terms. Tab icons are Material Symbols
  (`material_symbols_icons`, rounded, filled when selected); `MeditoNavItem`
  takes an `IconData`. **You** shows `YouView` (the stats summary and the settings
  groups; see "You and Settings"), in one line of `_page`. `meditejo://home`, `explore`,
  `sounds`, `library`, `you`, `settings` (You) and `search` (Explore with the
  cursor in its field, via `exploreFocusRequestProvider`) select a tab and
  close what is open above it (`tabForLink` in `lib/routes/routes.dart`).
  Track and pack links, the Up Next widget and the share target push pages
  as before.
- **Explore** (`lib/views/explore/`) is find-something-to-add, with a **search
  field at the top** (Material's `SearchBar`). Nothing typed: Practice and
  Talks chips and the starter suggestions (`searchSuggestions`), then the
  library's courses ("In your library", a strip of small cards, under any chip:
  a filter never hides what the user kept), Dharma Seed courses as a strip of
  large cards with Add to library on the art, saved teachers and teachers
  (`TeacherStrip`), and the latest sessions (`SessionRowsSliver`): guided
  practice unless Talks is chosen. `LibraryStateCard` explains the first sync.
  Pull to refresh runs an incremental sync. Typing (400 ms debounce, not
  ASCII-filtered) replaces that with `SearchResults` (`lib/views/search/`):
  Teachers, Courses, Talks, with the length chips over the talks, and the
  usual `AddToLibraryIcon` on courses and talks.
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

## Categories and labels

Practices can be browsed and filtered by category (BJS-586). Two layers on one
model: **categories** are a curated list the app ships; **labels** are the
user's own words on library items. A label the user types that names a
category *is* that category; anything else is a label of their own.

- **The asset** (`assets/categories/categories.json`, parsed by
  `CategoryCatalogue`, `lib/services/categories/`). `format` is the layout
  this build reads, `version` and `updated` the edition of the curation (bump
  `version` by hand whenever the mapping changes). It holds:
  - `categories`: ID, name, a one-line blurb and aliases. Metta, Vipassanā,
    Jhāna, Samatha, Open awareness, Breath, Body, TMI, Sankalpa, Emptiness.
    Names are practice terms and live here, not in the `.arb` files.
  - `curated`: content IDs (`ds-retreat-4496`, `ds-talk-60864`, or another
    source's ID) with their categories and the item's name. A curated entry
    **replaces** the keyword rules for that ID; `"categories": []` says "none of
    the guesses apply" and is how a false positive is silenced. Names are a
    typo guard: `categories_asset_test.dart` checks every `ds-` ID exists in the
    bundled snapshot and that its name still matches.
  - `rules`: per category, `title` terms and a stricter `description` list.
    Terms are whole words after folding (case, diacritics and punctuation
    ignored: Jhāna = jhana), phrases are consecutive words, and a trailing `*`
    makes the last word a prefix (`jhan*`). Descriptions mention everything in
    passing, so only distinctive words are allowed there (jhana, samatha,
    anapanasati, …).
- **Precedence, one rule everywhere:** the user's labels, then the curated
  mapping, then the keyword rules. A talk with no entry of its own also takes
  its retreat's categories (`classify(inherited:)`). The guesses are computed
  on read, never stored, so a new catalogue or a new asset edition changes only
  the guesses.
- **The user's labels** are `LibraryLabels` in `meditejo_library.sqlite`
  (schema 5), keyed by content ID: a row either *adds* a label (a category ID,
  or the folded text of a label of their own with the text as typed) or
  *excludes* an automatic category. `resolveLabels` (`entry_labels.dart`)
  applies them: guesses, minus exclusions, plus additions (additions show
  `CategorySource.user`). They sit in the user's own database, not the
  replaceable Dharma Seed one, and removing an entry leaves them, so Undo and
  re-adding find them again. `LibraryStore.userLabels / addLabel /
  excludeCategory / clearLabel` are the only writers.
- **`CategoryService`** reads and edits: `labelsOfEntries`, `labelsOf`,
  `setCategory`, `addLabel`, and `listing(categoryId)`. A category page is the
  library's entries with that category (exact, including the user's), plus
  Dharma Seed: the curated retreats and talks, then what the rules find
  through the on-device FTS index (title terms in `name` / `title`,
  description terms in `description`; the rules re-check each hit, because the
  index is looser and knows nothing of curated exclusions). Up to 30 rule
  courses and 30 rule sessions per group, curated ones always. Retreats with
  no stored talks are left out; a session whose retreat is already listed is
  not repeated. Retreats are Practice; sessions follow `recording_type`.
- **Screens, kept thin** (`lib/views/categories/`): `ExploreCategoryChips` (a
  chip per category on Explore), `CategoryView` (Practice, then Talks: the
  library's entries, then catalogue courses, then sessions), `LabelsSheet`
  (opened from a library entry's menu: category chips, the user's own labels,
  a field to add one) and `CategoryChips` (course and session pages). The
  Library gets a row of category and label chips under the kind chips
  (`libraryLabelOptionsProvider`; `LibraryViewOptions.label`, not kept between
  visits); `arrangeLibrary` filters on it.
- Medito's own tag system (server-sent tag catalogue, track → tag map, goal
  tags like sleep and anxiety) was deleted with this: nothing fed it, and it
  had no way to hold a user's label.

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

**Library.** `assets/sounds/*.opus` (the **bundled** Ogg Opus loops; the rest
are the downloadable sound pack, below) and
`assets/sounds/sounds.json`, the licence-as-data the app reads
(`SoundLibrary`, `lib/models/soundscape/sound_library.dart`), which lists every
sound, bundled or not. Each entry has its
id, title, category (`rain · water · wind · forest · fire · room · night`),
file, whether it is bundled, its SHA-256 and size, licence (`CC0-1.0 | CC-BY-3.0 | CC-BY-4.0 | PD`, anything else is
ignored), author, source page, and its processing record.
`tools/meditejo/sounds/process_sounds.py` writes the JSON, `assets/sounds/NOTICE`
and `tools/meditejo/sounds/commands.log` from `tools/meditejo/sounds/sources.json`.
Never edit the outputs by hand; change the manifest and rerun (see the script's
docstring for the loop, loudness and encoding steps). A manifest entry names its
original by `downloadUrl` (BigSoundBank, OpenGameArt) or by `"freesound": <id>`.
A Freesound original needs Burooj's authorised app: on a cache miss the script
asks `meditejo-freesound-fetch info` for the live licence (it stops on anything
but the licence the manifest declares, CC0 or CC BY), then `get` for the file, a
few seconds apart. That tool holds the OAuth tokens; the script never sees them.
The original is cached outside the repo and pinned by SHA-256, so a cached,
pinned original builds anywhere, and without the tool anything else stops with
a message. Each entry's `processing.seam` records the loop's seam on the encoded
file (level step and third-octave spectral distance across the wrap, beside the
loop's own p95 elsewhere); `python3 -I -m unittest discover -s tools/meditejo -p
'test_sounds.py'` tests the source kind and the metric with a fake tool. A CC BY
sound must carry its credit (original title, author, page URL): it is in NOTICE
and, marked "attribution required", on Sound credits. The sounds keep their own
licences, outside the AGPL; Settings › licences lists the mixer's native code
(`assets/licenses/soloud-native-components.json`), and **Sound credits** (the
Sounds screen's app-bar button and its last row) lists every recording.

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

### The sound pack

Sounds are a separate download (2026-10-27). The APK ships a **core set** (each
sound `"bundled": true` in `tools/meditejo/sounds/sources.json`): every layer of
a starter preset, so the presets work offline, plus one sound for each shelf.
Every other sound is a file on a `sounds-YYYYMMDD` **prerelease** of
`beejsbj/meditejo`, like the Dharma Seed catalogue's `catalogue-YYYYMMDD`.

* **Pinning.** `sounds.json` holds each sound's `file` (`<id>.opus`), `sha256`
  and `bytes`, and a top-level `pack` section: `{release, digest, files,
  bytes}`. The download URL is `<release downloads>/<release>/<file>`; nothing is
  asked of the GitHub API at run time. `digest` hashes the pack sounds'
  `id sha256 bytes` lines, so any change to a pack sound makes the pin stale
  (`sound_pack.py verify` and the release script both say so). Old pack releases
  are never deleted: an installed app pins the one it shipped with.
* **Tooling** (`tools/meditejo/sound_pack.py`, standard library only):
  `verify` (library, NOTICE and `assets/sounds` agree, offline, run in CI),
  `status`, `check` (HEAD every pinned file), `fetch` (download the pack into
  `build/sound-pack`), `publish` (upload `build/sound-pack` as a new prerelease
  with a copy of the manifest and `NOTICE`, so the credits travel with the recordings; read every file back, then
  pin it) and
  `verify-apk` (the APK holds exactly the bundled sounds and none of the pack).
  `process_sounds.py` writes bundled loops to `assets/sounds/` and the others to
  `build/sound-pack/` (not in git), and keeps the `pack` pin.
  `release.sh` publishes a new pack when the sounds changed since the pin and
  commits `sounds.json` alone; `build_apk.sh` and the APK workflow `check` the
  pin. **CI downloads no sound**: the bundled ones are in git, and tests read
  `sounds.json` only.
* **The updater never sees it.** The in-app updater reads `releases/latest`
  (prereleases excluded) and accepts only a `vX.Y.Z` tag; tests cover both
  (`github_release_client_test.dart`, `update_release_test.dart`).
* **On the phone.** `SoundPackFiles` / `SoundPackDownloader`
  (`lib/services/soundscape/sound_pack_service.dart`) keep files in the app's
  support directory (`sound_pack/`), named `<id>-<first 12 hex of sha256>.opus`.
  A download streams into a `.part` file, is checked for size and SHA-256 and
  renamed into place; any mismatch deletes it and fails as `integrity`. Only
  `https://github.com/beejsbj/meditejo/releases/download/` URLs are fetched.
  On start the folder is scanned (whole files only) and stale or partial files
  are removed. A downloaded file is trusted by name and size afterwards; one that
  will not decode fails like any sound that cannot be played.
* **State.** `soundPackProvider` (`SoundPackController`,
  `lib/providers/soundscape/sound_pack_provider.dart`): the `downloaded` ids, a
  `downloads` map (queued, downloading with progress, failed with why), and the
  Wi-Fi-only setting (`sound_pack_wifi_only`, default **on**). One download at a
  time; nothing downloads unless asked (a card, Download all, a message's
  Download, Retry). With Wi-Fi only on and the phone on mobile data, jobs wait
  (`waitingForWifi`) and start when Wi-Fi returns, or at once for **Download
  anyway**. Wi-Fi and Ethernet count as unmetered (`connectivity_plus`).
* **The mixer.** A layer whose sound is in the library but not on the phone
  stays in the mix (a preset or saved mix is never rewritten) and is left out of
  what plays (`_isAvailable`). When a mix starts, or a download finishes or is
  deleted, the mixer says which sounds it leaves out, once per change
  (`soundMissingNoticeProvider`); `SoundMissingListener`, mounted in
  `MaterialApp.builder`, shows "Playing without …" (or "Nothing to play yet: …")
  with a **Download** action, and a note if the download waits for Wi-Fi. A sound
  that finishes downloading joins a mix that is playing. Downloaded recordings
  play from `FileLoopSource`, bundled ones from `AssetLoopSource`.
* **Screens.** A card for a sound that is not on the phone shows its size and a
  download arrow where the + is; its tap downloads (a ring while it arrives; tap
  cancels), and a failed one shows a retry. Under the presets,
  `SoundPackBanner` offers **Download all**, then progress with Cancel, "Waiting
  for Wi-Fi" with **Download anyway**, or failures with Retry; it is gone when
  everything is here. The mix dock says "n sounds in this mix need downloading.
  The rest plays."; each such layer has a **Needs download** line, and a preset
  card says how many of its sounds are missing. **Settings › Library &
  downloads** has "Downloaded sounds" (how many, how much, Delete after
  asking) and "Download sounds on Wi-Fi only". Sound credits and NOTICE list
  every sound, downloaded or not.

### API for the player's Customize sheet

The sheet's **Background sound** row should drive the mixer only through these
(stable) members; the Sounds screen (`SoundsView`: the Sounds tab, or
`openSoundsPage` over anything else) is the place to build or edit a mix.

```dart
// What to play, as a string the cue settings can store:
//   'mix' or ''      the current mix (as left on the Sounds screen;
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
which opens the Sounds screen as a page (`openSoundsPage`), beside Customize.

**The Sounds screen** (`lib/views/soundscape/sounds_view.dart`, BRIEF
decisions 16 and 18) is presentation over the controller above; it adds no
mixer state. Presets are a row of `PresetCard`s and the library a grid of
`SoundCard`s per shelf, both on `GeneratedArtwork` (`sound_cards.dart`), three
cards across a phone (`SoundGridMetrics`: cells at most 140 dp wide, which
grows past 1.3× text so a phone falls back to two columns); a
shelf's colour and Material Symbol come from `SoundLook`
(`sound_labels.dart`, with the localised labels). The current mix
(`sound_mix_panel.dart`: `SoundsMixHeader`, `SoundsMixBody`,
`AnimatedMixLayers`) is docked at the foot, opening on
`MeditejoMotion.expressiveSpatial`; at 840 dp or wider it is a panel beside
the library. An empty mix stays docked. Layers enter and leave through an
`AnimatedList` diffed against the mix, whoever changed it. **Mute** is
`setLayerVolume(id, 0)` plus the old level in `layerUnmuteVolumesProvider`
(in memory), so a mix or preset saved while muted keeps the layer silent.
Entry points: Home's Sounds tile selects the tab; the player's sound button
and Customize's Background sound sub-sheet ("Edit your mix in Sounds") push
it full height with `openSoundsPage`, where back folds an open mix before
closing.

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

### Practice time (the stats page)

Each `LocalAudioCompleted` also carries, from the stats-page release on,
`durationMs`, `kind` (`practice` or `talks`) and `courseId`/`courseTitle` (the
title as it was then). All four are additive and nullable; earlier entries are
never back-filled, so they read as days practised, not minutes (a timer's
length is still read from its `timer-<seconds>` id).

- **Where they are filled.** `StatsManager.addAudioCompleted` stores the
  duration it is given and the label passed in. `handleStats` asks
  `labelSessionCompletion` (`lib/services/stats/session_label.dart`) for the
  label: the player registers, when it starts a session, the kind and course
  its cue scope resolved (`SessionLabelRegistry`), so stats and cues agree; a
  completion replayed after the app was killed falls back to the library
  group. Timers are Practice; manual entries are Practice.
- **Repeat passes** add their minutes to the same track's latest entry that has
  a length (`AudioCompletionTracker.addRepeatListeningTime(trackId:)`), as well
  as to `totalTimeListened`; they still add no session. Deleting a session takes
  back the minutes it recorded (an older entry recorded none).
- **Aggregation** is pure: `PracticeSummary.from(stats, now:, dayOffset:)`
  (`lib/services/stats/practice_summary.dart`) gives today, this week (Monday
  to today), this month, all time (the running `totalTimeListened`), the last 30
  days, the days practised, the Practice/Talks split and a ranking of courses
  and sources. `practiceSummaryProvider` feeds it the history, the day boundary
  and `practiceClockProvider`.
- **Screens.** `StatsScreen` (`lib/views/stats/`) and its `widgets/` (bar chart,
  month heat-map, breakdown) read the summary. History (add and delete
  sessions) is its second tab.

## You and Settings

`YouView` (`lib/views/you/you_view.dart`) is the You tab's body: a stats
summary card that opens `StatsScreen`, then `SettingsSections`
(`lib/views/settings/settings_sections.dart`), the settings in groups: Practice,
Sounds & cues, Library & downloads, Appearance, Notifications & reminders and
About (version, `UpdateSection` with Check for updates, the AGPL notice, source,
credits, licences, debug info). It is one widget, so a tab hosts it as
`const YouView()`, which is what `MainTab.you` does. `SettingsScreen` is the
same body titled "Settings", for the `settings` link.
The old Advanced, Manage defaults and About screens are gone: their rows are in
the groups. When an update is waiting, About moves to the top of the page, and
Home's update notice's View selects the You tab.

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

Home is a launchpad (BRIEF decision 14), not a catalogue. It opens with the
Meditejo mark: today's (`homeMarkProvider`, see "Identity: marks and
palettes"), or the one the user pinned with a long-press. It moves only while
it can be seen; the sections follow. `HomeWidgetType`
(`lib/constants/enums/home_widget_type.dart`) names its sections, which the
user can switch on or off and reorder in Customize (the Organize Home Layout
screen, from the button beside the title). `homeWidgetOrderProvider` keeps the
order (`homeWidgetOrder`) and `homeHiddenWidgetsProvider` the sections switched
off (`homeWidgetHidden`). Defaults, all on: **upNext → homeShortcuts → pinned**.
`upNext` keeps its old saved name for what is now **Continue**, and
`homeShortcuts` still reads its old saved name `quickLinks`
(`HomeWidgetType.tryParse`; saving writes the new one). **Home draws no
section headings** (BRIEF decision 19): spacing and grouping separate the
sections, and `HomeSectionHeader` (`home_styles.dart`) gives each one an undrawn
`Semantics(header: true)` label (`upNextTitle`, `homeShortcutsTitle`,
`homePinnedTitle`) so TalkBack still announces the groups. The same strings
name the sections in Customize. Sections an
earlier version saved (shortcuts, carousel, quote) are ignored. The consistency
score and streak are not on Home; they live on the stats screen (reached from
the You page), whose copy says the numbers are feedback, not a score.

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
  first item also feeds the Android Up Next widget. `inProgressItemsProvider`
  reads the same items with no limit and no fallback, for the Library's In
  progress; both start an item with `startContinueItem`.
- **Shortcuts** (`lib/views/home/widgets/shortcuts/`): Timer (Medito's timer), Sounds (the background-sound
  picker), up to two **sound presets** (`homeSoundPresetsProvider`: the
  user's own, newest first, then the built-ins) and Add (import). A preset
  tile starts the timer at once (`startTimerSession`,
  `lib/views/timer/start_timer.dart`) with the preset as that session's
  background: `PlaybackRequest.soundscape`, which the player prefers over the
  scope's Customize choice, so the user's saved choices are untouched.
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
fixed/random intervals, the halfway bell, integrated pulse ramps and silent
extension.

`CustomizeSheet` is used by `TimerView` as its setup screen, by the player's
sliders action and by Settings' Practice and Talks rows. `PlayerView`
optionally shows it before starting; edits update the active native
configuration and the existing ambient player; the Background sound row drives
the soundscape mixer (Sounds and the mixer). The timer continues to use a
sparse local WAV as its primary audio.

The sheet is sections (Bells, Rhythm, Time, Sound, Flow; Time first for the
Timer) under a pinned header with the scope and a Finishes at pill. Each row
(`_ExpandingRow`, keyed `customize_<part>`) shows its value and opens its
controls in place, one at a time. Durations and counts are `WheelPicker`s
(`lib/widgets/inputs/wheel_picker.dart`, keyed `wheel_<label>`): snap, a
haptic per row, one `onChanged` when the wheel rests, typed entry through
`parseEntry`, one adjustable semantics node. Levels stay sliders.

**Halfway.** `CueSettings.intervalHalfway` replaces the every-N-minutes bells
with one bell at the midpoint of session time (`intervalMinutes` is kept for
switching back). Natively it is `HalfwayCue` (`CueMath.kt`, mirrored in
`CueScheduler.swift`): pending until crossed, re-armed by every `armAll`,
due at half the session end the engine measures (extension and speed
included), consumed silently when more than the interval tolerance late.

**Bells.** Each cue stores its own bell (`startSound`, `intervalSound`,
`endSound`) as a bundled asset path, validated against `cueBellSounds`, the one
catalogue (display name to asset path, in picker order; `''` is Off). The path
is the stored id and what both native cue banks load, so adding a bell is: a
WAV under `assets/audio/`, an entry in the map, a line in `assets/audio/NOTICE`.
The ten new bells are synthesised by `tools/meditejo/generate_bells.py`
(`--check` proves byte-identical regeneration; `tools/meditejo/bells_report.py`
prints per-file numbers and builds the sampler). A bell the build does not know
reads as the default. The Customize sheet's three bell rows share `_BellList`:
tapping a row selects it and rings it once through `SessionBellPreview` at the
bell volume; a folded row's play button rings the chosen bell; folding the
list or closing the sheet stops it. `CueBellCatalogueTest` (Kotlin)
reads the Dart catalogue, so the native side and the list cannot drift.

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

**Naming: "my course" in code = "Playlist" in the UI** (BRIEF decision 18). What
the user makes is a Playlist; what comes from a source (a retreat, a YouTube
playlist, a feed, an imported folder) stays a Course. Class names, tables,
providers and `my-course-…` IDs keep the old name, so there is no migration, and
the code and this section below still say "course" for a playlist. Only the
strings (`myCourse*` keys in `lib/l10n`, plus `playlistKind`) changed. Where
both kinds share a list (the Library, Explore's "In your library", search),
`playlistAwareDetail` (`lib/views/my_courses/playlist_label.dart`) leads a
playlist's line with "Playlist · "; its own page shows "Playlist" where a course
shows its source.

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

## Theme and design tokens

Material 3 Expressive (BRIEF decision 16). Tokens (the default palette and
scheme variant, corner scale, spring motion schemes, the M3 type scale with
Expressive's emphasized styles) live in `lib/constants/theme/tokens.dart`;
`meditejoTheme(brightness, [palette])` in `app_theme.dart` builds `ThemeData`
from them and from the active identity palette (`palette_theme.dart`, below).
`main.dart` passes `activePaletteProvider`, so changing the palette re-themes
the whole app, animated over `MeditejoMotion.medium`.
The M3 type scale is the `ExpressiveTypography` theme extension
(`context.typography`); `ThemeData.textTheme` still carries Medito's text-role
sizes for screens not yet redesigned (`text_theme.dart`), coloured from the
scheme. Redesigned screens use `context.typography`, `MeditejoShapes` and
`MeditejoMotion` rather than literals. The tab bar and sidebar are Material's
`NavigationBar` and `NavigationRail`; a tab is a `MainTab` value plus an arm
in each of `BottomNavigationBarView`'s `_page` and `_navItem` switches, and,
because the order is saved, a new `MainTab.layout` with its restore rules.

## Identity: marks and palettes

BRIEF decisions 19 to 21. The generator from the identity exploration
(round 2 on `fork/mark-explore`, d040d58f) is ported to Dart, seed for seed.

- **`lib/services/identity/` (pure Dart, no Flutter):**
  - `seeded_random.dart`: the page's string hash and mulberry32, in 32-bit
    arithmetic. The order of calls is part of every mark.
  - `stroke_engine.dart`, `mark_generator.dart`: the three families (gesture,
    minimal, atmospheric) build a `MarkSpec` from a seed (`r2:` prefixed).
  - `mark_spec.dart`: a built mark, everything needed to draw it, with JSON
    (`v: 1`). **A pin stores this, frozen**, so a later generator never
    redraws a kept mark. Bump `formatVersion` if the JSON changes shape;
    an unreadable pin falls back to the daily mark.
  - `mark_outline.dart`: pebble outlines and settled-frame paths, shared by
    the painter and the icon tool.
  - `daily_mark.dart`: the local date picks the family and is the seed
    (`m-2026-10-26`); the daily palette walks one fixed shuffle. A day whose
    gesture would draw the retired double loop takes `<seed>-b`.
  - `palettes.dart`: the nine palettes (four mark roles, light and dark
    neutrals). Their order is part of the daily shuffle: add at the end.
- **`lib/widgets/branding/`:** `MarkRenderer` draws a `MarkSpec` at a moment
  of its life on a unit canvas (a port of the page's draw code, with the
  print finish from `mark_textures.dart`). `MeditejoMark` drives it with a
  ticker that runs only while visible (scroll, `Visibility`, `TickerMode`,
  app lifecycle) and shows the settled frame under reduced motion.
  `home_mark_sheet.dart` pins and unpins.
- **`lib/providers/identity/identity_providers.dart`:** `identityDayProvider`
  (`refresh()` from `main.dart`'s minute tick and on resume; no timer of
  its own),
  `paletteChoiceProvider` (`daily` or a palette id; default Tidewater),
  `activePaletteProvider`, `pinnedMarkProvider` (frozen JSON in
  `identity_pinned_mark`), `dailyMarkProvider` and `homeMarkProvider`. The
  mark and the palette are chosen and pinned independently.
- **Palette → scheme (`lib/constants/theme/palette_theme.dart`):** ramps
  from the palette's form colour with Material's neutral variant
  (`MeditejoColorTokens.variant`), tertiary from its accent with tonal spot
  (`accentVariant`); the
  palette's neutrals as surfaces and text; text roles held at WCAG AA on
  every surface (`legibleOn`). `MeditejoPalette` (a theme extension) carries
  the palette to the mark, which drops its tile on the app's background and
  takes the text colour for a stroke under 2.2:1.
- **The launcher icon is fixed** (Android can swap icons only through
  activity aliases built into the app). Its geometry is frozen in
  `assets/branding/house_mark.json`; `tools/meditejo/branding/make_icons.py`
  regenerates every platform's icon from it. No build flavour may override
  `ic_launcher` (a test checks).
- **Faithfulness:** `test/widgets/branding/mark_reference_test.dart` compares
  Dart renders with PNGs drawn by the page's own JS
  (`tools/meditejo/branding/reference/`, headless Chrome).

**Shared cards** (`lib/widgets/cards/`), used by Home, the Library, Explore,
search and the teacher page: `PressableCard` (the 96% press dip; Home's
`HomePressable` is a typedef of it), `SectionTitle` (Home's
`HomeSectionTitle` likewise), `CourseCard` (art on top; large, medium or
compact, with `heightFor` so strips grow with the text size) and
`CourseRowCard` (art at the start), `CardArt` (a Dharma Seed cover is the
teacher's portrait, so it is drawn as generated art with the photo as an
avatar), `SessionRow`, `TeacherTile` and `TeacherRow`, and `FilterChipBar`.
Radii and spacing are in `card_tokens.dart`.


## Generated art

`lib/widgets/art/` draws Meditejo's generated art (identity rounds 4 and 5; decisions 20–22).

- **Engine** (`engine/`), a port of the identity page:
  - `canvas2d.dart`: a Canvas 2D context over Flutter's `Canvas`;
  - `art_core.dart`: colour maths as the page does it, palette roles, inks, the params view `P`;
  - `grounds.dart`, `place_grounds.dart`, `figures.dart`, `place_figures.dart`, `bell.dart`: one class per ground and figure, each with a seeded `build` (plain-data params) and a `draw`;
  - `compose.dart`: the meaning map, `Compose.build/buildFor/buildPreset`, the frozen form (`freeze`/`thaw`) and `Compose.draw`;
  - `art_textures.dart`: the noise grain and the baked print finish.
  - **The order of random draws is part of the output.** Changing a builder changes what every generated item looks like, but never a curated one.
- **Subjects** (`art_subject.dart`): `ArtSubject.sound`, `.layers` (a preset or the mix), `.cover(kind, id)` and `.bell(asset, icon:)`. `CuratedArt` loads `assets/art/curated_art.json` at start-up and resolves a subject to a composition: frozen when it ships, built from its id otherwise.
- **Widget** (`art_cover.dart`): `ArtCover(subject:, live:, strike:, scrim:)`. It shows a still raster from `ArtRasters` (an LRU keyed by subject, palette and pixel size) or, when live and allowed, paints every frame at up to 30 fps.
- **Covers** go through `NetworkImageWidget(art:)` and `CardArt(art:)`, with the precedence in `cover_art.dart` (`shownCoverUrl`).
- **Checks:**
  - `test/widgets/art/art_reference_test.dart` (goldens against the page);
  - `art_build_parity_test.dart` (builder against the page; needs `MEDITEJO_ART_REF`);
  - `art_subject_test.dart` (curated, stable by id, no forbidden pairs, the live mix card, reduced motion);
  - `art_benchmark_test.dart` (gated by `MEDITEJO_ART_BENCH=1`).
