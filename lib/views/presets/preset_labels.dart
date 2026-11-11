import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/presets/preset.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/providers/cues/custom_bell_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/bells/custom_bell.dart';
import 'package:medito/views/soundscape/sound_labels.dart';
import 'package:medito/views/timer/timer_format.dart';

/// The name of a slot, as Customize names it.
String presetSlotName(AppLocalizations l10n, PresetSlot slot) => switch (slot) {
  PresetSlot.sound => l10n.customizeSlotSound,
  PresetSlot.bells => l10n.presetSlotBells,
  PresetSlot.rhythm => l10n.customizeSlotRhythm,
  PresetSlot.length => l10n.presetSlotLength,
};

IconData presetSlotIcon(PresetSlot slot) => switch (slot) {
  PresetSlot.sound => Icons.graphic_eq_rounded,
  PresetSlot.bells => Icons.notifications_none_rounded,
  PresetSlot.rhythm => Icons.monitor_heart_outlined,
  PresetSlot.length => Icons.timer_outlined,
};

/// Says what slots hold, in words. Built once per build from what it needs
/// to name things: the sound library and the bells the user made.
class PresetWords {
  const PresetWords(this.l10n, this.library, this.customBells);

  factory PresetWords.of(BuildContext context, WidgetRef ref) => PresetWords(
    AppLocalizations.of(context)!,
    ref.watch(soundLibraryProvider).value ?? SoundLibrary.empty,
    ref.watch(customBellsProvider),
  );

  final AppLocalizations l10n;
  final SoundLibrary library;
  final List<CustomBell> customBells;

  /// A bell by name; one that was deleted rings as the default bell.
  String bellName(String id) {
    if (isCustomBellId(id)) {
      for (final bell in customBells) {
        if (bell.id == id) return bell.name;
      }
      return bellName(cueDefaultBell);
    }
    return cueBellSounds.entries
        .firstWhere(
          (e) => e.value == id,
          orElse: () => cueBellSounds.entries.first,
        )
        .key;
  }

  /// What [slot] of [slots] holds, or null when it is empty. [short] is a
  /// word or two, for a line that names several slots ("Rain · Singing
  /// bowl · 20 min"); otherwise the fuller value beside the slot's name.
  String? value(
    PresetSlots slots,
    PresetSlot slot, {
    bool short = false,
  }) => switch (slot) {
    PresetSlot.sound => switch (slots.sound) {
      null => null,
      final mix when mix.isEmpty =>
        short ? l10n.presetNoSound : l10n.customizeOff,
      final mix => () {
        final layers = [...mix.layers]
          ..sort((a, b) => b.volume.compareTo(a.volume));
        final titles = [
          for (final layer in layers) ?soundTitle(l10n, layer.soundId, library),
        ];
        if (titles.isEmpty) return l10n.soundsLayerCount(layers.length);
        if (!short) return titles.join(', ');
        return titles.length == 1
            ? titles.first
            : '${titles.first} +${titles.length - 1}';
      }(),
    },
    PresetSlot.bells => switch (slots.bells?.asSettings) {
      null => null,
      final s => _bells(s, short: short),
    },
    PresetSlot.rhythm => switch (slots.rhythm?.asSettings) {
      null => null,
      final s when s.pulseSound.isEmpty =>
        short ? l10n.presetNoRhythm : l10n.customizeOff,
      final s => () {
        final name = cuePulseSounds.entries
            .firstWhere(
              (e) => e.value == s.pulseSound,
              orElse: () => cuePulseSounds.entries.first,
            )
            .key;
        return short ? name : '$name · ${s.pulseBpm.round()} BPM';
      }(),
    },
    PresetSlot.length => switch (slots.length) {
      null => null,
      final length => switch (length.minutes) {
        null => '∞',
        final minutes => formatTimerLength(Duration(minutes: minutes), l10n),
      },
    },
  };

  String _bells(CueSettings s, {required bool short}) {
    final names = <String>[
      if (s.startSound.isNotEmpty) bellName(s.startSound),
      if (s.endSound.isNotEmpty && s.endSound != s.startSound)
        bellName(s.endSound),
    ];
    final interval = !s.hasIntervalBell
        ? null
        : s.intervalHalfway
        ? l10n.customizeBellsHalfway
        : l10n.customizeBellsEvery(s.intervalMinutes);
    if (names.isEmpty && interval == null) {
      return short ? l10n.presetNoBells : l10n.customizeOff;
    }
    if (names.isEmpty) return interval!;
    if (short) return names.first;
    return [names.join(' / '), ?interval].join(' · ');
  }

  /// What every slot [slots] holds says, shortly, in slot order.
  List<(PresetSlot, String)> summary(PresetSlots slots) => [
    for (final slot in PresetSlot.values)
      if (value(slots, slot, short: true) case final text?) (slot, text),
  ];
}

/// What a preset sets, on one line: "Rain +2 · Singing bowl · 20 min".
/// The slots that do nothing here (not among [applies]) are muted.
class PresetSummary extends ConsumerWidget {
  const PresetSummary(
    this.slots, {
    super.key,
    required this.color,
    this.applies,
    this.style,
  });

  final PresetSlots slots;

  /// The slots in play where this is shown; null when all are.
  final Set<PresetSlot>? applies;
  final Color color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parts = PresetWords.of(context, ref).summary(slots);
    final muted = color.withValues(alpha: 0.5);
    return Text.rich(
      TextSpan(
        children: [
          for (final (i, (slot, text)) in parts.indexed) ...[
            if (i > 0)
              TextSpan(
                text: ' · ',
                style: TextStyle(color: muted),
              ),
            TextSpan(
              text: text,
              style: applies == null || applies!.contains(slot)
                  ? null
                  : TextStyle(color: muted),
            ),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (style ?? Theme.of(context).textTheme.bodySmall)?.copyWith(
        color: color,
      ),
    );
  }
}
