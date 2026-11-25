import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/identity/mark_generator.dart';
import 'package:medito/services/identity/mark_spec.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container([
  Map<String, Object> prefs = const {},
]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(p)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  var now = DateTime(2026, 10, 26, 9);
  setUp(() {
    now = DateTime(2026, 10, 26, 9);
    identityClock = () => now;
  });
  tearDown(() => identityClock = DateTime.now);

  group('the day', () {
    test('turns over at local midnight, not before', () async {
      now = DateTime(2026, 10, 26, 23, 59, 59);
      final c = await _container();
      final sub = c.listen(dailyMarkProvider, (_, _) {});
      expect(c.read(identityDayProvider), DateTime(2026, 10, 26));
      expect(sub.read().seed, 'm-2026-10-26');

      // main.dart's minute tick calls refresh: nothing changes before
      // midnight, and the next day's mark arrives after it.
      c.read(identityDayProvider.notifier).refresh();
      expect(sub.read().seed, 'm-2026-10-26');
      now = DateTime(2026, 10, 27, 0, 0, 30);
      c.read(identityDayProvider.notifier).refresh();
      expect(c.read(identityDayProvider), DateTime(2026, 10, 27));
      expect(sub.read().seed, 'g-2026-10-27');
    });

    test('is checked again on resume', () async {
      final c = await _container();
      expect(c.read(identityDayProvider), DateTime(2026, 10, 26));
      // The app slept through midnight: no timer ran.
      now = DateTime(2026, 10, 28, 7);
      c.read(identityDayProvider.notifier).refresh();
      expect(c.read(identityDayProvider), DateTime(2026, 10, 28));
    });
  });

  group('the palette', () {
    test('is Tidewater, fixed, by default', () async {
      final c = await _container();
      expect(c.read(paletteChoiceProvider), const FixedPalette('tide'));
      expect(c.read(activePaletteProvider).id, 'tide');
    });

    test('a choice is kept across launches', () async {
      final c = await _container();
      await c
          .read(paletteChoiceProvider.notifier)
          .choose(const FixedPalette('dusk'));
      expect(c.read(activePaletteProvider).id, 'dusk');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(SharedPreferenceConstants.identityPalette),
        'dusk',
      );
      final relaunched = await _container({
        SharedPreferenceConstants.identityPalette: 'dusk',
      });
      expect(relaunched.read(activePaletteProvider).id, 'dusk');
    });

    test('daily follows the date, independently of the mark', () async {
      final c = await _container({
        SharedPreferenceConstants.identityPalette: 'daily',
      });
      expect(c.read(paletteChoiceProvider), const DailyPalette());
      expect(c.read(activePaletteProvider).id, 'tide'); // 2026-10-26
      now = DateTime(2026, 10, 27, 8);
      c.read(identityDayProvider.notifier).refresh();
      expect(c.read(activePaletteProvider).id, 'riso');
      now = DateTime(2026, 10, 28, 8);
      c.read(identityDayProvider.notifier).refresh();
      expect(c.read(activePaletteProvider).id, 'dusk');
    });

    test('an unknown saved palette falls back to the default', () async {
      final c = await _container({
        SharedPreferenceConstants.identityPalette: 'gone',
      });
      expect(c.read(activePaletteProvider).id, 'tide');
    });
  });

  group('no pinning', () {
    test(
      "Home's mark is the day's, whatever an earlier build pinned",
      () async {
        final c = await _container({
          SharedPreferenceConstants.identityPinnedMark: MarkGenerator.build(
            'g-1kq',
          ).encode(),
        });
        expect(c.read(homeMarkProvider).seed, 'm-2026-10-26');
        now = DateTime(2026, 10, 30, 8);
        c.read(identityDayProvider.notifier).refresh();
        expect(c.read(homeMarkProvider).seed, c.read(dailyMarkProvider).seed);
        expect(c.read(homeMarkProvider).seed, isNot('m-2026-10-26'));
      },
    );

    test('a stored pin is dropped at launch', () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferenceConstants.identityPinnedMark: '{"v": 99}',
        SharedPreferenceConstants.identityPalette: 'dusk',
      });
      final prefs = await SharedPreferences.getInstance();
      await forgetPinnedMark(prefs);
      expect(
        prefs.containsKey(SharedPreferenceConstants.identityPinnedMark),
        isFalse,
      );
      expect(
        prefs.getString(SharedPreferenceConstants.identityPalette),
        'dusk',
      );
    });
  });

  test('a frozen mark round-trips through JSON for every family', () {
    for (final seed in ['g-1kq', 'g-28q', 'm-1nq', 'm-1zq', 'm-1aq', 'a-dq']) {
      final mark = MarkGenerator.build(seed);
      final again = MarkSpec.decode(mark.encode());
      expect(again.encode(), mark.encode(), reason: seed);
      expect(again.family, mark.family);
      expect(again.type, mark.type);
    }
  });
}
