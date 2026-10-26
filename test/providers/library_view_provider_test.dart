import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/library/library_view_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

LibraryEntry _entry(
  String id,
  String title, {
  LibraryKind kind = LibraryKind.course,
  LibraryGroup group = LibraryGroup.practice,
}) => LibraryEntry(
  sourceId: id,
  kind: kind,
  detectedGroup: group,
  title: title,
  addedAt: DateTime(2026, 10, 1),
);

List<String> _titles(Iterable<LibraryEntry> entries) => [
  for (final e in entries) e.displayTitle,
];

void main() {
  // In the store's order: most recent first.
  final entries = [
    _entry('ds-retreat-1', 'Jhāna retreat'),
    _entry('my-course-0123456789abcdef', 'Morning sits'),
    _entry(
      'ds-talk-1',
      'A talk on metta',
      kind: LibraryKind.single,
      group: LibraryGroup.talks,
    ),
    _entry('yt-playlist-a', 'Body and breath'),
    _entry('lib-track-x', 'Evening recording', kind: LibraryKind.single),
    _entry('ds-teacher-1', 'Rob Burbea', kind: LibraryKind.teacher),
    _entry('ds-retreat-2', 'Winter talks', group: LibraryGroup.talks),
  ];

  group('arrangeLibrary', () {
    test('All: Practice then Talks, courses before singles, then teachers', () {
      final a = arrangeLibrary(entries, const LibraryViewOptions());
      expect(a.shelves.map((s) => s.group), [
        LibraryGroup.practice,
        LibraryGroup.talks,
      ]);
      expect(_titles(a.shelves[0].courses), [
        'Jhāna retreat',
        'Morning sits',
        'Body and breath',
      ]);
      expect(_titles(a.shelves[0].singles), ['Evening recording']);
      expect(_titles(a.shelves[1].courses), ['Winter talks']);
      expect(_titles(a.shelves[1].singles), ['A talk on metta']);
      expect(_titles(a.teachers), ['Rob Burbea']);
    });

    test('each kind filters to itself', () {
      LibraryArrangement only(LibraryFilter filter) => arrangeLibrary(
        entries,
        LibraryViewOptions(filter: filter),
        downloaded: const {'ds-talk-1', 'yt-playlist-a'},
      );
      List<String> shown(LibraryArrangement a) => [
        for (final s in a.shelves) ...[
          ..._titles(s.courses),
          ..._titles(s.singles),
        ],
        ..._titles(a.teachers),
      ];

      expect(shown(only(LibraryFilter.courses)), [
        'Jhāna retreat',
        'Body and breath',
        'Winter talks',
      ]);
      expect(shown(only(LibraryFilter.playlists)), ['Morning sits']);
      expect(shown(only(LibraryFilter.singles)), [
        'Evening recording',
        'A talk on metta',
      ]);
      expect(shown(only(LibraryFilter.teachers)), ['Rob Burbea']);
      expect(shown(only(LibraryFilter.downloads)), [
        'Body and breath',
        'A talk on metta',
      ]);
    });

    test('Practice or Talks narrows the shelves and leaves teachers out', () {
      final talks = arrangeLibrary(
        entries,
        const LibraryViewOptions(group: LibraryGroup.talks),
      );
      expect(talks.shelves.single.group, LibraryGroup.talks);
      expect(_titles(talks.shelves.single.courses), ['Winter talks']);
      expect(talks.teachers, isEmpty);
    });

    test('A–Z sorts by the name shown, ignoring case', () {
      final renamed = [
        ...entries,
        LibraryEntry(
          sourceId: 'ds-retreat-3',
          kind: LibraryKind.course,
          detectedGroup: LibraryGroup.practice,
          title: 'Zzz',
          titleOverride: 'alpha course',
          addedAt: DateTime(2026, 10, 1),
        ),
      ];
      final a = arrangeLibrary(
        renamed,
        const LibraryViewOptions(sort: LibrarySort.title),
      );
      expect(_titles(a.shelves[0].courses), [
        'alpha course',
        'Body and breath',
        'Jhāna retreat',
        'Morning sits',
      ]);
    });

    test('Progress: furthest along first, then unbegun, finished last', () {
      final a = arrangeLibrary(
        entries,
        const LibraryViewOptions(sort: LibrarySort.progress),
        progress: const {
          'ds-retreat-1': (done: 10, total: 10),
          'my-course-0123456789abcdef': (done: 1, total: 5),
          'yt-playlist-a': (done: 3, total: 4),
        },
      );
      expect(_titles(a.shelves[0].courses), [
        'Body and breath',
        'Morning sits',
        'Jhāna retreat',
      ]);
    });

    test('an empty filter is empty', () {
      final a = arrangeLibrary([
        entries.first,
      ], const LibraryViewOptions(filter: LibraryFilter.playlists));
      expect(a.isEmpty, isTrue);
    });
  });

  test('the sort and layout are kept; the filter is not', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer container() => ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );

    final first = container();
    final notifier = first.read(libraryViewOptionsProvider.notifier);
    notifier.setSort(LibrarySort.title);
    notifier.setLayout(LibraryLayout.grid);
    notifier.setFilter(LibraryFilter.playlists);
    notifier.setGroup(LibraryGroup.talks);
    first.dispose();

    final second = container();
    addTearDown(second.dispose);
    final options = second.read(libraryViewOptionsProvider);
    expect(options.sort, LibrarySort.title);
    expect(options.layout, LibraryLayout.grid);
    expect(options.filter, LibraryFilter.all);
    expect(options.group, isNull);
  });
}
