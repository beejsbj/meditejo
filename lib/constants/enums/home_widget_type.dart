/// The sections of Home the user can switch on or off and reorder.
///
/// Names are saved, so renaming one drops it from a saved layout: [upNext]
/// keeps its old name for what is now the Continue section, and
/// [homeShortcuts] answers to its old saved name too (see [tryParse]).
/// Sections saved by earlier versions (shortcuts, carousel, quote) no longer
/// exist and are ignored.
enum HomeWidgetType {
  upNext, // Continue: what is in progress, one tap to resume
  homeShortcuts, // Timer, Sounds, presets, Add
  pinned; // Up to three pinned courses

  /// What [homeShortcuts] was saved as before it lost its "quick links" name.
  static const _legacyShortcuts = 'quickLinks';

  static HomeWidgetType? tryParse(String value) {
    if (value == _legacyShortcuts) return homeShortcuts;
    for (final type in values) {
      if (type.name == value) return type;
    }
    return null;
  }
}
