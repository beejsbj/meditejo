import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/services/bells/bell_synth.dart';
import 'package:medito/services/bells/custom_bell.dart';

/// The bells the user made. The list (names, starting bell, controls) is a
/// JSON value in preferences; each bell's WAV is a file in app storage that
/// the native cue engine plays by path. A bell's id is stable, and so is its
/// file's name, so a cue never has to be told a bell was renamed.
///
/// The WAV is a cache of the controls: a file that went missing is rendered
/// again, byte for byte, the next time something asks for it.
class CustomBellStore {
  CustomBellStore(
    this.prefs, {
    Future<Directory> Function()? directory,
    Future<Uint8List> Function(BellSpec spec)? render,
    math.Random? random,
    DateTime Function()? now,
  }) : _directory = directory ?? _defaultDirectory,
       _render = render ?? renderBellWavInBackground,
       _random = random ?? math.Random.secure(),
       _now = now ?? DateTime.now;

  /// The preferences key of the list.
  static const prefsKey = 'bells.custom.v1';

  /// Bells a user can keep; each file is up to about half a megabyte.
  static const maxBells = 30;

  final SharedPreferences prefs;
  final Future<Directory> Function() _directory;
  final Future<Uint8List> Function(BellSpec spec) _render;
  final math.Random _random;
  final DateTime Function() _now;

  // Writes go one at a time, so two quick saves cannot lose one.
  Future<void> _queue = Future.value();

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/custom_bells');
  }

  /// The saved bells, oldest first. Entries this version cannot read are
  /// skipped, and left in storage for a newer one.
  List<CustomBell> all() {
    final raw = prefs.getString(prefsKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final bells = [for (final e in decoded) ?CustomBell.tryFromJson(e)]
        ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
      return bells;
    } catch (_) {
      return const [];
    }
  }

  CustomBell? find(String id) {
    for (final b in all()) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// A name for a new bell that no other has: "My bell", "My bell 2"...
  String suggestName([String base = 'My bell']) {
    final taken = {for (final b in all()) b.name.toLowerCase()};
    if (!taken.contains(base.toLowerCase())) return base;
    for (var i = 2; ; i++) {
      final name = '$base $i';
      if (!taken.contains(name.toLowerCase())) return name;
    }
  }

  /// Keeps [spec] as a new bell called [name]. [wav] is its sound when the
  /// caller has already made it (it must be [spec]'s render); else it is made
  /// here.
  Future<CustomBell> save({
    required String name,
    required BellSpec spec,
    Uint8List? wav,
  }) => _serial(() async {
    final clean = cleanBellName(name);
    if (clean == null) throw ArgumentError.value(name, 'name', 'empty');
    final bells = _raw();
    if (bells.length >= maxBells) {
      throw StateError('Only $maxBells bells can be kept.');
    }
    final id = _newId({for (final b in bells) b['id']});
    final bell = CustomBell(
      id: id,
      name: clean,
      preset: spec.preset,
      knobs: spec.knobs,
      createdAtMs: _now().millisecondsSinceEpoch,
    );
    await _write(bell, wav ?? await _render(spec));
    await prefs.setString(prefsKey, jsonEncode([...bells, bell.toJson()]));
    return bell;
  });

  Future<void> rename(String id, String name) => _serial(() async {
    final clean = cleanBellName(name);
    if (clean == null) throw ArgumentError.value(name, 'name', 'empty');
    final bells = _raw();
    final at = bells.indexWhere((b) => b['id'] == id);
    if (at < 0) return;
    bells[at] = {...bells[at], 'name': clean};
    await prefs.setString(prefsKey, jsonEncode(bells));
  });

  /// Forgets the bell and removes its file. Cues that ring it are the
  /// caller's to move (`CueSettingsStore.replaceSound`).
  Future<void> delete(String id) => _serial(() async {
    final bells = _raw();
    final kept = [
      for (final b in bells)
        if (b['id'] != id) b,
    ];
    if (kept.length != bells.length) {
      await prefs.setString(prefsKey, jsonEncode(kept));
    }
    if (!isCustomBellId(id)) return;
    final file = await _file(id.substring(customBellPrefix.length));
    if (await file.exists()) await file.delete();
  });

  /// The path of bell [id]'s WAV, for the native engine and the preview;
  /// rendered again if the file is gone. Null when there is no such bell.
  Future<String?> fileFor(String id) => _serial(() async {
    final bell = find(id);
    if (bell == null) return null;
    final file = await _file(bell.token);
    if (!await file.exists() || await file.length() == 0) {
      await _write(bell, await _render(bell.spec));
    }
    return file.path;
  });

  /// [fileFor] with the preferences of the app, for callers that have no
  /// store of their own (the native cue channel).
  static Future<String?> sharedFileFor(String id) async =>
      CustomBellStore(await SharedPreferences.getInstance()).fileFor(id);

  List<Map<String, Object?>> _raw() {
    final raw = prefs.getString(prefsKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List
          ? [
              for (final e in decoded)
                if (e is Map) e.cast<String, Object?>(),
            ]
          : [];
    } catch (_) {
      return [];
    }
  }

  String _newId(Set<Object?> taken) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    while (true) {
      final token = String.fromCharCodes([
        for (var i = 0; i < 10; i++)
          alphabet.codeUnitAt(_random.nextInt(alphabet.length)),
      ]);
      if (!taken.contains('$customBellPrefix$token')) {
        return '$customBellPrefix$token';
      }
    }
  }

  Future<File> _file(String token) async =>
      File('${(await _directory()).path}/$token.wav');

  Future<void> _write(CustomBell bell, Uint8List wav) async {
    final file = await _file(bell.token);
    await file.parent.create(recursive: true);
    // Whole or not at all: the engine must never open half a bell.
    final partial = File('${file.path}.part');
    await partial.writeAsBytes(wav, flush: true);
    await partial.rename(file.path);
  }

  Future<T> _serial<T>(Future<T> Function() job) {
    final done = _queue.then((_) => job());
    _queue = done.then<void>((_) {}, onError: (_) {});
    return done;
  }
}

/// Where a cue's bell lives for the native engine: the file's path for a
/// bell the user made, the sound itself for a bundled one. A bell that was
/// deleted, or cannot be made again, rings as the default bell rather than
/// not at all.
Future<String> nativeBellSound(
  String sound,
  Future<String?> Function(String id) fileFor,
) async {
  if (!isCustomBellId(sound)) return sound;
  try {
    return await fileFor(sound) ?? cueDefaultBell;
  } catch (_) {
    return cueDefaultBell;
  }
}
