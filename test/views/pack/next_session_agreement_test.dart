import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/home/widgets/continue/continue_section.dart';
import 'package:medito/views/pack/widgets/pack_path_button.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';

/// Courses `x-course-NAME` holding sessions `x-NAME-N`, titled
/// "Lesson N".
class _Source implements ContentSource, ParentedContentSource {
  @override
  String get prefix => 'x-';

  @override
  Future<String?> parentOf(String trackId) async {
    final parts = trackId.split('-');
    return parts.length == 3 ? 'x-course-${parts[1]}' : null;
  }

  @override
  Future<Track> track(String id) async => Track(
    id: id,
    title: 'Lesson ${id.split('-').last}',
    description: '',
    coverUrl: '',
    isPublished: true,
    hasBackgroundSound: true,
  );

  @override
  Future<List<PackModel>> browsePacks() async => const [];
  @override
  Future<PackModel> pack(String id) => throw UnimplementedError();
  @override
  Future<Map<String, List<String>>> packTrackIds({
    Set<String> startedTrackIds = const {},
  }) async => const {};
  @override
  Future<List<PackItemsModel>> searchPacks(String query) async => const [];
  @override
  Future<List<TrackSearchModel>> searchTracks(String query) async => const [];
}

PackModel _course(Set<int> done, {int sessions = 18}) => PackModel(
  id: 'x-course-a',
  title: 'Course a',
  items: [
    for (var i = 1; i <= sessions; i++)
      PackItemsModel(
        type: TypeConstants.track,
        id: 'x-a-$i',
        title: 'Lesson $i',
        path: '/tracks/x-a-$i',
        isCompleted: done.contains(i),
      ),
  ],
);

void main() {
  late AppLocalizations l10n;

  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  /// Pumps the course's play button above Home's Continue, over the same
  /// data, and returns the course label the button announces.
  Future<String> pumpBoth(
    WidgetTester tester,
    LibraryTestApp app,
    PackModel pack, {
    required Map<String, DateTime> leftPartway,
    required List<String> played,
  }) async {
    await tester.runAsync(() async {
      await app.harness.store.add(
        const LibraryDraft(
          sourceId: 'x-course-a',
          kind: LibraryKind.course,
          title: 'Course a',
          group: LibraryGroup.practice,
        ),
      );
      await app.harness.store.touchPlayed(['x-course-a']);
      for (final entry in leftPartway.entries) {
        await app.harness.db
            .into(app.harness.db.playbackPositions)
            .insertOnConflictUpdate(
              PlaybackPositionsCompanion.insert(
                trackId: entry.key,
                positionMs: 120000,
                durationMs: const Value(600000),
                updatedAt: entry.value,
              ),
            );
      }
    });
    await app.pump(
      tester,
      Scaffold(
        body: Column(
          children: [
            PackPlayButton(pack: pack),
            const Expanded(
              child: SingleChildScrollView(child: ContinueSection()),
            ),
          ],
        ),
      ),
      played: played,
      overrides: [
        libraryContentRouterProvider.overrideWithValue(
          ContentRouter(sources: [_Source()]),
        ),
        packDataProvider(packId: pack.id).overrideWith((ref) async => pack),
      ],
    );
    final label = tester.getSemantics(find.byType(PackPlayButton)).label;
    return label;
  }

  testWidgets('a partly played lesson is the next session on both surfaces', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    final handle = tester.ensureSemantics();

    // Lesson 1 is finished; Lessons 2 and 5 were left partway, 5 more
    // recently. The first incomplete lesson is 2, but 5 is where they were.
    final label = await pumpBoth(
      tester,
      app,
      _course({1}),
      leftPartway: {
        'x-a-2': DateTime(2026, 10, 18),
        'x-a-5': DateTime(2026, 10, 25),
      },
      played: ['x-a-1'],
    );

    expect(label, contains('${l10n.packContinue}: Lesson 5'));
    // Home's Continue offers the same session, at its resume point.
    expect(find.byKey(const ValueKey('continue_x-a-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('continue_x-a-2')), findsNothing);
    // The course's Play names it too; this is Home's card.
    expect(
      find.descendant(
        of: find.byType(ContinueSection),
        matching: find.text('Lesson 5'),
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, l10n.packContinue),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('with nothing partway both offer the first incomplete lesson', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    final handle = tester.ensureSemantics();

    final label = await pumpBoth(
      tester,
      app,
      _course({1, 2}),
      leftPartway: const {},
      played: ['x-a-1', 'x-a-2'],
    );

    expect(label, contains('${l10n.packContinue}: Lesson 3'));
    expect(find.byKey(const ValueKey('continue_x-a-3')), findsOneWidget);
    // The course's Play names it too; this is Home's card.
    expect(
      find.descendant(
        of: find.byType(ContinueSection),
        matching: find.text('Lesson 3'),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the label turns from Start to Resume after a pause', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    final handle = tester.ensureSemantics();
    final pack = _course({});
    await app.pump(
      tester,
      Scaffold(body: PackPlayButton(pack: pack)),
      overrides: [
        packDataProvider(packId: pack.id).overrideWith((ref) async => pack),
      ],
    );
    String label() => tester.getSemantics(find.byType(PackPlayButton)).label;

    expect(label(), contains('${l10n.packStart}: Lesson 1'));

    // The player pauses Lesson 3: the store saves it and notifies.
    await tester.runAsync(
      () => app.harness.store.savePosition('x-a-3', 90000, 600000),
    );
    await DharmaSeedTestApp.settle(tester);

    expect(label(), contains('${l10n.packContinue}: Lesson 3'));
    handle.dispose();
  });
}
