import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/meditation/downloaded_track_ids_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/categories/entry_labels.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';

/// What the Library tab shows: one kind, or everything.
enum LibraryFilter { all, courses, playlists, singles, teachers, downloads }

/// How the Library orders what it shows, within Practice and Talks.
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

/// The Library's controls. The filter and Practice/Talks are for this visit;
/// the sort and layout are kept.
@immutable
class LibraryViewOptions {
  const LibraryViewOptions({
    this.filter = LibraryFilter.all,
    this.group,
    this.sort = LibrarySort.recent,
    this.layout = LibraryLayout.list,
    this.label,
  });

  final LibraryFilter filter;

  /// A category's ID or a label of the user's own (its key), or null for
  /// everything. It narrows what the kind filter shows; teachers have none.
  final String? label;

  /// Practice or Talks; null for both.
  final LibraryGroup? group;
  final LibrarySort sort;
  final LibraryLayout layout;

  LibraryViewOptions copyWith({
    LibraryFilter? filter,
    ValueGetter<LibraryGroup?>? group,
    LibrarySort? sort,
    LibraryLayout? layout,
    ValueGetter<String?>? label,
  }) => LibraryViewOptions(
    filter: filter ?? this.filter,
    group: group == null ? this.group : group(),
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

  void setGroup(LibraryGroup? group) =>
      state = state.copyWith(group: () => group);

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

/// Practice's or Talks' share of the library: courses and playlists, then
/// singles.
@immutable
class LibraryShelf {
  const LibraryShelf(
    this.group, {
    this.courses = const [],
    this.singles = const [],
  });

  final LibraryGroup group;
  final List<LibraryEntry> courses;
  final List<LibraryEntry> singles;

  bool get isEmpty => courses.isEmpty && singles.isEmpty;
}

/// The library as the tab shows it under its current options: Practice
/// before Talks (decision 11), each sorted, then saved teachers.
@immutable
class LibraryArrangement {
  const LibraryArrangement({this.shelves = const [], this.teachers = const []});

  final List<LibraryShelf> shelves;
  final List<LibraryEntry> teachers;

  bool get isEmpty => shelves.every((s) => s.isEmpty) && teachers.isEmpty;
}

/// Filters and sorts [entries] (in the store's most-recent-first order) by
/// [options]. Teachers have no Practice or Talks, so they show under All
/// with neither chosen, or under their own filter.
LibraryArrangement arrangeLibrary(
  List<LibraryEntry> entries,
  LibraryViewOptions options, {
  Map<String, CourseProgress> progress = const {},
  Set<String> downloaded = const {},
  Map<String, EntryLabels> labels = const {},
}) {
  final label = options.label;
  bool labelled(LibraryEntry e) =>
      label == null || (labels[e.sourceId]?.hasLabel(label) ?? false);
  bool shows(LibraryEntry e) =>
      labelled(e) &&
      switch (options.filter) {
        LibraryFilter.all => e.kind != LibraryKind.teacher,
        LibraryFilter.courses => e.isCourse && !isMyCourseId(e.sourceId),
        LibraryFilter.playlists => e.isCourse && isMyCourseId(e.sourceId),
        LibraryFilter.singles => e.kind == LibraryKind.single,
        LibraryFilter.teachers => false,
        LibraryFilter.downloads =>
          e.kind != LibraryKind.teacher && downloaded.contains(e.sourceId),
      };

  final sorted = _sorted(entries, options.sort, progress);
  final groups = options.group == null ? LibraryGroup.values : [options.group!];
  final teachersShown =
      label == null &&
      (options.filter == LibraryFilter.teachers ||
          (options.filter == LibraryFilter.all && options.group == null));
  return LibraryArrangement(
    shelves: [
      for (final group in groups)
        LibraryShelf(
          group,
          courses: [
            for (final e in sorted)
              if (e.group == group && e.isCourse && shows(e)) e,
          ],
          singles: [
            for (final e in sorted)
              if (e.group == group && e.kind == LibraryKind.single && shows(e))
                e,
          ],
        ),
    ],
    teachers: teachersShown
        ? [
            for (final e in sorted)
              if (e.kind == LibraryKind.teacher) e,
          ]
        : const [],
  );
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
