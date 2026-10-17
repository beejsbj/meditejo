# Local content and playback seams

The app launches without accounts, credentials or a network connection. The
bundled catalogue is empty; content comes from sources such as Dharma Seed,
whose metadata syncs in the background after launch and is read from an
on-device database. The timer uses bundled bells and a locally generated silent
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

| Repository | Contract / destination |
| --- | --- |
| `lib/repositories/pack/packs_repository.dart` | `PacksRepository`: browsable packs, pack by ID, pack-to-track-ID map (limited for large sources) |
| `lib/repositories/track/track_repository.dart` | `TrackRepository`: source track lookup, then saved download metadata; current-track preferences |
| `lib/repositories/home/home_repository.dart` | `HomeRepository`: home sections; announcements are currently absent |
| `lib/repositories/explore/` | Pack and track search results across sources |
| `lib/repositories/tags/tags_repository.dart` | Tag catalogue and tracks by tag (local catalogue only) |
| `lib/repositories/background_sounds/` | Empty ambient catalogue; local volume/preferences retained |

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
- `dharma_seed_sync.dart`: teachers, then retreats, then talks. Each kind
  lists IDs (`detail=0`, with the stored edition after the first run), queues
  them in the database, and drains the queue in batches (250/250/500),
  one request at a time with a 750 ms gap. A killed app resumes from the
  queue. Opening a course or talk that is not stored yet fetches it, and its
  teachers, ahead of the background queue on the same lane. Automatic syncs
  run 3 s after launch, at most every 12 h; the settings row
  (`DharmaSeedSyncTile`) shows progress, last sync or failure, and refreshes
  on tap.
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
The player and native completion queue must see the same track ID.

## Completion, stats and favourites

`lib/providers/pack/pack_provider.dart` combines raw pack items with
`LocalAllStats.tracksChecked`. A track item is checked when its ID is present.
A nested pack is checked when its nonempty track-ID set is entirely checked;
`fetchPackTrackIds()` must include descendant tracks. Repeated tracks contribute
to each containing pack. No server marks completion.

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

`HomeWidgetType` and `lib/providers/home/widget_order_provider.dart` define the
saved section order. Defaults: **upNext → shortcuts → carousel → quote**. Stats
and the header sit outside that reorderable list. Removed/unknown saved section
names are ignored. The timer shortcut works with an empty catalogue. A future
“Continue your practice” section belongs in `upNext`; populate it from a pinned
source course plus the same local pack-completion data.
