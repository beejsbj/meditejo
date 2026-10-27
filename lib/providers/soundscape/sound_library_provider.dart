import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/soundscape/sound_library.dart';
import '../../utils/logger.dart';

/// The library (`assets/sounds/sounds.json`): every sound, bundled or part of
/// the downloadable pack, with its licence.
final soundLibraryProvider = FutureProvider<SoundLibrary>((ref) async {
  ref.keepAlive();
  try {
    final raw = await rootBundle.loadString(kSoundLibraryAsset);
    return SoundLibrary.fromJson(jsonDecode(raw) as Map<String, Object?>);
  } catch (error, stack) {
    AppLogger.e('SOUNDSCAPE', 'Could not read the sound library', error, stack);
    return SoundLibrary.empty;
  }
});
