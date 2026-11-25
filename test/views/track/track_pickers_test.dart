import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/guide_name_preference_provider.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/views/track/track_view.dart';

import '../../helpers/library_app.dart';

class _FakeTracks extends Tracks {
  _FakeTracks(this.track);
  final Track track;

  @override
  Future<Track> build({required String trackId}) async => track;
}

TrackAudioFile _file(String id, int minutes) =>
    TrackAudioFile(id: id, path: '$id.mp3', duration: minutes * 60000);

Track _track(List<TrackVoice> voices) => Track(
  id: 'tr',
  title: 'Metta',
  description: '',
  coverUrl: '',
  isPublished: true,
  hasBackgroundSound: false,
  voices: voices,
);

final _single = _track([
  TrackVoice(guideName: 'Ajahn Sucitto', audioFiles: [_file('only', 42)]),
]);

final _several = _track([
  TrackVoice(
    guideName: 'Ajahn Sucitto',
    audioFiles: [_file('a10', 10), _file('a20', 20)],
  ),
  TrackVoice(guideName: 'Rob Burbea', audioFiles: [_file('b10', 10)]),
]);

const _guideChips = ValueKey('track_guide_chips');
const _lengthChips = ValueKey('track_length_chips');

void main() {
  Future<LibraryTestApp> pumpTrack(
    WidgetTester tester,
    Track track, {
    Map<String, Object> prefs = const {},
  }) async {
    final app = await LibraryTestApp.create(tester);
    for (final MapEntry(:key, :value) in prefs.entries) {
      if (value is int) await app.prefs.setInt(key, value);
      if (value is String) await app.prefs.setString(key, value);
    }
    await app.pump(
      tester,
      const TrackView(trackId: 'tr'),
      overrides: [
        tracksProvider(trackId: 'tr').overrideWith(() => _FakeTracks(track)),
      ],
    );
    return app;
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(TrackView)));

  group('track page pickers', () {
    testWidgets('one guide and one length show no picker at all', (
      tester,
    ) async {
      await pumpTrack(tester, _single);
      expect(find.byKey(_guideChips), findsNothing);
      expect(find.byKey(_lengthChips), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(DropdownButton), findsNothing);
      expect(find.text('Ajahn Sucitto'), findsNothing);
      // The length is said once, on the Play bar, not as a choice.
      expect(find.text('42 min'), findsOneWidget);
      expect(find.byKey(const ValueKey('play_title')), findsOneWidget);
    });

    testWidgets('several guides and lengths are shown as chips', (
      tester,
    ) async {
      await pumpTrack(tester, _several);
      expect(find.byKey(_guideChips), findsOneWidget);
      expect(find.byKey(_lengthChips), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Ajahn Sucitto'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Rob Burbea'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '10 min'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '20 min'), findsOneWidget);
    });

    testWidgets('one guide with several lengths shows only the lengths', (
      tester,
    ) async {
      await pumpTrack(
        tester,
        _track([
          TrackVoice(
            guideName: 'Ajahn Sucitto',
            audioFiles: [_file('a10', 10), _file('a20', 20)],
          ),
        ]),
      );
      expect(find.byKey(_guideChips), findsNothing);
      expect(find.byKey(_lengthChips), findsOneWidget);
    });

    testWidgets('choosing a guide is remembered as the preferred guide', (
      tester,
    ) async {
      await pumpTrack(tester, _several);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Rob Burbea'));
      await tester.pump();
      expect(
        containerOf(tester).read(guideNamePreferenceProvider),
        'Rob Burbea',
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Rob Burbea'))
            .selected,
        isTrue,
      );
    });

    testWidgets('a remembered guide that is not offered falls back to the '
        'first voice and is not overwritten', (tester) async {
      final app = await pumpTrack(
        tester,
        _several,
        prefs: {
          'lastSelectedGuideName': 'Nobody',
          'meditation_duration_preference': 20 * 60000,
        },
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Ajahn Sucitto'),
            )
            .selected,
        isTrue,
      );
      // The length closest to the remembered one in that voice is selected.
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '20 min'))
            .selected,
        isTrue,
      );
      // Showing the fallback saves nothing.
      expect(app.prefs.getString('lastSelectedGuideName'), 'Nobody');
      expect(app.prefs.getInt('meditation_duration_preference'), 20 * 60000);
    });

    testWidgets('a track with a name only (YouTube or imported) shows its '
        'length on Play', (tester) async {
      await pumpTrack(
        tester,
        _track([
          TrackVoice(audioFiles: [_file('yt', 44)]),
        ]),
      );
      expect(find.byKey(_guideChips), findsNothing);
      expect(find.byKey(_lengthChips), findsNothing);
      expect(find.byTooltip('Play · 44 min'), findsOneWidget);
      expect(find.text('44 min'), findsOneWidget);
    });

    testWidgets('Play shows no length when it is unknown', (tester) async {
      await pumpTrack(
        tester,
        _track([
          TrackVoice(audioFiles: [_file('yt', 0)]),
        ]),
      );
      expect(find.textContaining('Play ·'), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });
  });

  // Tests that open the player leak Riverpod state into the next test in the
  // same file, so only one may run here, and it must stay last. Others go in
  // their own file.
  group('starting with a single option', () {
    testWidgets('the Play button uses the only guide and length', (
      tester,
    ) async {
      await pumpTrack(tester, _single);
      final container = containerOf(tester);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final request = container.read(playerProvider);
      expect(request?.trackId, 'tr');
      expect(request?.fileId, 'only');
    });
  });
}
