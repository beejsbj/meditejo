import '../../utils/logger.dart';
import 'dart:async';
import 'dart:convert';

import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:medito/models/background_sounds/background_sounds_model.dart';

part 'background_sounds_repository.g.dart';

abstract class BackgroundSoundsRepository {
  Future<List<BackgroundSoundsModel>> fetchBackgroundSounds();

  Future<List<BackgroundSoundsModel>?> fetchLocallySavedBackgroundSounds();

  /// Available local ambient recordings. Never returns legacy remote sounds.
  List<BackgroundSoundsModel> fetchCachedBackgroundSounds();

  Future<void> updateItemsInSavedBgSoundList(BackgroundSoundsModel sound);

  /// The ambient sound, one choice shared by tracks and the Timer.
  void saveSelectedBgSoundToSharedPreferences(BackgroundSoundsModel sound);

  /// The ambient sound (never session bells, which are a separate switch).
  BackgroundSoundsModel? getSelectedBgSoundFromSharedPreferences();

  /// Bells default on for the Timer and off under tracks, except for users
  /// who had picked bells as their background sound before they were a switch.
  bool getSessionBellsEnabled({bool forTimer = false});

  void saveSessionBellsEnabled(bool enabled, {bool forTimer = false});

  void removeSelectedBgSound();

  void handleOnChangeVolume(double vol);

  double? getBgSoundVolume();
}

class BackgroundSoundsRepositoryImpl extends BackgroundSoundsRepository {
  final Ref ref;
  final LocalCatalogue catalogue;

  BackgroundSoundsRepositoryImpl({
    required this.ref,
    this.catalogue = const LocalCatalogue(),
  });

  @override
  Future<List<BackgroundSoundsModel>> fetchBackgroundSounds() async =>
      catalogue.backgroundSounds;

  @override
  List<BackgroundSoundsModel> fetchCachedBackgroundSounds() =>
      catalogue.backgroundSounds;

  @override
  Future<List<BackgroundSoundsModel>?>
  fetchLocallySavedBackgroundSounds() async {
    final pref = ref.read(sharedPreferencesProvider);
    final saved =
        pref.getStringList(SharedPreferenceConstants.listBgSound) ?? [];
    final available = catalogue.backgroundSounds;
    return [
      for (final sound in available)
        if (saved.any((entry) => _savedSoundId(entry) == sound.id)) sound,
    ];
  }

  String? _savedSoundId(String entry) {
    try {
      final value = jsonDecode(entry);
      return value is Map && value['id'] is String
          ? value['id'] as String
          : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> updateItemsInSavedBgSoundList(
    BackgroundSoundsModel sound,
  ) async {
    try {
      if (sound.id == kNoneBackgroundSoundId || sound.id == kSessionBellsId) {
        return;
      } else {
        var pref = ref.read(sharedPreferencesProvider);
        var soundList =
            pref.getStringList(SharedPreferenceConstants.listBgSound) ?? [];
        var sounds = <BackgroundSoundsModel>[];
        for (var element in soundList) {
          sounds.add(BackgroundSoundsModel.fromJson(json.decode(element)));
        }
        var index = sounds.indexWhere((element) => element.id == sound.id);
        if (index == -1) {
          sounds.add(sound);
          var encodeSounds = sounds.map((e) => json.encode(e)).toList();
          await pref.setStringList(
            SharedPreferenceConstants.listBgSound,
            encodeSounds,
          );
        }
      }
    } catch (err) {
      AppLogger.d('BACKGROUND', err.toString());
    }
  }

  @override
  void saveSelectedBgSoundToSharedPreferences(BackgroundSoundsModel sound) {
    var bgSoundJson = json.encode(sound.toJson());
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setString(SharedPreferenceConstants.bgSound, bgSoundJson),
    );
  }

  @override
  BackgroundSoundsModel? getSelectedBgSoundFromSharedPreferences() {
    var bgSoundJson = ref
        .read(sharedPreferencesProvider)
        .getString(SharedPreferenceConstants.bgSound);

    if (bgSoundJson == null) return null;
    final id = _savedSoundId(bgSoundJson);
    // Resolve through the local catalogue so stale saved URLs never play.
    for (final sound in catalogue.backgroundSounds) {
      if (sound.id == id) return sound;
    }
    return null;
  }

  @override
  bool getSessionBellsEnabled({bool forTimer = false}) {
    final prefs = ref.read(sharedPreferencesProvider);
    final saved = prefs.getBool(
      forTimer
          ? SharedPreferenceConstants.timerSessionBellsEnabled
          : SharedPreferenceConstants.sessionBellsEnabled,
    );
    if (saved != null) return saved;
    if (forTimer) return true;
    final legacy = prefs.getString(SharedPreferenceConstants.bgSound);
    return legacy != null && legacy.contains('"$kSessionBellsId"');
  }

  @override
  void saveSessionBellsEnabled(bool enabled, {bool forTimer = false}) {
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setBool(
            forTimer
                ? SharedPreferenceConstants.timerSessionBellsEnabled
                : SharedPreferenceConstants.sessionBellsEnabled,
            enabled,
          ),
    );
  }

  @override
  void removeSelectedBgSound() {
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .remove(SharedPreferenceConstants.bgSound),
    );
  }

  @override
  double? getBgSoundVolume() {
    return ref
        .read(sharedPreferencesProvider)
        .getDouble(SharedPreferenceConstants.bgSoundVolume);
  }

  @override
  void handleOnChangeVolume(double vol) {
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setDouble(SharedPreferenceConstants.bgSoundVolume, vol),
    );
  }
}

@riverpod
BackgroundSoundsRepository backgroundSoundsRepository(Ref ref) {
  return BackgroundSoundsRepositoryImpl(ref: ref);
}
