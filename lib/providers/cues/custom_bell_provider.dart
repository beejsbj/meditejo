import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/bells/bell_synth.dart';
import 'package:medito/services/bells/custom_bell.dart';
import 'package:medito/services/bells/custom_bell_store.dart';

final customBellStoreProvider = Provider<CustomBellStore>(
  (ref) => CustomBellStore(ref.watch(sharedPreferencesProvider)),
);

/// The bells the user made, oldest first.
final customBellsProvider =
    NotifierProvider<CustomBellsNotifier, List<CustomBell>>(
      CustomBellsNotifier.new,
    );

class CustomBellsNotifier extends Notifier<List<CustomBell>> {
  CustomBellStore get _store => ref.read(customBellStoreProvider);

  @override
  List<CustomBell> build() => ref.watch(customBellStoreProvider).all();

  Future<CustomBell> save({
    required String name,
    required BellSpec spec,
    Uint8List? wav,
  }) async {
    final bell = await _store.save(name: name, spec: spec, wav: wav);
    state = _store.all();
    return bell;
  }

  Future<void> rename(String id, String name) async {
    await _store.rename(id, name);
    state = _store.all();
  }

  /// Removes the bell and its file. Every cue that rang it rings the default
  /// bell instead.
  Future<void> delete(String id) async {
    await _store.delete(id);
    await ref.read(cueSettingsStoreProvider).replaceSound(id, cueDefaultBell);
    ref.invalidate(cueSettingsProvider);
    state = _store.all();
  }
}
