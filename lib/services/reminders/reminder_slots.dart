import 'package:flutter/material.dart';
import 'package:medito/l10n/app_localizations.dart';

/// The daily reminder presets shared by onboarding and settings.
enum ReminderSlot {
  morning(TimeOfDay(hour: 7, minute: 0)),
  evening(TimeOfDay(hour: 21, minute: 0)),
  night(TimeOfDay(hour: 22, minute: 0));

  const ReminderSlot(this.time);

  final TimeOfDay time;

  String label(AppLocalizations l10n) => switch (this) {
    ReminderSlot.morning => l10n.reminderSlotMorning,
    ReminderSlot.evening => l10n.reminderSlotEvening,
    ReminderSlot.night => l10n.reminderSlotNight,
  };

  /// The preset matching [time] exactly, or null for a custom time.
  static ReminderSlot? forTime(TimeOfDay? time) {
    if (time == null) return null;
    for (final slot in values) {
      if (slot.time == time) return slot;
    }
    return null;
  }
}
