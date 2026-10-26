import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/utils/resume_request.dart';
import 'package:medito/views/pack/widgets/pack_path_button.dart';
import 'package:medito/views/track/track_view.dart';

import '../../helpers/library_app.dart';

class _FakePack extends Pack {
  _FakePack(this.model);
  final PackModel model;

  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(model);
}

PackModel _pack({int done = 0}) => PackModel(
  id: 'course',
  title: 'Course',
  items: List.generate(
    3,
    (i) => PackItemsModel(
      type: TypeConstants.track,
      id: 'lib-track-$i',
      title: 'Session $i',
      path: '/tracks/lib-track-$i',
      isCompleted: i < done,
    ),
  ),
);

void main() {
  late AppLocalizations l10n;

  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  Future<void> pumpButton(
    WidgetTester tester,
    LibraryTestApp app,
    PackModel pack,
  ) => app.pump(
    tester,
    Scaffold(
      body: PackPathButton(
        pack: pack,
        onStartSession: (c, r, {required trackId, required path}) async {},
        child: const SizedBox(height: 40),
      ),
    ),
    overrides: [
      packProvider(packId: pack.id).overrideWith(() => _FakePack(pack)),
    ],
  );

  group('the course action', () {
    testWidgets('says Start for an untouched course', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await pumpButton(tester, app, _pack());
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('^${l10n.packStart}: Session 0')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('says Resume once the first session was left partway', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await tester.runAsync(
        () => app.harness.store.savePosition('lib-track-0', 90000, 600000),
      );
      await pumpButton(tester, app, _pack());
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('^${l10n.packContinue}: Session 0')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('^${l10n.packStart}: ')),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('a position in some other session does not change the label', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await tester.runAsync(
        () => app.harness.store.savePosition('lib-track-2', 90000, 600000),
      );
      await pumpButton(tester, app, _pack());
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('^${l10n.packStart}: Session 0')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('the track page', () {
    Future<LibraryTestApp> trackApp(WidgetTester tester) async {
      final app = await LibraryTestApp.create(tester);
      await tester.runAsync(() async {
        final preview = await app.harness.service.resolve(
          app.harness.writeAudio('Metta.mp3').path,
        );
        await app.harness.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.single,
            group: LibraryGroup.practice,
          ),
        );
      });
      return app;
    }

    testWidgets('plays from the start with just a play icon', (tester) async {
      final app = await trackApp(tester);
      final id = (await tester.runAsync(
        app.harness.store.entries,
      ))!.single.sourceId;
      await app.pump(tester, TrackView(trackId: id));
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.textContaining('Resume at'), findsNothing);
      expect(find.text('From the beginning'), findsNothing);
      // The page offers the library action too, already ticked.
      expect(find.text('In library'), findsOneWidget);
    });

    testWidgets('reads Resume at the saved place, and can start over', (
      tester,
    ) async {
      final app = await trackApp(tester);
      final id = (await tester.runAsync(
        app.harness.store.entries,
      ))!.single.sourceId;
      await tester.runAsync(
        () => app.harness.store.savePosition(id, 754000, 3600000),
      );
      await app.pump(tester, TrackView(trackId: id));

      expect(find.text('Resume at 12:34'), findsOneWidget);
      expect(find.text('From the beginning'), findsOneWidget);
    });
  });

  testWidgets('a request is set to start where the user left off', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await tester.runAsync(
      () => app.harness.store.savePosition('lib-track-0', 45000, 600000),
    );
    late WidgetRef captured;
    await app.pump(
      tester,
      Consumer(
        builder: (context, ref, _) {
          captured = ref;
          return const SizedBox();
        },
      ),
    );
    const base = PlaybackRequest(
      trackId: 'lib-track-0',
      fileId: 'lib-track-0',
      title: 't',
      description: '',
      coverUrl: '',
      remoteUrl: 'https://example.org/a.mp3',
      duration: 600000,
      hasBackgroundSound: true,
    );
    final resumed = await tester.runAsync(
      () => withResumePosition(captured, base),
    );
    expect(resumed!.startPositionMs, 45000);
    final fresh = await tester.runAsync(
      () => withResumePosition(captured, base.copyWith(trackId: 'lib-track-9')),
    );
    expect(fresh!.startPositionMs, 0);
  });
}
