/// A cue sound that is a bell the user made carries this prefix; the rest of
/// the id is a token that never changes, so renaming a bell keeps every cue
/// that rings it. Bundled bells are their asset paths.
const customBellPrefix = 'custom-bell:';

final _customBellId = RegExp(r'^custom-bell:[a-z0-9]{6,32}$');

/// Whether [sound] is the id of a bell the user made (well formed, whether or
/// not it still exists).
bool isCustomBellId(String sound) => _customBellId.hasMatch(sound);
