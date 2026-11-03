import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/player/widgets/bottom_actions/pack_view_bottom_bar.dart';
import 'package:medito/views/track/track_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';
import '../../helpers/no_hearts.dart';

const _track = Track(
  id: 'ds-talk-77',
  title: 'Wise Attention and the Practice of Loving-Kindness',
  subtitle: 'Talk · Ajahn Sucitto · 42 min',
  description: '',
  coverUrl: '',
  isPublished: true,
  hasBackgroundSound: false,
  voices: [
    TrackVoice(
      guideName: 'Ajahn Sucitto',
      audioFiles: [TrackAudioFile(id: 'f1', path: 'f1.mp3', duration: 1)],
    ),
  ],
);

class _FakeTracks extends Tracks {
  @override
  Future<Track> build({required String trackId}) async => _track;
}

const _pack = PackModel(
  id: 'lib-course-c',
  title: 'The Art of Concentration',
  items: [
    PackItemsModel(type: 'track', id: 'c-1', title: 'One', path: '/tracks/c'),
  ],
);

class _FakePack extends Pack {
  _FakePack(this.pack);
  final PackModel pack;
  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(pack);
}

final _pinOff = find.byIcon(Icons.push_pin_outlined);
final _pinOn = find.byIcon(Icons.push_pin);

Future<ProviderContainer> _pumpTrack(
  WidgetTester tester, {
  List<String> pinned = const [],
}) async {
  final app = await LibraryTestApp.create(tester);
  await app.prefs.setStringList(
    SharedPreferenceConstants.pinnedCourseIds,
    pinned,
  );
  await app.pump(
    tester,
    TrackView(trackId: _track.id),
    overrides: [
      tracksProvider(trackId: _track.id).overrideWith(_FakeTracks.new),
    ],
  );
  return ProviderScope.containerOf(tester.element(find.byType(TrackView)));
}

void main() {
  group("a session's page", () {
    testWidgets('pins the session to Home, and unpins it', (tester) async {
      final container = await _pumpTrack(tester);
      expectNoHearts();
      expect(_pinOff, findsOneWidget);
      expect(find.byTooltip('Pin to Home'), findsOneWidget);

      await tester.tap(_pinOff);
      await DharmaSeedTestApp.settle(tester);
      expect(container.read(pinnedCoursesProvider), [_track.id]);
      expect(
        container.read(pinnedCoursesProvider.notifier).isSession(_track.id),
        isTrue,
      );
      expect(_pinOn, findsOneWidget);
      expect(find.text('Pinned to Home'), findsOneWidget);
      expect(find.byTooltip('Unpin from Home'), findsOneWidget);
      expectNoHearts();

      await tester.tap(_pinOn);
      await DharmaSeedTestApp.settle(tester);
      expect(container.read(pinnedCoursesProvider), isEmpty);
      expect(find.text('Unpinned from Home'), findsOneWidget);
      expect(_pinOff, findsOneWidget);

      // Undo puts it back, still a session.
      await tester.tap(find.text('Undo'));
      await DharmaSeedTestApp.settle(tester);
      expect(container.read(pinnedCoursesProvider), [_track.id]);
      expect(
        container.read(pinnedCoursesProvider.notifier).isSession(_track.id),
        isTrue,
      );
    });

    testWidgets('a fourth pin says it is under See all', (tester) async {
      final container = await _pumpTrack(tester, pinned: ['a', 'b', 'c']);
      await tester.tap(_pinOff);
      await DharmaSeedTestApp.settle(tester);
      expect(container.read(pinnedCoursesProvider), ['a', 'b', 'c', _track.id]);
      expect(find.text('Pinned to Home, under See all'), findsOneWidget);
    });
  });

  group("a course's page", () {
    for (final course in [true, false]) {
      testWidgets('pins from its header, not its bottom bar '
          '(${course ? 'course' : 'plain pack'} layout)', (tester) async {
        final pack = course
            ? _pack.copyWith(
                items: [_pack.items.single.copyWith(kind: 'Meditation')],
              )
            : _pack;
        final app = await LibraryTestApp.create(tester);
        await app.pump(
          tester,
          PackView(id: pack.id),
          overrides: [
            packProvider(packId: pack.id).overrideWith(() => _FakePack(pack)),
          ],
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(PackView)),
        );
        expectNoHearts();
        final pin = find.byKey(const ValueKey('course_pin'));
        // One control, in the header beside Add to library (#81).
        expect(pin, findsOneWidget);
        expect(_pinOff, findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(PackViewBottomBar),
            matching: find.byIcon(Icons.push_pin_outlined),
          ),
          findsNothing,
        );

        await tester.tap(pin);
        await DharmaSeedTestApp.settle(tester);
        expect(container.read(pinnedCoursesProvider), [pack.id]);
        expect(
          container.read(pinnedCoursesProvider.notifier).isSession(pack.id),
          isFalse,
        );
        expect(_pinOn, findsOneWidget);
        expect(find.byTooltip('Unpin from Home'), findsOneWidget);
      });
    }
  });
}
