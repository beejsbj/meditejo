import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../utils/logger.dart';

/// What the platform asks of the mixer: the notification's Stop action, or
/// audio focus moving to another app and back.
enum SoundscapeCommand { stop, pause, resume }

/// Holds the app in the foreground while Sounds play outside a session
/// (Android's `SoundscapeService`), so they continue with the screen off.
abstract interface class SoundscapeKeepAlive {
  Future<void> hold({
    required String title,
    required String text,
    required String stopLabel,
  });

  Future<void> release();

  Stream<SoundscapeCommand> get commands;
}

class NoopSoundscapeKeepAlive implements SoundscapeKeepAlive {
  const NoopSoundscapeKeepAlive();

  @override
  Future<void> hold({
    required String title,
    required String text,
    required String stopLabel,
  }) async {}

  @override
  Future<void> release() async {}

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
  Future<void> hold({
    required String title,
    required String text,
    required String stopLabel,
  }) async {
    try {
      await _channel.invokeMethod('hold', {
        'title': title,
        'text': text,
        'stopLabel': stopLabel,
      });
    } on PlatformException catch (e) {
      AppLogger.e('SOUNDSCAPE', 'Keep-alive hold failed', e);
    } on MissingPluginException {
      // A build without the native side: sounds still play in the foreground.
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
