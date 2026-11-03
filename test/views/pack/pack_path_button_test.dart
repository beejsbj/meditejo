import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/scaffold_messenger_key.dart';
import 'package:medito/views/pack/widgets/pack_path_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/memory_session_store.dart';

class _FakePack extends Pack {
  _FakePack(this.model);
  final PackModel model;

  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(model);
}

PackModel _pack(String id, String title, {int tracks = 3, int done = 1}) {
  return PackModel(
    id: id,
    title: title,
    items: List.generate(
      tracks,
      (i) => PackItemsModel(
        type: TypeConstants.track,
        id: '$id-$i',
        title: 'Session $i',
        path: '/tracks/$id-$i',
        isCompleted: i < done,
      ),
    ),
  );
}

void main() {
  late SharedPreferences prefs;
  late AppLocalizations l10n;
  late List<String> started;
  late List<String?> courses;
  late MemorySessionStore store;

  final sleep = _pack('sleep', 'Sleep', tracks: 7, done: 3);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    started = [];
    courses = [];
    store = MemorySessionStore();
  });

  Future<void> fakeStart(
    BuildContext context,
    WidgetRef ref, {
    required String trackId,
    required String path,
    String? courseId,
  }) async {
    started.add(trackId);
    courses.add(courseId);
  }

  Future<void> pump(
    WidgetTester tester,
    PackModel pack, {
    List<PackModel> others = const [],
    List<Override> extra = const [],
  }) async {
    final packs = [pack, ...others]..sort((a, b) => a.id.compareTo(b.id));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          libraryStoreProvider.overrideWithValue(store),
          for (final p in packs)
            packProvider(packId: p.id).overrideWith(() => _FakePack(p)),
          ...extra,
        ],
        child: MaterialApp(
          scaffoldMessengerKey: scaffoldMessengerKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PackPlayButton(pack: pack, onStartSession: fakeStart),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an untouched pack says Start', (tester) async {
    await pump(tester, _pack('fresh', 'Fresh', done: 0));

    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp('^${l10n.packStart}: Session 0')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('Continue plays the next session and pins nothing', (
    tester,
  ) async {
    await pump(tester, sleep);

    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(
        '${l10n.packContinue}: Session 3. ${l10n.upNextProgress(3, 7)}',
      ),
      findsOneWidget,
    );
    handle.dispose();

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();

    expect(started, ['sleep-3']);
    // The session counts towards the course it was started from: the button
    // says so, and startSession writes it before the session starts.
    expect(courses, ['sleep']);
    // Home follows what is played; pinning is its own, deliberate action.
    expect(
      prefs.getStringList(SharedPreferenceConstants.pinnedCourseIds),
      isNull,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a finished pack offers Play again, from its first session', (
    tester,
  ) async {
    await pump(tester, _pack('done', 'Done', tracks: 2, done: 2));

    expect(find.text(l10n.coursePlayAgain), findsOneWidget);
    expect(find.text('Session 0'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.replay_rounded));
    await tester.pumpAndSettle();

    expect(started, ['done-0']);
    expect(courses, ['done']);
  });

  testWidgets('names no session until the places are read', (tester) async {
    // Sleep has 3 of 7 done: without its places it could say "Resume:
    // Session 3" and then turn to the session left partway. It waits.
    final places = Completer<Map<String, DateTime>>();
    await pump(
      tester,
      sleep,
      extra: [partialPlacesProvider.overrideWith((ref) => places.future)],
    );
    final handle = tester.ensureSemantics();
    expect(find.text(l10n.play), findsOneWidget);
    expect(find.text(l10n.packContinue), findsNothing);
    expect(find.textContaining('Session'), findsNothing);
    expect(find.bySemanticsLabel(l10n.play), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(started, isEmpty);

    places.complete({'sleep-5': DateTime(2026, 10, 25)});
    await tester.pumpAndSettle();
    expect(find.text(l10n.packContinue), findsOneWidget);
    expect(find.text('Session 5'), findsOneWidget);
    handle.dispose();
  });

  test('not offered for packs that contain sub-packs', () {
    final nested = PackModel(
      id: 'nested',
      title: 'Nested',
      items: const [
        PackItemsModel(
          type: TypeConstants.pack,
          id: 'child',
          title: 'Child',
          path: '/packs/child',
        ),
      ],
    );
    // The header's action row leaves Play out for it.
    expect(PackPlayButton.isPlayable(nested), isFalse);
    expect(PackPlayButton.isPlayable(sleep), isTrue);
  });
}
