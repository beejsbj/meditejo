import 'dart:async';
import 'dart:io' show FileSystemException;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:medito/models/background_sounds/background_sounds_model.dart';
import 'package:medito/services/audio/session_bell_preview.dart';

class _Player extends Mock implements AudioPlayer {}

void main() {
  late _Player player;
  late SessionBellPreview preview;
  setUp(() {
    player = _Player();
    when(
      () => player.setAsset(kSessionBellAsset),
    ).thenAnswer((_) async => const Duration(seconds: 6));
    when(() => player.setVolume(any())).thenAnswer((_) async {});
    when(() => player.play()).thenAnswer((_) async {});
    when(() => player.stop()).thenAnswer((_) async {});
    when(() => player.dispose()).thenAnswer((_) async {});
    preview = SessionBellPreview(player: player);
  });

  test('audition plays the bundled bell without a primary player', () async {
    await preview.play(.4);
    verifyInOrder([
      () => player.setAsset(kSessionBellAsset),
      () => player.setVolume(.4),
      () => player.play(),
    ]);
  });

  const made = 'custom-bell:abc123xyz9';

  test('a made bell rings from its file', () async {
    when(
      () => player.setFilePath('/bells/a.wav'),
    ).thenAnswer((_) async => null);
    preview = SessionBellPreview(
      player: player,
      bellFile: (id) async => id == made ? '/bells/a.wav' : null,
    );
    await preview.play(.4, asset: made);
    verifyInOrder([
      () => player.setFilePath('/bells/a.wav'),
      () => player.setVolume(.4),
      () => player.play(),
    ]);
    verifyNever(() => player.setAsset(any()));
  });

  test('a made bell that is gone rings the default bell', () async {
    preview = SessionBellPreview(player: player, bellFile: (_) async => null);
    await preview.play(.4, asset: made);
    verifyInOrder([
      () => player.setAsset(kSessionBellAsset),
      () => player.setVolume(.4),
      () => player.play(),
    ]);
  });

  test(
    'a made bell that cannot be made again rings the default bell',
    () async {
      preview = SessionBellPreview(
        player: player,
        bellFile: (_) async => throw const FileSystemException('disk'),
      );
      await preview.play(.4, asset: made);
      verify(() => player.setAsset(kSessionBellAsset)).called(1);
      verify(() => player.play()).called(1);
    },
  );

  test('switching sounds during load cancels stale audition', () async {
    final loaded = Completer<Duration?>();
    when(
      () => player.setAsset(kSessionBellAsset),
    ).thenAnswer((_) => loaded.future);
    final pending = preview.play(.4);
    await preview.stop();
    loaded.complete(const Duration(seconds: 6));
    await pending;
    verifyNever(() => player.play());
  });

  test('dispose during load prevents late playback', () async {
    final loaded = Completer<Duration?>();
    when(
      () => player.setAsset(kSessionBellAsset),
    ).thenAnswer((_) => loaded.future);
    final pending = preview.play(.4);
    await preview.dispose();
    loaded.complete(const Duration(seconds: 6));
    await pending;
    verifyNever(() => player.play());
  });
}
