import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/player/player_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/views/player/widgets/autoplay_control.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _course = CueScope(CueKind.practice, courseId: 'c1');
const _kind = CueScope(CueKind.practice);
const _playlistId = 'my-course-abc';

PackItemsModel _item(String id, String title) =>
    PackItemsModel(type: 'track', id: id, title: title, path: '/tracks/$id');

PlaybackRequest _playing(String trackId) => PlaybackRequest(
  trackId: trackId,
  fileId: trackId,
  title: trackId,
  description: '',
  coverUrl: '',
  remoteUrl: 'https://example.org/$trackId.mp3',
  duration: 600000,
  hasBackgroundSound: false,
);

/// What the player is playing, moved on by the test as autoplay would.
class _Player extends PlayerProvider {
  _Player(this.initial);
  final String initial;

  @override
  PlaybackRequest? build() => _playing(initial);

  void playing(String trackId) => state = _playing(trackId);
}

Override _pack(String id) => packDataProvider(packId: id).overrideWith(
  (ref) async => PackModel(
    id: id,
    title: 'Practising the Jhānas',
    items: [
      _item('t1', 'Day 1: Settling the body'),
      _item('t2', 'Day 2: Piti, and letting it build'),
      _item('t3', 'Day 3: The second jhāna'),
    ],
  ),
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String trackId = 't1',
  CueScope scope = _course,
  Map<String, Object> prefsValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      _pack('c1'),
      _pack(_playlistId),
      playerProvider.overrideWith(() => _Player(trackId)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: AutoplayButton(scope: scope, trackId: trackId),
          ),
        ),
      ),
    ),
  );
  return container;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('player_autoplay')));
  await tester.pumpAndSettle();
}

String _scopeLine(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('autoplay_scope'))).data!;

void main() {
  testWidgets('Autoplay lives in the player: on, off and the pause', (
    tester,
  ) async {
    final container = await _pump(tester);
    CueSettings kind() => container.read(cueSettingsStoreProvider).read(_kind);
    expect(find.text('Autoplay off'), findsOneWidget);
    await _open(tester);
    expect(find.text('Autoplay'), findsOneWidget);
    // Kind-wide, it says so: switching it here reaches every course.
    expect(_scopeLine(tester), 'For all practice');
    expect(
      find.text('Up next: Day 2: Piti, and letting it build'),
      findsOneWidget,
    );
    // The pause is offered only once autoplay is on.
    expect(find.text('Pause between sessions'), findsNothing);
    await tester.tap(find.text('Play the next session automatically'));
    await tester.pumpAndSettle();
    expect(kind().autoplay, isTrue, reason: 'saved where Customize saves');
    expect(find.text('Pause between sessions'), findsOneWidget);
    for (final label in ['None', '5 sec', '10 sec', '30 sec']) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(ChoiceChip, '10 sec'));
    await tester.pumpAndSettle();
    expect(kind().interludeSeconds, 10);
    expect(
      container.read(cueSettingsProvider(_course)).interludeSeconds,
      10,
      reason: 'the course inherits its kind',
    );
    Navigator.of(tester.element(find.text('Autoplay'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Autoplay on'), findsOneWidget);
  });

  testWidgets('talks say talks', (tester) async {
    await _pump(tester, scope: const CueScope(CueKind.talks, courseId: 'c1'));
    await _open(tester);
    expect(_scopeLine(tester), 'For all talks');
  });

  testWidgets('a course with its own settings keeps autoplay to itself', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      prefsValues: {'cues.v1.practice.course.c1': '{"autoplay":false}'},
    );
    final store = container.read(cueSettingsStoreProvider);
    await _open(tester);
    expect(_scopeLine(tester), 'For this course');
    await tester.tap(find.byKey(const ValueKey('autoplay_switch')));
    await tester.pumpAndSettle();
    expect(store.read(_course).autoplay, isTrue);
    expect(store.read(_kind).autoplay, isFalse);
  });

  testWidgets('a playlist says playlist', (tester) async {
    await _pump(
      tester,
      trackId: 't3',
      scope: const CueScope(CueKind.practice, courseId: _playlistId),
      prefsValues: {
        'cues.v1.practice.course.$_playlistId': '{"autoplay":true}',
      },
    );
    await _open(tester);
    expect(_scopeLine(tester), 'For this playlist');
    expect(find.text('This is the last session of the playlist'), findsOne);
  });

  testWidgets('the last session says so', (tester) async {
    await _pump(tester, trackId: 't3');
    await _open(tester);
    expect(find.text('This is the last session of the course'), findsOne);
  });

  testWidgets('"Up next" follows the player while the sheet is open', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _open(tester);
    expect(find.text('Up next: Day 2: Piti, and letting it build'), findsOne);
    // Autoplay moves on to the next session with the sheet still open.
    (container.read(playerProvider.notifier) as _Player).playing('t2');
    await tester.pumpAndSettle();
    expect(find.text('Up next: Day 3: The second jhāna'), findsOne);
    expect(find.textContaining('Day 2'), findsNothing);
  });

  testWidgets('settings stored by the old Flow section show here', (
    tester,
  ) async {
    await _pump(
      tester,
      prefsValues: {
        'cues.v1.practice': '{"autoplay":true,"interludeSeconds":30}',
      },
    );
    expect(find.text('Autoplay on'), findsOneWidget);
    await _open(tester);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '30 sec'))
          .selected,
      isTrue,
    );
  });

  test('the pauses offered are the ones stored settings accept', () {
    for (final seconds in cueInterludeSeconds) {
      expect(
        CueSettings.fromJson({'interludeSeconds': seconds}).interludeSeconds,
        seconds,
      );
    }
    expect(CueSettings.fromJson({'interludeSeconds': 7}).interludeSeconds, 0);
  });
}
