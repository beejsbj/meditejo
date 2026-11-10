import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/meditation/downloaded_track_ids_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/categories/entry_labels.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';

/// What the Library tab shows: everything, Practice, Talks, saved teachers
/// (decision 18), or what is downloaded. Practice and Talks go by what a
/// course's sessions are (#80).
enum LibraryFilter {
  all,
  practice,
  talks,
  teachers,
  downloads;

  /// Practice or Talks; null for the others.
  LibraryGroup? get group => switch (this) {
    LibraryFilter.practice => LibraryGroup.practice,
    LibraryFilter.talks => LibraryGroup.talks,
    _ => null,
  };
}

/// How the Library is divided: by form, in this order (#80). Saved teachers
/// follow, apart.
enum LibraryForm {
  /// Single sessions.
  sessions,

  /// What the user made.
  playlists,

  /// Courses from a source: retreats, feeds, YouTube series.
  courses,
}

/// How the Library orders what it shows, within each section.
enum LibrarySort {
  /// Most recently played or added first: the store's own order.
  recent,

  /// By name.
  title,

  /// Furthest along first; then what has not been begun; finished last.
  progress,
}

/// Courses and playlists as wide row cards, or as a grid of cards.
enum LibraryLayout { list, grid }

/// The Library's controls. The filter is for this visit; the sort and
/// layout are kept.
@immutable
class LibraryViewOptions {
  const LibraryViewOptions({
    this.filter = LibraryFilter.all,
    this.sort = LibrarySort.recent,
    this.layout = LibraryLayout.list,
    this.label,
  });

  final LibraryFilter filter;

  /// A category's ID or a label of the user's own (its key), or null for
  /// everything. It narrows what the filter shows; teachers have none.
  final String? label;

  final LibrarySort sort;
  final LibraryLayout layout;

  LibraryViewOptions copyWith({
    LibraryFilter? filter,
    LibrarySort? sort,
    LibraryLayout? layout,
    ValueGetter<String?>? label,
  }) => LibraryViewOptions(
    filter: filter ?? this.filter,
    sort: sort ?? this.sort,
    layout: layout ?? this.layout,
    label: label == null ? this.label : label(),
  );
}

final libraryViewOptionsProvider =
    NotifierProvider<LibraryViewOptionsNotifier, LibraryViewOptions>(
      LibraryViewOptionsNotifier.new,
    );

class LibraryViewOptionsNotifier extends Notifier<LibraryViewOptions> {
  @override
  LibraryViewOptions build() {
    final prefs = ref.read(sharedPreferencesProvider);
    T saved<T extends Enum>(List<T> values, String key, T fallback) {
      final name = prefs.getString(key);
      return values.where((v) => v.name == name).firstOrNull ?? fallback;
    }

    return LibraryViewOptions(
      sort: saved(
        LibrarySort.values,
        SharedPreferenceConstants.librarySort,
        LibrarySort.recent,
      ),
      layout: saved(
        LibraryLayout.values,
        SharedPreferenceConstants.libraryLayout,
        LibraryLayout.list,
      ),
    );
  }

  void setFilter(LibraryFilter filter) =>
      state = state.copyWith(filter: filter);

  void setLabel(String? label) => state = state.copyWith(label: () => label);

  void setSort(LibrarySort sort) {
    state = state.copyWith(sort: sort);
    ref
        .read(sharedPreferencesProvider)
        .setString(SharedPreferenceConstants.librarySort, sort.name);
  }

  void setLayout(LibraryLayout layout) {
    state = state.copyWith(layout: layout);
    ref
        .read(sharedPreferencesProvider)
        .setString(SharedPreferenceConstants.libraryLayout, layout.name);
  }
}

/// How many of a course's sessions are done.
typedef CourseProgress = ({int done, int total});

/// Progress of every course the app knows the sessions of, by ID.
final libraryProgressProvider =
    Provider.autoDispose<Map<String, CourseProgress>>((ref) {
      final trackIds = ref.watch(packTrackIdsProvider).value ?? const {};
      final checked = {...?ref.watch(statsProvider).value?.tracksChecked};
      return {
        for (final MapEntry(:key, :value) in trackIds.entries)
          if (value.isNotEmpty)
            key: (
              done: value.where(checked.contains).length,
              total: value.length,
            ),
      };
    });

