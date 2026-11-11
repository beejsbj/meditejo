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
      body: PackPlayButton(
        pack: pack,
        onStartSession:
            (c, r, {required trackId, required path, courseId}) async {},
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

    testWidgets('resumes the session left partway, not the first incomplete', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await tester.runAsync(
        () => app.harness.store.savePosition('lib-track-2', 90000, 600000),
      );
      await pumpButton(tester, app, _pack());
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('^${l10n.packContinue}: Session 2')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a position in a session outside the course is ignored', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await tester.runAsync(
        () => app.harness.store.savePosition('elsewhere', 90000, 600000),
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

    testWidgets('plays from the start: a plain labelled Play', (tester) async {
      final app = await trackApp(tester);
      final id = (await tester.runAsync(
        app.harness.store.entries,
      ))!.single.sourceId;
      await app.pump(tester, TrackView(trackId: id));
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      // A length the file does not know yet: Play alone (#84).
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.byKey(const ValueKey('play_progress')), findsNothing);
      expect(find.textContaining('from '), findsNothing);
      expect(find.byTooltip('From the beginning'), findsNothing);
      // The page offers the library toggle too, already on.
      expect(find.byTooltip('In library'), findsOneWidget);
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

      // The bar: the play disc in a ring of how far in, "from 12:34"
      // beside it, and a small From the beginning at its end. "Resume at
      // 12:34" is the tooltip and the screen reader's label.
      final handle = tester.ensureSemantics();
      expect(find.byKey(const ValueKey('play_progress')), findsOneWidget);
      expect(find.text('from 12:34'), findsOneWidget);
      expect(find.byTooltip('Resume at 12:34'), findsOneWidget);
      expect(find.bySemanticsLabel('Resume at 12:34'), findsOneWidget);
      expect(find.text('Resume at 12:34'), findsNothing);
      final fromStart = find.byKey(const ValueKey('track_from_start'));
      expect(fromStart, findsOneWidget);
      expect(find.byTooltip('From the beginning'), findsOneWidget);
      expect(
        tester.getCenter(fromStart).dx,
        greaterThan(tester.getCenter(find.text('from 12:34')).dx),
      );
      handle.dispose();
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
