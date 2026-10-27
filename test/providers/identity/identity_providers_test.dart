import 'dart:convert';

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
      // Pinning a mark does not fix the palette.
      await c.read(pinnedMarkProvider.notifier).pin(c.read(dailyMarkProvider));
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

  group('pinning', () {
    test("keeps today's mark on Home after the day changes", () async {
      final c = await _container();
      final today = c.read(homeMarkProvider);
      await c.read(pinnedMarkProvider.notifier).pin(today);
      now = DateTime(2026, 10, 30, 8);
      c.read(identityDayProvider.notifier).refresh();
      expect(c.read(dailyMarkProvider).seed, isNot(today.seed));
      expect(c.read(homeMarkProvider).seed, today.seed);

      await c.read(pinnedMarkProvider.notifier).unpin();
      expect(c.read(homeMarkProvider).seed, c.read(dailyMarkProvider).seed);
    });

    test('stores frozen geometry, so a generator change never redraws '
        'a kept mark', () async {
      final c = await _container();
      await c
          .read(pinnedMarkProvider.notifier)
          .pin(MarkGenerator.build('g-1kq'));
      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(
                prefs.getString(SharedPreferenceConstants.identityPinnedMark)!,
              )
              as Map<String, Object?>;
      // The pin holds the drawn geometry, not just a seed.
      expect(stored['seed'], 'g-1kq');
      expect((stored['stroke'] as Map)['x'], hasLength(420));

      // A later generator draws g-1kq differently: simulate that by
      // changing what is stored under the same seed, then relaunch.
      final stroke = stored['stroke'] as Map<String, Object?>;
      final shifted = [for (final x in stroke['x'] as List) (x as num) + 0.05];
      stroke['x'] = shifted;
      final relaunched = await _container({
        SharedPreferenceConstants.identityPinnedMark: jsonEncode(stored),
      });
      final kept = relaunched.read(homeMarkProvider) as GestureMark;
      final regenerated = MarkGenerator.build('g-1kq') as GestureMark;
      expect(kept.seed, 'g-1kq');
      expect(kept.stroke.x.first, closeTo(shifted.first.toDouble(), 1e-9));
      expect(
        kept.stroke.x.first,
        isNot(closeTo(regenerated.stroke.x.first, 0.01)),
      );
    });

    test('an unreadable pin falls back to the daily mark', () async {
      final c = await _container({
        SharedPreferenceConstants.identityPinnedMark: '{"v": 99}',
      });
      expect(c.read(pinnedMarkProvider), isNull);
      expect(c.read(homeMarkProvider).seed, 'm-2026-10-26');
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
