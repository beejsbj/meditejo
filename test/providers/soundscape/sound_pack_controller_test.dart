import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/sound_pack_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/soundscape/sound_pack_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

void main() {
  late SoundPackFixture fixture;
  late ProviderContainer container;
  late SharedPreferences prefs;

  final packIds = [for (final s in bundledSoundLibrary.packSounds) s.id];

  Future<ProviderContainer> make({
    Set<String> onPhone = const {},
    Map<String, Object> values = const {},
  }) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = await SharedPreferences.getInstance();
    fixture.stage(bundledSoundLibrary, onPhone);
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        soundLibraryProvider.overrideWith((ref) async => bundledSoundLibrary),
        ...fixture.overrides,
      ],
    );
    addTearDown(c.dispose);
    await c.read(soundPackProvider.notifier).ready;
    return c;
  }

  SoundPackController pack() => container.read(soundPackProvider.notifier);
  SoundPackState st() => container.read(soundPackProvider);

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() => fixture = SoundPackFixture());
  tearDown(() => fixture.dispose());

  test('nothing is downloaded on its own, and Wi-Fi only is on', () async {
    container = await make();
    await settle();
    expect(st().scanned, isTrue);
    expect(st().downloaded, isEmpty);
    expect(st().wifiOnly, isTrue);
    expect(st().busy, isFalse);
    expect(fixture.downloader.calls, isEmpty);
  });

  test('what is on the phone is found again after a restart', () async {
    container = await make(onPhone: {packIds[0], packIds[1]});
    expect(st().downloaded, {packIds[0], packIds[1]});
    expect(st().usedBytes, greaterThan(0));
    final sound = bundledSoundLibrary[packIds[0]]!;
    expect(st().isAvailable(sound), isTrue);
    expect(st().isAvailable(bundledSoundLibrary[packIds[2]]!), isFalse);
    // Bundled sounds never need a file.
    expect(
      st().isAvailable(bundledSoundLibrary.sounds.firstWhere((s) => s.bundled)),
      isTrue,
    );
  });

  test('a download arrives, is counted, and leaves the queue', () async {
    container = await make();
    await pack().download([packIds.first]);
    await settle();
    expect(fixture.downloader.calls, [packIds.first]);
    expect(st().downloaded, {packIds.first});
    expect(st().downloads, isEmpty);
    expect(pack().fileOf(bundledSoundLibrary[packIds.first]!), isNotNull);
    expect(st().usedBytes, bundledSoundLibrary[packIds.first]!.bytes);
  });

  test('Download all takes every pack sound, one at a time', () async {
    container = await make(onPhone: {packIds.first});
    await pack().downloadAll();
    await settle();
    expect(fixture.downloader.calls, packIds.skip(1).toList());
    expect(st().downloaded, packIds.toSet());
    expect(st().batchDone, packIds.length - 1);
    expect(st().batchTotal, packIds.length - 1);
  });

  test('a bundled or unknown sound is not downloaded', () async {
    container = await make();
    final bundled = bundledSoundLibrary.sounds.firstWhere((s) => s.bundled);
    await pack().download([bundled.id, 'no-such-sound']);
    await settle();
    expect(fixture.downloader.calls, isEmpty);
    expect(st().downloads, isEmpty);
  });

  test('progress shows while it downloads, and a cancel drops it', () async {
    container = await make();
    final id = packIds.first;
    fixture.downloader.held.add(id);
    await pack().download([id]);
    await settle();
    final running = st().downloadOf(id)!;
    expect(running.phase, SoundDownloadPhase.downloading);
    expect(running.progress, closeTo(0.5, 0.01));
    expect(st().busy, isTrue);

    pack().cancel(id);
    await settle();
    expect(st().downloads, isEmpty);
    expect(st().downloaded, isEmpty);
    expect(st().busy, isFalse);
  });

  test('a failure is kept for a retry, with why, then succeeds', () async {
    container = await make();
    final id = packIds.first;
    fixture.downloader.failures[id] = SoundDownloadFailure.network;
    await pack().download([id]);
    await settle();
    final failed = st().downloadOf(id)!;
    expect(failed.phase, SoundDownloadPhase.failed);
    expect(failed.failure, SoundDownloadFailure.network);
    expect(st().hasFailures, isTrue);
    expect(st().downloaded, isEmpty);

    fixture.downloader.failures.clear();
    await pack().retry();
    await settle();
    expect(st().downloaded, {id});
    expect(st().hasFailures, isFalse);
  });

  test('one failure does not stop the others', () async {
    container = await make();
    fixture.downloader.failures[packIds[0]] = SoundDownloadFailure.integrity;
    await pack().download(packIds.take(3));
    await settle();
    expect(st().downloaded, {packIds[1], packIds[2]});
    expect(
      st().downloadOf(packIds[0])!.failure,
      SoundDownloadFailure.integrity,
    );
  });

  group('Wi-Fi only', () {
    setUp(() => fixture = SoundPackFixture(unmetered: false));

    test('a download waits on mobile data, and says so', () async {
      container = await make();
      await pack().download([packIds.first]);
      await settle();
      expect(fixture.downloader.calls, isEmpty);
      expect(st().waitingForWifi, isTrue);
      expect(st().downloadOf(packIds.first)!.phase, SoundDownloadPhase.queued);
    });

    test('and goes ahead when Wi-Fi comes back', () async {
      container = await make();
      await pack().download([packIds.first, packIds[1]]);
      await settle();
      fixture.network.setUnmetered(true);
      await settle();
      expect(st().waitingForWifi, isFalse);
      expect(st().downloaded, {packIds.first, packIds[1]});
    });

    test('Download anyway goes ahead on mobile data', () async {
      container = await make();
      await pack().download([packIds.first]);
      await settle();
      await pack().download([packIds.first], anyNetwork: true);
      await settle();
      expect(st().downloaded, {packIds.first});
      expect(st().waitingForWifi, isFalse);
    });

    test('switching the setting off releases the queue', () async {
      container = await make();
      await pack().download([packIds.first]);
      await settle();
      await pack().setWifiOnly(false);
      await settle();
      expect(st().downloaded, {packIds.first});
      expect(prefs.getBool(kSoundPackWifiOnlyKey), isFalse);
    });

    test('the setting is remembered', () async {
      container = await make(values: {kSoundPackWifiOnlyKey: false});
      expect(st().wifiOnly, isFalse);
      await pack().download([packIds.first]);
      await settle();
      expect(st().downloaded, {packIds.first});
    });

    test('Cancel while waiting forgets the queue', () async {
      container = await make();
      await pack().download(packIds.take(3));
      await settle();
      pack().cancelAll();
      fixture.network.setUnmetered(true);
      await settle();
      expect(fixture.downloader.calls, isEmpty);
      expect(st().downloads, isEmpty);
      expect(st().waitingForWifi, isFalse);
    });
  });

  test('deleting the pack frees the space and forgets the sounds', () async {
    container = await make(onPhone: {packIds[0], packIds[1]});
    expect(st().usedBytes, greaterThan(0));
    await pack().deleteAll();
    expect(st().downloaded, isEmpty);
    expect(st().usedBytes, 0);
    final again = await make();
    expect(again.read(soundPackProvider).downloaded, isEmpty);
  });

  test('a stale or partial file is tidied away on the next start', () async {
    container = await make(onPhone: {packIds[0]});
    final dir = fixture.directory.path;
    final stale = '$dir/pack/${packIds[1]}-000000000000.opus';
    final part = '$dir/pack/${packIds[2]}.opus.part';
    await Future.wait([_write(stale, 10), _write(part, 10)]);
    container = await make();
    expect(_exists(stale), isFalse);
    expect(_exists(part), isFalse);
    expect(container.read(soundPackProvider).downloaded, {packIds[0]});
  });
}

Future<void> _write(String path, int length) async {
  final file = File(path)..createSync(recursive: true);
  file.writeAsBytesSync(List.filled(length, 1));
}

bool _exists(String path) => File(path).existsSync();