/// IDs of the library's entries with something downloaded: a single that is,
/// or a course with at least one downloaded session.
final libraryDownloadedIdsProvider = Provider.autoDispose<Set<String>>((ref) {
  final downloaded = ref.watch(downloadedTrackIdsProvider);
  if (downloaded.isEmpty) return const {};
  final trackIds = ref.watch(packTrackIdsProvider).value ?? const {};
  return {
    ...downloaded,
    for (final MapEntry(:key, :value) in trackIds.entries)
      if (value.any(downloaded.contains)) key,
  };
});

/// Whether each library entry shows under Practice, Talks or both (#80), by
/// source ID. Teachers have neither.
///
/// - A Practice or Talks the user chose for the entry ("Move to Talks", or
///   at import) is the one it shows under, alone: the user's word wins.
/// - Otherwise it shows under the kind the app filed it as, and also under
///   any kind its sessions are. So a Dharma Seed retreat (filed as Practice:
///   its sittings are often labelled "Talk") with talks in it shows under
///   both.
///
/// A session's kind is its Dharma Seed `recording_type` ([sessionGroups]).
/// Inside a playlist, which gathers sessions from elsewhere, a session also
/// takes the kind of where it lives: a saved single's own kind (the user's
/// choice for it first, before its recording type), else that of a library
/// course listing it. A source's own course goes by recording types alone,
/// so courses that share sessions do not colour each other. A session none
/// of these covers adds nothing; with no session known, the entry's own kind
/// stands alone. [trackIds] is the sessions of each course, as the device has
/// them.
Map<String, Set<LibraryGroup>> libraryEntryKinds(
  List<LibraryEntry> entries, {
  Map<String, List<String>> trackIds = const {},
  Map<String, LibraryGroup> sessionGroups = const {},
}) {
  final byId = {for (final e in entries) e.sourceId: e};
  // Courses (not playlists) holding each session, for sessions of a source
  // with no kind of their own (a YouTube or feed episode in a playlist).
  final holders = <String, List<LibraryEntry>>{};
  for (final e in entries) {
    if (!e.isCourse || isMyCourseId(e.sourceId)) continue;
    for (final id in trackIds[e.sourceId] ?? const <String>[]) {
      (holders[id] ??= []).add(e);
    }
  }
  LibraryGroup? sessionGroup(String id, LibraryEntry within) {
    final playlist = isMyCourseId(within.sourceId);
    final own = byId[id];
    final single = own != null && own.kind == LibraryKind.single ? own : null;
    if (playlist && single?.groupOverride != null) return single!.groupOverride;
    if (sessionGroups[id] case final group?) return group;
    if (!playlist) return null;
    if (single != null) return single.group;
    return holders[id]?.firstOrNull?.group;
  }

  return {
    for (final e in entries)
      if (e.kind != LibraryKind.teacher)
        e.sourceId: switch (e.groupOverride) {
          final chosen? => {chosen},
          null => {
            e.detectedGroup,
            for (final id
                in e.isCourse
                    ? trackIds[e.sourceId] ?? const <String>[]
                    : [e.sourceId])
              ?sessionGroup(id, e),
          },
        },
  };
}

/// How long the Library waits after Dharma Seed stores more before it reads
/// the kinds again, while a saved retreat's talks are still missing.
const libraryKindsSyncDebounce = Duration(seconds: 5);

