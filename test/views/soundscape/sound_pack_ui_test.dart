import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/sound_pack_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/scaffold_messenger_key.dart';
import 'package:medito/services/soundscape/sound_pack_service.dart';
import 'package:medito/views/settings/widgets/sound_pack_tiles.dart';
import 'package:medito/views/soundscape/sound_credits_view.dart';
import 'package:medito/views/soundscape/sound_pack_widgets.dart';
import 'package:medito/views/soundscape/sounds_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

/// The Sounds screen when some sounds are a download, not on the phone.
void main() {
  late FakeSoundPack pack;
  late ProviderContainer container;

  // On the phone: the bundled sounds always, plus these.
  const have = {'rain-car', 'river'};
  final packIds = [for (final s in bundledSoundLibrary.packSounds) s.id];

  Future<void> pump(
    WidgetTester tester, {
    Set<String> downloaded = have,
    bool instant = true,
    Widget home = const SoundsView(),
  }) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...soundscapeTestOverrides(
            FakeSoundscapeEngine(),
            soundPack: [
              soundPackProvider.overrideWith(
                () => pack = FakeSoundPack(downloaded, instant),
              ),
            ],
          ),
        ],
        child: MaterialApp(
          scaffoldMessengerKey: scaffoldMessengerKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => SoundMissingListener(child: child!),
          home: Scaffold(body: home),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('sounds_library')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  Finder card(String id) => find.byKey(ValueKey('sound_$id'));
  Finder offer(String id) => find.byKey(ValueKey('sound_offer_$id'));

  testWidgets('a sound that is not downloaded shows its size, not a +', (
    tester,
  ) async {
    await pump(tester);
    await reveal(tester, card('sea'));
    expect(offer('sea'), findsOneWidget);
    expect(
      find.descendant(
        of: card('sea'),
        matching: find.textContaining(RegExp(r'^\d+(\.\d)? MB$')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sound_state_sea')), findsNothing);
    // One on the phone, and a bundled one, are ordinary cards.
    expect(offer('river'), findsNothing);
    await reveal(tester, card('stream'));
    expect(offer('stream'), findsNothing);
    expect(find.byKey(const ValueKey('sound_state_stream')), findsOneWidget);
  });

  testWidgets('tapping it downloads rather than layering it in', (
    tester,
  ) async {
    await pump(tester, instant: false);
    await reveal(tester, card('sea'));
    await tester.tap(card('sea'));
    await tester.pump();
    expect(pack.asked, ['sea']);
    expect(container.read(soundscapeProvider).mix.contains('sea'), isFalse);
    // A ring while it arrives; tapping again cancels.
    expect(
      find.descendant(
        of: offer('sea'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(card('sea'));
    await tester.pump();
    expect(pack.cancelled, ['sea']);
  });

  testWidgets('a download that lands makes it an ordinary card', (
    tester,
  ) async {
    await pump(tester);
    await reveal(tester, card('sea'));
    await tester.tap(card('sea'));
    await tester.pumpAndSettle();
    expect(offer('sea'), findsNothing);
    expect(find.byKey(const ValueKey('sound_state_sea')), findsOneWidget);
    await tester.tap(card('sea'));
    await tester.pumpAndSettle();
    expect(container.read(soundscapeProvider).mix.contains('sea'), isTrue);
  });

  testWidgets('a failed download offers a retry on its card', (tester) async {
    await pump(tester);
    pack.setDownload(
      'sea',
      const SoundDownload(
        SoundDownloadPhase.failed,
        failure: SoundDownloadFailure.integrity,
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, card('sea'));
    expect(
      find.descendant(
        of: offer('sea'),
        matching: find.byIcon(Symbols.refresh_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(card('sea'));
    await tester.pump();
    expect(pack.retried, ['sea']);
  });

  group('the banner', () {
    Finder banner() => find.byKey(const ValueKey('sound_pack_banner'));

    testWidgets('offers Download all, with what is left', (tester) async {
      await pump(tester);
      expect(banner(), findsOneWidget);
      expect(find.text('More sounds'), findsOneWidget);
      expect(
        find.textContaining('${packIds.length - have.length} more sounds'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('pack_download_all')));
      await tester.pumpAndSettle();
      expect(pack.asked.toSet(), packIds.toSet().difference(have));
      // Everything arrived: nothing left to offer.
      expect(banner(), findsNothing);
    });

    testWidgets('shows progress with Cancel while downloading', (tester) async {
      await pump(tester, instant: false);
      await tester.tap(find.byKey(const ValueKey('pack_download_all')));
      await tester.pump();
      expect(find.byKey(const ValueKey('pack_progress')), findsOneWidget);
      expect(find.textContaining('Downloading 1 of'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pack_cancel')));
      await tester.pump();
      expect(pack.cancelAlls, 1);
      expect(find.byKey(const ValueKey('pack_progress')), findsNothing);
    });

    testWidgets('says it waits for Wi-Fi, and can go ahead anyway', (
      tester,
    ) async {
      await pump(tester, instant: false);
      await pack.download(['sea']);
      pack.setWaitingForWifi(true);
      await tester.pumpAndSettle();
      expect(find.text('Waiting for Wi-Fi'), findsOneWidget);
      expect(find.byKey(const ValueKey('pack_progress')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pack_anyway')));
      await tester.pump();
      expect(pack.askedAnyNetwork, ['sea']);
    });

    testWidgets('after failures: how many, why, and Retry', (tester) async {
      await pump(tester);
      for (final id in ['sea', 'ocean']) {
        pack.setDownload(
          id,
          const SoundDownload(
            SoundDownloadPhase.failed,
            failure: SoundDownloadFailure.network,
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('2 downloads failed'), findsOneWidget);
      expect(find.text('Check your connection'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pack_retry')));
      await tester.pump();
      expect(pack.retried.toSet(), {'sea', 'ocean'});
    });

    testWidgets('is gone when every sound is on the phone', (tester) async {
      await pump(tester, downloaded: packIds.toSet());
      expect(banner(), findsNothing);
    });
  });

  group('a mix that has sounds not on the phone', () {
    Future<void> mixWithMissing(WidgetTester tester) async {
      await pump(tester);
      final mixer = container.read(soundscapeProvider.notifier)
        ..toggleSound('river')
        ..toggleSound('sea')
        ..toggleSound('stream');
      expect(mixer.state.mix.contains('sea'), isTrue);
      await tester.pumpAndSettle();
    }

    testWidgets('plays the rest and says which need downloading', (
      tester,
    ) async {
      await mixWithMissing(tester);
      final state = container.read(soundscapeProvider);
      expect(state.playing, isTrue);
      expect(
        find.text('1 sound in this mix needs downloading. The rest plays.'),
        findsOneWidget,
      );
      // The same, once, as a message with the way to fix it.
      expect(
        find.byKey(const ValueKey('sound_missing_snackbar')),
        findsOneWidget,
      );
      expect(find.textContaining('Playing without'), findsOneWidget);
      expect(find.textContaining('sea'), findsWidgets);
    });

    testWidgets('its layer offers the download', (tester) async {
      await mixWithMissing(tester);
      await tester.tap(find.byKey(const ValueKey('sounds_mix_toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Needs download'), findsOneWidget);
      expect(find.byKey(const ValueKey('layer_download_river')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('layer_download_sea')));
      await tester.pumpAndSettle();
      expect(pack.asked, ['sea']);
      // It landed: the mix is whole, and the line is gone.
      expect(find.textContaining('Needs download'), findsNothing);
    });

    testWidgets('the snackbar fetches them', (tester) async {
      await mixWithMissing(tester);
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(pack.asked, ['sea']);
    });

    testWidgets('a saved preset says how many it is missing', (tester) async {
      await pump(tester);
      container.read(soundscapeProvider.notifier)
        ..toggleSound('river')
        ..toggleSound('sea')
        ..savePreset('Mine');
      await tester.pumpAndSettle();
      final userPreset = container
          .read(soundscapeProvider)
          .userPresets
          .single
          .id;
      final chip = find.byKey(ValueKey('preset_missing_$userPreset'));
      await tester.scrollUntilVisible(
        chip,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('sounds_presets')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(chip, findsOneWidget);
      expect(
        find.descendant(
          of: chip,
          matching: find.text('1 sound needs downloading'),
        ),
        findsOneWidget,
      );
      // The starter presets are whole.
      expect(
        find.byKey(const ValueKey('preset_missing_starter-night')),
        findsNothing,
      );
    });
  });

  testWidgets('the credits list every sound, downloaded or not', (
    tester,
  ) async {
    await pump(tester, downloaded: const {}, home: const SoundCreditsView());
    for (final sound in bundledSoundLibrary.sounds) {
      await tester.scrollUntilVisible(
        find.text(sound.title).first,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(sound.title), findsWidgets, reason: sound.id);
    }
    expect(find.text('Rain on a car roof'), findsWidgets);
  });

  group('Settings › Library & downloads', () {
    testWidgets('shows what is on the phone, and deletes it after asking', (
      tester,
    ) async {
      await pump(tester, home: const SoundPackTile());
      expect(find.text('Downloaded sounds'), findsOneWidget);
      expect(
        find.textContaining('${have.length} of ${packIds.length}'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('settings_sound_pack_delete')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete downloaded sounds?'), findsOneWidget);
      expect(pack.deletes, 0);
      await tester.tap(
        find.byKey(const ValueKey('settings_sound_pack_delete_confirm')),
      );
      await tester.pumpAndSettle();
      expect(pack.deletes, 1);
      expect(find.textContaining('None downloaded'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings_sound_pack_delete')),
        findsNothing,
      );
    });

    testWidgets('cancelling the dialog keeps the sounds', (tester) async {
      await pump(tester, home: const SoundPackTile());
      await tester.tap(
        find.byKey(const ValueKey('settings_sound_pack_delete')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(pack.deletes, 0);
    });

    testWidgets('Wi-Fi only is on until it is switched off', (tester) async {
      await pump(tester, home: const SoundPackWifiTile());
      Switch toggle() => tester.widget<Switch>(find.byType(Switch));
      expect(toggle().value, isTrue);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(toggle().value, isFalse);
      expect(container.read(soundPackProvider).wifiOnly, isFalse);
    });
  });
}
