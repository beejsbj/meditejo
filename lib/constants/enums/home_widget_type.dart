/// The sections of Home the user can switch on or off and reorder.
///
/// Names are saved, so renaming one drops it from a saved layout: [upNext]
/// keeps its old name for what is now the Continue section. Sections saved
/// by earlier versions (carousel, quote) no longer exist and are ignored.
/// Shortcuts (Timer, Sounds) became part of [pinned], whose first tile is
/// the Timer: see [legacyShortcuts].
enum HomeWidgetType {
  upNext, // Continue: what is in progress, one tap to resume
  pinned; // The Timer, then pinned presets, courses and sessions

  /// What the Shortcuts section was saved as ("quickLinks" before that). In
  /// a saved order Pinned takes its place, since the Timer now leads Pinned;
  /// a saved "hidden" mark on it is dropped, so it never hides the pins.
  static const legacyShortcuts = {'homeShortcuts', 'quickLinks'};

  static HomeWidgetType? tryParse(String value) {
    for (final type in values) {
      if (type.name == value) return type;
    }
    return null;
  }
}