/// [libraryEntryKinds] for the library as it stands. It reads only what is
/// on the device (the sessions each course lists, and Dharma Seed's stored
/// talks), never the network. Until it has an answer, and for anything it
/// cannot place, an entry shows under its own kind.
///
/// A course just added is not in the cached [packTrackIdsProvider] yet: its
/// sessions are read for it alone (a Dharma Seed retreat's from its stored
/// record, also when its cached list is empty; another source's from its
/// own few courses). A saved retreat with
/// none of its talks stored yet is read again once the background sync has
/// stored more, at most once per [libraryKindsSyncDebounce]; once its talks
/// are stored, typed or not, it is not waited for.
final libraryEntryKindsProvider =
    FutureProvider.autoDispose<Map<String, Set<LibraryGroup>>>((ref) async {
      var waiting = false;
      Timer? again;
      ref.listen(dharmaSeedRevisionProvider, (_, _) {
        if (waiting) {
          again ??= Timer(libraryKindsSyncDebounce, ref.invalidateSelf);
        }
      });
      ref.onDispose(() => again?.cancel());

      final entries = await ref.watch(libraryEntriesProvider.future);
      final cached = await ref.watch(packTrackIdsProvider.future);
      final dharmaSeed = ref.watch(dharmaSeedSourceProvider);
      final missing = {
        for (final e in entries)
          if (e.isCourse &&
              (!cached.containsKey(e.sourceId) ||
                  // A retreat cached before its record was stored.
                  (cached[e.sourceId]!.isEmpty &&
                      parseDsRetreatId(e.sourceId) != null)))
            e.sourceId,
      };
      var trackIds = cached;
      if (missing.isNotEmpty) {
        final retreats = {
          for (final id in missing)
            if (parseDsRetreatId(id) != null) id,
        };
        final router = ref.read(libraryContentRouterProvider);
        final others = {
          for (final id in missing.difference(retreats)) ?router.sourceFor(id),
        }..remove(dharmaSeed);
        final fresh = await Future.wait([
          if (retreats.isNotEmpty) dharmaSeed.retreatTrackIds(retreats),
          for (final source in others)
            source.packTrackIds().catchError(
              (Object _) => const <String, List<String>>{},
            ),
        ]);
        trackIds = {
          ...cached,
          for (final map in fresh)
            for (final MapEntry(:key, :value) in map.entries)
              if (missing.contains(key)) key: value,
        };
      }
      final ids = {
        for (final e in entries)
          if (e.isCourse) ...?trackIds[e.sourceId] else e.sourceId,
      };
      // Stored talks: with their kind, or null with no recording type.
      final stored = await dharmaSeed.sessionGroups(ids);
      // A saved retreat with none of its talks stored yet.
      waiting = entries.any(
        (e) =>
            e.isCourse &&
            parseDsRetreatId(e.sourceId) != null &&
            !(trackIds[e.sourceId] ?? const []).any(stored.containsKey),
      );
      return libraryEntryKinds(
        entries,
        trackIds: trackIds,
        sessionGroups: {
          for (final MapEntry(:key, :value) in stored.entries) key: ?value,
        },
      );
    });

/// The kinds [entry] shows under, from [kinds] or else its own.
Set<LibraryGroup> _kindsOf(
  LibraryEntry entry,
  Map<String, Set<LibraryGroup>> kinds,
) => kinds[entry.sourceId] ?? {entry.group};

LibraryForm _formOf(LibraryEntry e) => !e.isCourse
    ? LibraryForm.sessions
    : isMyCourseId(e.sourceId)
    ? LibraryForm.playlists
    : LibraryForm.courses;

/// One section of the library: its playlists, its courses or its sessions.
@immutable
class LibraryShelf {
  const LibraryShelf(this.form, {this.entries = const []});

  final LibraryForm form;
  final List<LibraryEntry> entries;

  /// Playlists and courses are cards (rows or a grid); sessions are rows.
  bool get isCards => form != LibraryForm.sessions;

  bool get isEmpty => entries.isEmpty;
}

/// The library as the tab shows it under its current options: Sessions,
/// Playlists, Courses (#80), each sorted, then saved teachers. A section
/// with nothing in it is left out.
@immutable
class LibraryArrangement {
  const LibraryArrangement({this.shelves = const [], this.teachers = const []});

  final List<LibraryShelf> shelves;
  final List<LibraryEntry> teachers;

  bool get isEmpty => shelves.every((s) => s.isEmpty) && teachers.isEmpty;
}

