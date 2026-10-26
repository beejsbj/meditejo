import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/identity/daily_mark.dart';
import 'package:medito/services/identity/mark_generator.dart';
import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/utils/logger.dart';

/// The clock the identity reads. Tests replace it.
@visibleForTesting
DateTime Function() identityClock = DateTime.now;

/// Today's local date (midnight). [IdentityDay.refresh] picks up a new day:
/// `main.dart` calls it from its once-a-minute day tick, so the mark and a
/// daily palette turn over within a minute of local midnight, and again on
/// resume (no timer runs while the app sleeps). The provider owns no timer
/// itself, so a test's container leaves nothing pending.
final identityDayProvider = NotifierProvider<IdentityDay, DateTime>(
  IdentityDay.new,
);

class IdentityDay extends Notifier<DateTime> {
  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  @override
  DateTime build() => _dayOf(identityClock());

  /// Picks up a new day, if one has begun.
  void refresh() {
    final today = _dayOf(identityClock());
    if (today != state) state = today;
  }
}

/// The palette setting: the date's palette, or one chosen and kept.
sealed class PaletteChoice {
  const PaletteChoice();
}

class DailyPalette extends PaletteChoice {
  const DailyPalette();

  @override
  bool operator ==(Object other) => other is DailyPalette;

  @override
  int get hashCode => 0;
}

class FixedPalette extends PaletteChoice {
  const FixedPalette(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is FixedPalette && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final paletteChoiceProvider =
    NotifierProvider<PaletteChoiceNotifier, PaletteChoice>(
      PaletteChoiceNotifier.new,
    );

class PaletteChoiceNotifier extends Notifier<PaletteChoice> {
  static const _daily = 'daily';

  @override
  PaletteChoice build() {
    final saved = ref
        .read(sharedPreferencesProvider)
        .getString(SharedPreferenceConstants.identityPalette);
    if (saved == _daily) return const DailyPalette();
    return FixedPalette(IdentityPalettes.byId(saved).id);
  }

  Future<void> choose(PaletteChoice choice) async {
    state = choice;
    await ref.read(sharedPreferencesProvider).setString(
      SharedPreferenceConstants.identityPalette,
      switch (choice) {
        DailyPalette() => _daily,
        FixedPalette(:final id) => id,
      },
    );
  }
}

/// The palette the app wears today.
final activePaletteProvider = Provider<IdentityPalette>((ref) {
  return switch (ref.watch(paletteChoiceProvider)) {
    DailyPalette() => DailyMark.paletteFor(ref.watch(identityDayProvider)),
    FixedPalette(:final id) => IdentityPalettes.byId(id),
  };
});

/// The pinned Home mark, stored as frozen geometry so a later change to the
/// generator never redraws it. Null: the mark changes daily.
final pinnedMarkProvider = NotifierProvider<PinnedMarkNotifier, MarkSpec?>(
  PinnedMarkNotifier.new,
);

class PinnedMarkNotifier extends Notifier<MarkSpec?> {
  @override
  MarkSpec? build() {
    final saved = ref
        .read(sharedPreferencesProvider)
        .getString(SharedPreferenceConstants.identityPinnedMark);
    if (saved == null) return null;
    try {
      return MarkSpec.decode(saved);
    } catch (e) {
      // A pin from a newer build, or damaged: fall back to the daily mark
      // rather than fail Home.
      AppLogger.e('IDENTITY', 'Unreadable pinned mark', e);
      return null;
    }
  }

  /// Keeps [mark] on Home, exactly as it is drawn now.
  Future<void> pin(MarkSpec mark) async {
    state = mark;
    await ref
        .read(sharedPreferencesProvider)
        .setString(SharedPreferenceConstants.identityPinnedMark, mark.encode());
  }

  /// Back to the daily mark.
  Future<void> unpin() async {
    state = null;
    await ref
        .read(sharedPreferencesProvider)
        .remove(SharedPreferenceConstants.identityPinnedMark);
  }
}

/// Today's daily mark (built once per day).
final dailyMarkProvider = Provider<MarkSpec>((ref) {
  final pick = DailyMark.forDay(ref.watch(identityDayProvider));
  return MarkGenerator.build(pick.seed);
});

/// The mark on Home: the pinned one, else today's.
final homeMarkProvider = Provider<MarkSpec>(
  (ref) => ref.watch(pinnedMarkProvider) ?? ref.watch(dailyMarkProvider),
);
