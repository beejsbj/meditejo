import 'package:flutter/foundation.dart';
import 'package:medito/services/library/library_models.dart';

/// The shape of what a pasted link, a picked folder or some files turned out
/// to be. The shape decides what Add offers first, and what else it allows.
enum ImportShape {
  /// An RSS or Atom feed, or a page or Apple Podcasts link that leads to one.
  feed,

  /// A YouTube playlist link.
  youtubePlaylist,

  /// A YouTube watch link that also carries a playlist (`watch?v=…&list=…`).
  youtubeWatchWithPlaylist,

  /// A YouTube watch link with no playlist.
  youtubeVideo,

  /// A Dharma Seed retreat page.
  dharmaSeedRetreat,

  /// A Dharma Seed talk page.
  dharmaSeedTalk,

  /// A direct link to one audio file.
  audioUrl,

  /// A folder of audio, with its subfolders.
  localFolder,

  /// Several audio files picked or shared together.
  localFiles,

  /// One audio file.
  localFile,
}

@immutable
class ImportDefault {
  const ImportDefault(this.kind, this.allowed);

  /// What it is added as unless the user changes it.
  final LibraryKind kind;

  /// What the user may choose between; one kind means no choice.
  final Set<LibraryKind> allowed;
}

const _courseOrSingle = {LibraryKind.course, LibraryKind.single};

/// The one table of defaults (BRIEF decision 18): anything that is a list
/// arrives whole, as a Course; one recording stays a Single. Where both are
/// offered, Single means picking one episode from the list, not a different
/// way to import the whole of it.
///
/// A Dharma Seed teacher is not here on purpose. It is a person to follow
/// (`LibraryKind.teacher`), not a list to play.
const importDefaults = <ImportShape, ImportDefault>{
  ImportShape.feed: ImportDefault(LibraryKind.course, _courseOrSingle),
  ImportShape.youtubePlaylist: ImportDefault(
    LibraryKind.course,
    _courseOrSingle,
  ),
  ImportShape.youtubeWatchWithPlaylist: ImportDefault(
    LibraryKind.course,
    _courseOrSingle,
  ),
  ImportShape.youtubeVideo: ImportDefault(LibraryKind.single, _courseOrSingle),
  ImportShape.dharmaSeedRetreat: ImportDefault(LibraryKind.course, {
    LibraryKind.course,
  }),
  ImportShape.dharmaSeedTalk: ImportDefault(LibraryKind.single, {
    LibraryKind.single,
  }),
  ImportShape.audioUrl: ImportDefault(LibraryKind.single, {LibraryKind.single}),
  ImportShape.localFolder: ImportDefault(LibraryKind.course, _courseOrSingle),
  ImportShape.localFiles: ImportDefault(LibraryKind.course, _courseOrSingle),
  ImportShape.localFile: ImportDefault(LibraryKind.single, {
    LibraryKind.single,
  }),
};

extension ImportShapeDefaults on ImportShape {
  LibraryKind get defaultKind => importDefaults[this]!.kind;
  Set<LibraryKind> get allowedKinds => importDefaults[this]!.allowed;
}
