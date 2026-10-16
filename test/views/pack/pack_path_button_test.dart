import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/home/up_next_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/scaffold_messenger_key.dart';
import 'package:medito/views/pack/widgets/pack_path_button.dart';
import 'package:medito/views/home/widgets/up_next/up_next_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  final sleep = _pack('sleep', 'Sleep', tracks: 7, done: 3);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    started = [];
  });

  Future<void> fakeStart(
    BuildContext context,
    WidgetRef ref, {
    required String trackId,
    required String path,
  }) async => started.add(trackId);

  Future<void> pump(
    WidgetTester tester,
    PackModel pack, {
    List<PackModel> others = const [],
  }) async {
    final packs = [pack, ...others]..sort((a, b) => a.id.compareTo(b.id));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          for (final p in packs)
            packProvider(packId: p.id).overrideWith(() => _FakePack(p)),
        ],
        child: MaterialApp(
          scaffoldMessengerKey: scaffoldMessengerKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PackPathButton(
              pack: pack,
              onStartSession: fakeStart,
              child: const SizedBox(height: 40),
            ),
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

  testWidgets('Continue plays the next session and puts the pack on Home', (
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
    expect(prefs.getString(SharedPreferenceConstants.upNextPackId), 'sleep');
    expect(find.text(l10n.packAddedToHome), findsOneWidget);
  });

  testWidgets('Undo after the first pin leaves Home unpinned', (tester) async {
    await pump(tester, sleep);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.undo));
    await tester.pumpAndSettle();

    expect(prefs.getString(SharedPreferenceConstants.upNextPackId), isNull);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PackPathButton)),
    );
    expect(container.read(upNextPackIdProvider), isEmpty);
  });

  testWidgets('Undo restores an explicitly chosen previous pack', (
    tester,
  ) async {
    final work = _pack('work', 'Work life');
    await prefs.setString(SharedPreferenceConstants.upNextPackId, 'work');
    await prefs.setString(
      SharedPreferenceConstants.upNextReturnPackId,
      'retired-course',
    );
    await pump(tester, sleep, others: [work]);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    expect(
      prefs.getString(SharedPreferenceConstants.upNextReturnPackId),
      isNull,
    );
    await tester.tap(find.text(l10n.undo));
    await tester.pumpAndSettle();

    expect(prefs.getString(SharedPreferenceConstants.upNextPackId), 'work');
    expect(
      prefs.getString(SharedPreferenceConstants.upNextReturnPackId),
      isNull,
    );
  });

  testWidgets(
    'Remove clears the pin and retired return target; Undo restores only the pin',
    (tester) async {
      await prefs.setString(SharedPreferenceConstants.upNextPackId, sleep.id);
      await prefs.setString(
        SharedPreferenceConstants.upNextReturnPackId,
        'retired-course',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            packProvider(packId: sleep.id).overrideWith(() => _FakePack(sleep)),
          ],
          child: MaterialApp(
            scaffoldMessengerKey: scaffoldMessengerKey,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: UpNextWidget()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(UpNextWidget)),
      );

      await tester.drag(find.byType(Slidable), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.removeFromHomeShort));
      await tester.pumpAndSettle();

      expect(prefs.getString(SharedPreferenceConstants.upNextPackId), isNull);
      expect(
        prefs.getString(SharedPreferenceConstants.upNextReturnPackId),
        isNull,
      );
      expect(container.read(upNextPackIdProvider), isEmpty);
      expect(find.byType(Slidable), findsNothing);

      await tester.tap(find.text(l10n.undo));
      await tester.pumpAndSettle();

      expect(container.read(upNextPackIdProvider), sleep.id);
      expect(
        prefs.getString(SharedPreferenceConstants.upNextReturnPackId),
        isNull,
      );
      expect(find.byType(Slidable), findsOneWidget);
    },
  );

  testWidgets(
    'manual pins replace each other and Undo restores the last choice',
    (tester) async {
      final work = _pack('work', 'Work life');
      await pump(tester, work, others: [sleep]);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      expect(started, ['work-1']);
      expect(prefs.getString(SharedPreferenceConstants.upNextPackId), 'work');

      await pump(tester, sleep, others: [work]);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      expect(started, ['work-1', 'sleep-3']);
      expect(prefs.getString(SharedPreferenceConstants.upNextPackId), 'sleep');

      await tester.tap(find.text(l10n.undo));
      await tester.pumpAndSettle();
      expect(prefs.getString(SharedPreferenceConstants.upNextPackId), 'work');
    },
  );

  testWidgets('the pack already on Home just plays, with no snackbar', (
    tester,
  ) async {
    await prefs.setString(SharedPreferenceConstants.upNextPackId, 'sleep');
    await pump(tester, sleep);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();

    expect(started, ['sleep-3']);
    expect(find.text(l10n.packAddedToHome), findsNothing);
  });

  testWidgets('a finished pack shows "All sessions done" and does nothing', (
    tester,
  ) async {
    await pump(tester, _pack('done', 'Done', tracks: 2, done: 2));

    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();

    expect(started, isEmpty);
    expect(prefs.getString(SharedPreferenceConstants.upNextPackId), isNull);
  });

  testWidgets('hidden for packs that contain sub-packs', (tester) async {
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
    await pump(tester, nested);

    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  test('upNextPackIdProvider is empty when no pack has been pinned', () {
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(container.read(upNextPackIdProvider), isEmpty);
    expect(prefs.getString(SharedPreferenceConstants.upNextPackId), isNull);
  });
}
