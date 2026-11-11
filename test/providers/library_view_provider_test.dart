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
  LibraryGroup? override,
}) => LibraryEntry(
  sourceId: id,
  kind: kind,
  detectedGroup: group,
  groupOverride: override,
  title: title,
  addedAt: DateTime(2026, 10, 1),
);

List<String> _titles(Iterable<LibraryEntry> entries) => [
  for (final e in entries) e.displayTitle,
];

const _morning = 'my-course-0123456789abcdef';

void main() {
  // In the store's order: most recent first.
  final entries = [
    _entry('ds-retreat-1', 'Jhāna retreat'),
    _entry(_morning, 'Morning sits'),
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

  List<String> shown(LibraryArrangement a) => [
    for (final s in a.shelves) ..._titles(s.entries),
    ..._titles(a.teachers),
  ];

  group('arrangeLibrary', () {
    test('All: Sessions, Playlists, Courses by form, then teachers', () {
      final a = arrangeLibrary(entries, const LibraryViewOptions());
      expect(a.shelves.map((s) => s.form), [
        LibraryForm.sessions,
        LibraryForm.playlists,
        LibraryForm.courses,
      ]);
      expect(_titles(a.shelves[0].entries), [
        'A talk on metta',
        'Evening recording',
      ]);
      expect(_titles(a.shelves[1].entries), ['Morning sits']);
      // Practice and talks side by side: no kind sections any more.
      expect(_titles(a.shelves[2].entries), [
        'Jhāna retreat',
        'Body and breath',
        'Winter talks',
      ]);
      expect(a.shelves.map((s) => s.isCards), [false, true, true]);
      expect(_titles(a.teachers), ['Rob Burbea']);
    });

    test('no In progress section: only the three forms', () {
      expect(LibraryForm.values, [
        LibraryForm.sessions,
        LibraryForm.playlists,
        LibraryForm.courses,
      ]);
    });

    test('Practice and Talks go by kinds, keep the forms, drop teachers', () {
      final kinds = {
        'ds-retreat-1': {LibraryGroup.practice, LibraryGroup.talks},
      };
      final talks = arrangeLibrary(
        entries,
        const LibraryViewOptions(filter: LibraryFilter.talks),
        kinds: kinds,
      );
      expect(shown(talks), [
        'A talk on metta',
        'Jhāna retreat',
        'Winter talks',
      ]);
      expect(talks.teachers, isEmpty);
      final practice = arrangeLibrary(
        entries,
        const LibraryViewOptions(filter: LibraryFilter.practice),
        kinds: kinds,
      );
      // The mixed retreat is under both.
      expect(shown(practice), [
        'Evening recording',
        'Morning sits',
        'Jhāna retreat',
        'Body and breath',
      ]);
    });

    test('an entry with no kinds known shows under its own', () {
      final a = arrangeLibrary(
        entries,
        const LibraryViewOptions(filter: LibraryFilter.talks),
      );
      expect(shown(a), ['A talk on metta', 'Winter talks']);
    });

    test('Teachers shows the saved teachers alone', () {
      final a = arrangeLibrary(
        entries,
        const LibraryViewOptions(filter: LibraryFilter.teachers),
      );
      expect(shown(a), ['Rob Burbea']);
    });

    test('Downloads shows what has something downloaded', () {
      final a = arrangeLibrary(
        entries,
        const LibraryViewOptions(filter: LibraryFilter.downloads),
        downloaded: const {'ds-talk-1', 'yt-playlist-a'},
      );
      expect(shown(a), ['A talk on metta', 'Body and breath']);
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
      expect(_titles(a.shelves[2].entries), [
        'alpha course',
        'Body and breath',
        'Jhāna retreat',
        'Winter talks',
      ]);
    });

    test('Progress: furthest along first, then unbegun, finished last', () {
      final a = arrangeLibrary(
        entries,
        const LibraryViewOptions(sort: LibrarySort.progress),
        progress: const {
          'ds-retreat-1': (done: 10, total: 10),
          'ds-retreat-2': (done: 1, total: 5),
          'yt-playlist-a': (done: 3, total: 4),
        },
      );
      expect(_titles(a.shelves[2].entries), [
        'Body and breath',
        'Winter talks',
        'Jhāna retreat',
      ]);
    });

    test('a filter with nothing is empty', () {
      final a = arrangeLibrary([
        entries.first,
      ], const LibraryViewOptions(filter: LibraryFilter.talks));
      expect(a.isEmpty, isTrue);
    });
  });

  test('the chips count what each would show, teachers aside', () {
    final counts = libraryFilterCounts(
      entries,
      downloaded: const {'ds-talk-1'},
      kinds: {
        'ds-retreat-1': {LibraryGroup.practice, LibraryGroup.talks},
      },
    );
    expect(counts, {
      LibraryFilter.all: 6,
      LibraryFilter.practice: 4,
      LibraryFilter.talks: 3,
      LibraryFilter.teachers: 1,
      LibraryFilter.downloads: 1,
    });
  });

  group('libraryEntryKinds (#80)', () {
    const retreat = 'ds-retreat-9';
    const tracks = {
      retreat: ['ds-talk-1', 'ds-talk-2', 'ds-talk-3'],
    };

    test('a retreat of sittings and talks is under both', () {
      final kinds = libraryEntryKinds(
        [_entry(retreat, 'Mixed')],
        trackIds: tracks,
        sessionGroups: const {
          'ds-talk-1': LibraryGroup.practice,
          'ds-talk-2': LibraryGroup.talks,
        },
      );
      expect(kinds[retreat], {LibraryGroup.practice, LibraryGroup.talks});
    });

    test(
      'its sessions add to the kind the app filed it as, never take it away',
      () {
        // Filed as Practice; every session labelled Talk (Dharma Seed files
        // many guided sittings so).
        final kinds = libraryEntryKinds(
          [_entry(retreat, 'All talks')],
          trackIds: tracks,
          sessionGroups: const {
            'ds-talk-1': LibraryGroup.talks,
            'ds-talk-2': LibraryGroup.talks,
          },
        );
        expect(kinds[retreat], {LibraryGroup.practice, LibraryGroup.talks});
      },
    );

    test('with no session known, its own kind alone (the fallback)', () {
      final kinds = libraryEntryKinds([
        _entry(retreat, 'Not synced'),
        _entry('yt-playlist-v', 'Lectures', group: LibraryGroup.talks),
      ], trackIds: tracks);
      expect(kinds[retreat], {LibraryGroup.practice});
      expect(kinds['yt-playlist-v'], {LibraryGroup.talks});
    });

    test('a kind the user chose wins, alone', () {
      final kinds = libraryEntryKinds(
        [
          _entry(retreat, 'Moved to Talks', override: LibraryGroup.talks),
          _entry(
            'yt-playlist-v',
            'Moved to Practice',
            group: LibraryGroup.talks,
            override: LibraryGroup.practice,
          ),
        ],
        trackIds: {
          ...tracks,
          'yt-playlist-v': ['yt-1'],
        },
        sessionGroups: const {
          'ds-talk-1': LibraryGroup.practice,
          'ds-talk-2': LibraryGroup.practice,
          'ds-talk-3': LibraryGroup.talks,
        },
      );
      expect(kinds[retreat], {LibraryGroup.talks});
      expect(kinds['yt-playlist-v'], {LibraryGroup.practice});
    });

    test('a playlist takes the kind of each session from where it is', () {
      final kinds = libraryEntryKinds(
        [
          _entry(_morning, 'Mixed playlist'),
          _entry('yt-playlist-v', 'Lectures', group: LibraryGroup.talks),
          _entry(
            'lib-track-a',
            'A recorded talk',
            kind: LibraryKind.single,
            group: LibraryGroup.talks,
          ),
        ],
        trackIds: const {
          _morning: ['ds-talk-1', 'yt-2', 'lib-track-a', 'lib-track-unknown'],
          'yt-playlist-v': ['yt-1', 'yt-2'],
        },
        sessionGroups: const {'ds-talk-1': LibraryGroup.practice},
      );
      expect(kinds[_morning], {LibraryGroup.practice, LibraryGroup.talks});
      // A course's own sessions do not vouch for it.
      expect(kinds['yt-playlist-v'], {LibraryGroup.talks});
    });

    test('source courses sharing sessions do not colour each other', () {
      final kinds = libraryEntryKinds(
        [
          _entry('yt-playlist-a', 'Lectures', group: LibraryGroup.talks),
          _entry('yt-playlist-b', 'Guided series'),
        ],
        trackIds: const {
          'yt-playlist-a': ['yt-1', 'yt-2'],
          'yt-playlist-b': ['yt-2', 'yt-3'],
        },
      );
      expect(kinds['yt-playlist-a'], {LibraryGroup.talks});
      expect(kinds['yt-playlist-b'], {LibraryGroup.practice});
    });

    test('in a playlist, a single moved by the user beats its recording', () {
      final kinds = libraryEntryKinds(
        [
          _entry(_morning, 'Sits', group: LibraryGroup.talks),
          // A guided sitting Dharma Seed files as "Talk", moved to Practice.
          _entry(
            'ds-talk-7',
            'Breathing with the body',
            kind: LibraryKind.single,
            group: LibraryGroup.talks,
            override: LibraryGroup.practice,
          ),
        ],
        trackIds: const {
          _morning: ['ds-talk-7'],
        },
        sessionGroups: const {'ds-talk-7': LibraryGroup.talks},
      );
      expect(kinds[_morning], {LibraryGroup.talks, LibraryGroup.practice});
      expect(kinds['ds-talk-7'], {LibraryGroup.practice});
      // Without the user's word, the recording decides.
      final plain = libraryEntryKinds(
        [
          _entry(_morning, 'Sits'),
          _entry(
            'ds-talk-7',
            'Breathing with the body',
            kind: LibraryKind.single,
          ),
        ],
        trackIds: const {
          _morning: ['ds-talk-7'],
        },
        sessionGroups: const {'ds-talk-7': LibraryGroup.talks},
      );
      expect(plain[_morning], {LibraryGroup.practice, LibraryGroup.talks});
    });

    test('a single goes by its own recording; teachers have no kind', () {
      final kinds = libraryEntryKinds(
        [
          _entry(
            'ds-talk-5',
            'Guided, filed as talks',
            kind: LibraryKind.single,
            group: LibraryGroup.talks,
          ),
          _entry('ds-teacher-1', 'Rob Burbea', kind: LibraryKind.teacher),
        ],
        sessionGroups: const {'ds-talk-5': LibraryGroup.practice},
      );
      expect(kinds['ds-talk-5'], {LibraryGroup.practice, LibraryGroup.talks});
      expect(kinds.containsKey('ds-teacher-1'), isFalse);
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
    notifier.setFilter(LibraryFilter.talks);
    first.dispose();

    final second = container();
    addTearDown(second.dispose);
    final options = second.read(libraryViewOptionsProvider);
    expect(options.sort, LibrarySort.title);
    expect(options.layout, LibraryLayout.grid);
    expect(options.filter, LibraryFilter.all);
  });
}
