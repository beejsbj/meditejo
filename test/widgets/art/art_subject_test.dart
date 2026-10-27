import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/art/engine/compose.dart';

final _file = File('assets/art/curated_art.json').readAsStringSync();
final _items = ((jsonDecode(_file) as Map)['items'] as Map)
    .cast<String, Map<String, Object?>>();

Object? _plain(Object? v) => jsonDecode(jsonEncode(v));

/// Whether [comp] keeps to its class's row of the meaning map.
void _keepsToMap(ArtComposition comp, String cls) {
  final allowed = ArtMap.allowed(cls);
  expect(
    allowed.pairs,
    contains((comp.ground.name, comp.figure?.name)),
    reason: '$cls ${comp.seed}: ${comp.ground.name} + ${comp.figure?.name}',
  );
  expect(
    allowed.accents,
    contains(comp.accent?.name),
    reason: '$cls ${comp.seed}: accent ${comp.accent?.name}',
  );
}

void main() {
  setUp(() => CuratedArt.instance.useJson(_file));

  group('curated art', () {
    test('ships every built-in sound, preset, starter item and bell', () {
      expect(_items.length, 58);
      expect(_items.values.where((e) => e['kind'] == 'bell'), hasLength(11));
    });

    test(
      'a shipped item draws its frozen composition, never a rebuilt one',
      () {
        for (final MapEntry(key: id, value: e) in _items.entries) {
          if (e['kind'] == 'bell') continue;
          final subject = switch (e['kind']) {
            'sound' => ArtSubject.sound(id),
            'course' => ArtSubject.cover(ArtCoverKind.course, id),
            'single' => ArtSubject.cover(ArtCoverKind.single, id),
            _ => null,
          };
          if (subject == null) continue;
          final comp = CuratedArt.instance.resolve(subject)!;
          final frozen = Map.of(e)
            ..remove('title')
            ..remove('kind')
            ..remove('pick');
          expect(_plain(comp.freeze()), _plain(frozen), reason: id);
        }
      },
    );

    test('synth layers find their curated cards by what they are', () {
      ArtComposition? sound(String id, Map<String, Object?> params) =>
          CuratedArt.instance.resolve(ArtSubject.sound(id, params));
      expect(
        sound(
          kSynthNoiseId,
          const NoiseParams(colour: NoiseColour.brown).toJson(),
        )!.seed,
        _items['noise-brown']!['seed'],
      );
      expect(sound(kSynthDroneId, const {})!.seed, _items['drone']!['seed']);
      expect(
        sound(kSynthBinauralId, const {})!.seed,
        _items['binaural']!['seed'],
      );
    });

    test('bells resolve by asset, card and icon', () {
      final card = CuratedArt.instance.resolve(
        const ArtSubject.bell('assets/audio/bell_gong.wav'),
      )!;
      final icon = CuratedArt.instance.resolve(
        const ArtSubject.bell('assets/audio/bell_gong.wav', icon: true),
      )!;
      final gong = _items['bell-gong']!;
      expect(card.seed, (gong['card']! as Map)['seed']);
      expect(icon.seed, (gong['icon']! as Map)['seed']);
      expect(icon.figure!.layout, 'icon');
    });

    test('a starter preset keeps its card while its leading pair holds', () {
      const layers = [
        SoundLayer(soundId: 'rain-terrace', volume: 0.7),
        SoundLayer(soundId: 'forest-birds', volume: 0.45),
        SoundLayer(soundId: 'wind-trees', volume: 0.3),
      ];
      final comp = CuratedArt.instance.resolve(
        const ArtSubject.layers('starter-rain-forest', layers),
      )!;
      expect(comp.seed, _items['starter-rain-forest']!['seed']);
    });
  });

  group('generated art', () {
    test('a user item is stable by id, and ids differ', () {
      final a = Compose.buildFor('my-course-0123456789abcdef', 'playlist')!;
      final again = Compose.buildFor('my-course-0123456789abcdef', 'playlist')!;
      final other = Compose.buildFor('my-course-fedcba9876543210', 'playlist')!;
      expect(_plain(a.freeze()), _plain(again.freeze()));
      expect(_plain(a.freeze()), isNot(_plain(other.freeze())));
    });

    test('art is keyed by id, so a renamed item keeps it', () {
      const before = ArtSubject.cover(ArtCoverKind.course, 'ds-retreat-77');
      const after = ArtSubject.cover(ArtCoverKind.course, 'ds-retreat-77');
      expect(before.key, after.key);
      expect(
        identical(
          CuratedArt.instance.resolve(before),
          CuratedArt.instance.resolve(after),
        ),
        isTrue,
      );
    });

    test('only fitting grounds and figures meet (no forbidden pairs)', () {
      for (final cls in ArtMap.classes.keys) {
        for (var i = 0; i < 60; i++) {
          _keepsToMap(Compose.build(cls, 'check-$cls-$i'), cls);
        }
      }
    });

    test('every shipped card keeps to its row of the map', () {
      for (final MapEntry(key: id, value: e) in _items.entries) {
        final frozen = e['kind'] == 'bell'
            ? [e['card'], e['icon']]
            : e['kind'] == 'preset'
            ? <Object?>[]
            : [e];
        for (final f in frozen) {
          final comp = ArtComposition.thaw((f! as Map).cast<String, Object?>());
          final cls = comp.cls;
          expect(ArtMap.classes, contains(cls), reason: id);
          _keepsToMap(comp, cls);
        }
      }
    });

    test("a preset takes its loudest layer's ground and figure", () {
      final preset = Compose.buildPreset((
        id: 'user-1',
        layers: [('fire-crackle', 0.3), ('night-insects', 0.8)],
      ))!;
      final allowed = ArtMap.allowed('night');
      expect(
        allowed.pairs,
        contains((preset.ground.name, preset.figure?.name)),
      );
      expect(preset.cls, 'preset');
    });
  });

  group('the live mix card', () {
    test('follows the two loudest layers as they change', () {
      MixArt mix(double rain, double fire, double night) =>
          MixArt(MixArt.current, [
            SoundLayer(soundId: 'rain-car', volume: rain),
            SoundLayer(soundId: 'fire-stove', volume: fire),
            SoundLayer(soundId: 'night-insects', volume: night),
          ]);
      final a = mix(0.8, 0.5, 0.2), b = mix(0.2, 0.5, 0.8);
      expect(a.leading, ['rain-car', 'fire-stove']);
      expect(b.leading, ['night-insects', 'fire-stove']);
      expect(a.key, isNot(b.key));
      final ca = CuratedArt.instance.resolve(a)!;
      final cb = CuratedArt.instance.resolve(b)!;
      expect(
        ArtMap.allowed('rain').pairs,
        contains((ca.ground.name, ca.figure?.name)),
      );
      expect(
        ArtMap.allowed('night').pairs,
        contains((cb.ground.name, cb.figure?.name)),
      );
      // Quieter layers moving don't change it.
      expect(mix(0.8, 0.5, 0.1).key, a.key);
    });
  });

  group('ArtCover', () {
    Widget frame(Widget child, {bool reduce = false}) => MaterialApp(
      theme: meditejoTheme(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Center(child: SizedBox.square(dimension: 120, child: child)),
      ),
    );

    testWidgets('under reduced motion, live art keeps its still frame', (
      tester,
    ) async {
      await tester.pumpWidget(
        frame(
          const ArtCover(subject: ArtSubject.sound('rain-car'), live: true),
          reduce: true,
        ),
      );
      await tester.pump();
      expect(
        find.byType(CustomPaint).evaluate().where((e) {
          final w = e.widget as CustomPaint;
          return w.painter.runtimeType.toString() == '_LivePainter';
        }),
        isEmpty,
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('live art moves when motion is allowed', (tester) async {
      await tester.pumpWidget(
        frame(
          const ArtCover(subject: ArtSubject.sound('rain-car'), live: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byType(CustomPaint).evaluate().where((e) {
          final w = e.widget as CustomPaint;
          return w.painter.runtimeType.toString() == '_LivePainter';
        }),
        isNotEmpty,
      );
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
