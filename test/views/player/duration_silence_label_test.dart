import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/cues/cue_runtime_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/views/player/widgets/duration_indicator_widget.dart';

void main() {
  testWidgets('the seek bar says Silence while a hold or the tail runs, and '
      'not through the voice', (tester) async {
    final container = ProviderContainer(
      overrides: [audioStateProvider.overrideWith(AudioStateNotifier.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DurationIndicatorWidget(
              onSeekEnd: (_) {},
              fallbackDurationMs: 600000,
            ),
          ),
        ),
      ),
    );
    double shown() => tester
        .widget<AnimatedOpacity>(find.byKey(const ValueKey('player_silence')))
        .opacity;
    void phase(String phase) => container
        .read(cueRuntimeProvider.notifier)
        .updateFromMap({'phase': phase});

    expect(find.text('Silence'), findsOneWidget);
    expect(shown(), 0);

    for (final silent in ['hold', 'extension']) {
      phase(silent);
      await tester.pumpAndSettle();
      expect(shown(), greaterThan(0), reason: silent);
      phase('playing');
      await tester.pumpAndSettle();
      expect(shown(), 0, reason: 'after $silent');
    }
    // The times keep their places beside it.
    expect(find.text('10:00'), findsOneWidget);
  });
}
