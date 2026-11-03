import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/views/player/widgets/autoplay_control.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _course = CueScope(CueKind.practice, courseId: 'c1');
const _kind = CueScope(CueKind.practice);

PackItemsModel _item(String id, String title) =>
    PackItemsModel(type: 'track', id: id, title: title, path: '/tracks/$id');

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String trackId = 't1',
  Map<String, Object> prefsValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      packDataProvider(packId: 'c1').overrideWith(
        (ref) async => PackModel(
          id: 'c1',
          title: 'Practising the Jhānas',
          items: [
            _item('t1', 'Day 1: Settling the body'),
            _item('t2', 'Day 2: Piti, and letting it build'),
          ],
        ),
      ),
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
            child: AutoplayButton(scope: _course, trackId: trackId),
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

void main() {
  testWidgets('Autoplay lives in the player: on, off and the pause', (
    tester,
  ) async {
    final container = await _pump(tester);
    CueSettings kind() => container.read(cueSettingsStoreProvider).read(_kind);
    expect(find.text('Autoplay off'), findsOneWidget);
    await _open(tester);
    expect(find.text('Autoplay'), findsOneWidget);
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

  testWidgets('a course with its own settings keeps autoplay to itself', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      prefsValues: {'cues.v1.practice.course.c1': '{"autoplay":false}'},
    );
    final store = container.read(cueSettingsStoreProvider);
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('autoplay_switch')));
    await tester.pumpAndSettle();
    expect(store.read(_course).autoplay, isTrue);
    expect(store.read(_kind).autoplay, isFalse);
  });

  testWidgets('the last session says so', (tester) async {
    await _pump(tester, trackId: 't2');
    await _open(tester);
    expect(find.text('This is the last session of the course'), findsOne);
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
}
