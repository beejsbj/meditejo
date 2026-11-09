import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/player/playback_speed_provider.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/speed_sheet.dart';
import 'package:medito/views/previews/preview_support.dart';
import 'package:medito/views/settings/widgets/practice_default_tiles.dart';

void main() {
  Future<void> pump(WidgetTester tester, Map<String, Object> prefs) async {
    await tester.pumpWidget(
      PreviewShell(
        prefs: {...prefsLight, ...prefs},
        themeMode: ThemeMode.light,
        child: const Scaffold(body: PlaybackSpeedTile()),
      ),
    );
    await tester.pump();
  }

  Finder tab(CueKind kind) => find.byKey(ValueKey('speed_kind_${kind.name}'));

  testWidgets('Settings shows each kind\'s speed, Practice first', (
    tester,
  ) async {
    await pump(tester, {'speed.v1.talks': 1.5});
    expect(
      find.textContaining('Playback speed', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Practice 1× · Talks 1.5×', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('it opens the speed sheet for both kinds, without a session', (
    tester,
  ) async {
    await pump(tester, {'speed.v1.talks': 1.5});
    await tester.tap(find.byKey(const ValueKey('settings_playback_speed')));
    await tester.pumpAndSettle();
    expect(find.byType(SpeedSheet), findsOneWidget);
    expect(
      tester.getTopLeft(tab(CueKind.practice)).dx,
      lessThan(tester.getTopLeft(tab(CueKind.talks)).dx),
    );

    // Set Talks to 2× from Settings: stored, and the row follows.
    await tester.tap(tab(CueKind.talks));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('speed_option_2×')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlaybackSpeedTile)),
    );
    expect(container.read(playbackSpeedProvider(CueKind.talks)), 2.0);
    expect(container.read(playbackSpeedProvider(CueKind.practice)), 1.0);
    expect(
      find.textContaining('Practice 1× · Talks 2×', findRichText: true),
      findsOneWidget,
    );
  });
}
