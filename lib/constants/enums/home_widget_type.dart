/// The sections of Home the user can switch on or off and reorder.
///
/// Names are saved, so renaming one drops it from a saved layout: [upNext]
/// keeps its old name for what is now the Continue section. Sections saved by
/// earlier versions (shortcuts, carousel, quote) no longer exist and are
/// ignored.
enum HomeWidgetType {
  upNext, // Continue: what is in progress, one tap to resume
  quickLinks, // Timer, Sounds, Add
  pinned; // Up to three pinned courses

  static HomeWidgetType? tryParse(String value) {
    for (final type in values) {
      if (type.name == value) return type;
    }
    return null;
  }
}