/// Filters and sorts [entries] (in the store's most-recent-first order) by
/// [options], into sections by form. Practice and Talks go by [kinds] (see
/// [libraryEntryKinds]; an entry missing there shows under its own kind).
/// Teachers have no Practice or Talks: they show under All and under their
/// own filter, with no label chosen.
LibraryArrangement arrangeLibrary(
  List<LibraryEntry> entries,
  LibraryViewOptions options, {
  Map<String, CourseProgress> progress = const {},
  Set<String> downloaded = const {},
  Map<String, EntryLabels> labels = const {},
  Map<String, Set<LibraryGroup>> kinds = const {},
}) {
  final label = options.label;
  bool labelled(LibraryEntry e) =>
      label == null || (labels[e.sourceId]?.hasLabel(label) ?? false);
  final sorted = _sorted(entries, options.sort, progress);
  final shown = [
    for (final e in sorted)
      if (e.kind != LibraryKind.teacher &&
          labelled(e) &&
          _matches(e, options.filter, kinds, downloaded))
        e,
  ];
  return LibraryArrangement(
    shelves: [
      for (final form in LibraryForm.values)
        LibraryShelf(
          form,
          entries: [
            for (final e in shown)
              if (_formOf(e) == form) e,
          ],
        ),
    ],
    teachers:
        label == null &&
            (options.filter == LibraryFilter.all ||
                options.filter == LibraryFilter.teachers)
        ? [
            for (final e in sorted)
              if (e.kind == LibraryKind.teacher) e,
          ]
        : const [],
  );
}

bool _matches(
  LibraryEntry e,
  LibraryFilter filter,
  Map<String, Set<LibraryGroup>> kinds,
  Set<String> downloaded,
) => switch (filter) {
  LibraryFilter.all => true,
  LibraryFilter.practice ||
  LibraryFilter.talks => _kindsOf(e, kinds).contains(filter.group),
  LibraryFilter.teachers => false,
  LibraryFilter.downloads => downloaded.contains(e.sourceId),
};

/// How many entries each filter would show, under the chosen [label]: the
/// numbers on the Library's chips. All counts what it shows besides
/// teachers.
Map<LibraryFilter, int> libraryFilterCounts(
  List<LibraryEntry> entries, {
  String? label,
  Set<String> downloaded = const {},
  Map<String, EntryLabels> labels = const {},
  Map<String, Set<LibraryGroup>> kinds = const {},
}) {
  final content = [
    for (final e in entries)
      if (e.kind != LibraryKind.teacher &&
          (label == null || (labels[e.sourceId]?.hasLabel(label) ?? false)))
        e,
  ];
  return {
    for (final filter in LibraryFilter.values)
      filter: filter == LibraryFilter.teachers
          ? label == null
                ? entries.where((e) => e.kind == LibraryKind.teacher).length
                : 0
          : content.where((e) => _matches(e, filter, kinds, downloaded)).length,
  };
}

List<LibraryEntry> _sorted(
  List<LibraryEntry> entries,
  LibrarySort sort,
  Map<String, CourseProgress> progress,
) {
  if (sort == LibrarySort.recent) return entries;
  // The store's order (most recent first) breaks ties.
  final indexed = entries.indexed.toList();
  int rank((int, LibraryEntry) item) {
    final p = progress[item.$2.sourceId];
    if (p == null || p.done == 0) return 1;
    return p.done >= p.total ? 2 : 0;
  }

  double fraction((int, LibraryEntry) item) {
    final p = progress[item.$2.sourceId];
    return p == null || p.total == 0 ? 0 : p.done / p.total;
  }

  indexed.sort((a, b) {
    final int byKey = switch (sort) {
      LibrarySort.title => a.$2.displayTitle.toLowerCase().compareTo(
        b.$2.displayTitle.toLowerCase(),
      ),
      LibrarySort.progress => () {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : fraction(b).compareTo(fraction(a));
      }(),
      LibrarySort.recent => 0,
    };
    return byKey != 0 ? byKey : a.$1.compareTo(b.$1);
  });
  return [for (final (_, e) in indexed) e];
}
