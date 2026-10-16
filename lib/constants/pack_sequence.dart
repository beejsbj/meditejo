library;

import 'package:medito/constants/config_constants.dart';

/// Optional source-provided progression behind "Your Path".
class PackSequence {
  const PackSequence._();

  // Sources may provide a progression later. No proprietary courses ship.
  static const List<String> ordered = <String>[];
  static const String experiencedEntryPackId = '';

  static String get beginnerEntryPackId => ordered.isEmpty ? '' : ordered.first;

  /// Every pack above concatenated into one. Retired by attrition: it stays the
  /// no-pin fallback so pre-change users keep their place in it.
  static String get legacyMegapackId => ConfigConstants.basicsPackId;

  /// Analytics dimension: 'megapack' | 'sequence' | 'custom'.
  static String modeFor(String packId) {
    if (packId == legacyMegapackId) return 'megapack';
    if (contains(packId)) return 'sequence';
    return 'custom';
  }

  /// True when finishing [packId] means there is no course content left — the
  /// last pack on the path, or the megapack, which holds the same material.
  static bool isPathTerminal(String packId) =>
      isLast(packId) || packId == legacyMegapackId;

  /// Null when [packId] is last on the path or not on it at all.
  static String? nextPackAfter(String packId) {
    final index = ordered.indexOf(packId);
    if (index == -1 || index == ordered.length - 1) return null;
    return ordered[index + 1];
  }

  static bool isLast(String packId) =>
      ordered.isNotEmpty && ordered.last == packId;

  static bool contains(String packId) => ordered.contains(packId);

  /// 1-based position, or null when not on the path.
  static int? positionOf(String packId) {
    final index = ordered.indexOf(packId);
    return index == -1 ? null : index + 1;
  }
}
