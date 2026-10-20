import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../utils/logger.dart';

/// What the platform asks of the mixer: the notification's Stop action, or
/// audio focus moving to another app and back.
///
/// `pause` and `resume` are a transient loss (a call) and its end; `lost` is
/// another app taking over playback for good, or focus refused outright;
/// `noisy` is the headphones being unplugged (Android would move the sound
/// to the speaker).
enum SoundscapeCommand { stop, pause, lost, resume, noisy }

/// Holds the app in the foreground while Sounds play outside a session
/// (Android's `SoundscapeService`), so they continue with the screen off.
abstract interface class SoundscapeKeepAlive {
  /// Whether the service is (now) in the foreground.
  Future<bool> hold({
    required String title,
    required String text,
    required String stopLabel,
  });

  Future<void> release();

  /// Asks for audio focus again (resuming after another app took it).
  Future<void> requestFocus();

  Stream<SoundscapeCommand> get commands;
}

class NoopSoundscapeKeepAlive implements SoundscapeKeepAlive {
  const NoopSoundscapeKeepAlive();

  @override
  Future<bool> hold({
    required String title,
    required String text,
    required String stopLabel,
  }) async => true;

  @override
  Future<void> release() async {}

  @override
  Future<void> requestFocus() async {}

  @override
  Stream<SoundscapeCommand> get commands => const Stream.empty();
}

class MethodChannelSoundscapeKeepAlive implements SoundscapeKeepAlive {
  MethodChannelSoundscapeKeepAlive({
    MethodChannel channel = const MethodChannel('meditejo/soundscape'),
  }) : _channel = channel {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'command') return;
      for (final c in SoundscapeCommand.values) {
        if (c.name == call.arguments) _commands.add(c);
      }
    });
  }

  final MethodChannel _channel;
  final _commands = StreamController<SoundscapeCommand>.broadcast();

  @override
  Stream<SoundscapeCommand> get commands => _commands.stream;

  @override
  Future<bool> hold({
    required String title,
    required String text,
    required String stopLabel,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('hold', {
            'title': title,
            'text': text,
            'stopLabel': stopLabel,
          }) ??
          false;
    } on PlatformException catch (e) {
      AppLogger.e('SOUNDSCAPE', 'Keep-alive hold failed', e);
      return false;
    } on MissingPluginException {
      // A build without the native side: sounds still play in the foreground.
      return true;
    }
  }

  @override
  Future<void> requestFocus() async {
    try {
      await _channel.invokeMethod('focus');
    } on PlatformException catch (e) {
      AppLogger.e('SOUNDSCAPE', 'Keep-alive focus failed', e);
    } on MissingPluginException {
      // See hold().
    }
  }

  @override
  Future<void> release() async {
    try {
      await _channel.invokeMethod('release');
    } on PlatformException catch (e) {
      AppLogger.e('SOUNDSCAPE', 'Keep-alive release failed', e);
    } on MissingPluginException {
      // See hold().
    }
  }
}

/// Only Android has a service to hold. iOS standalone playback with the
/// screen locked is untested (Meditejo is used on Android).
SoundscapeKeepAlive platformSoundscapeKeepAlive() => Platform.isAndroid
    ? MethodChannelSoundscapeKeepAlive()
    : const NoopSoundscapeKeepAlive();
