import 'package:medito/services/library/library_models.dart';

/// One thing that is already in the library on a fresh install.
class StarterItem {
  const StarterItem({
    required this.id,
    required this.kind,
    required this.title,
    this.itemCount = 1,
    this.group,
  });

  /// The content ID, for the source that owns it (`ds-retreat-4496`).
  final String id;
  final LibraryKind kind;

  /// Used only when the source cannot describe the item offline.
  final String title;
  final int itemCount;

  /// Practice or Talks. Null follows the source's own label for the item.
  final LibraryGroup? group;
}

/// Burooj's built-in starter set (docs/fork/BRIEF.md, decision 13), in the
/// order it should lead the library. Seeded once, on the first run with an
/// empty library; see `seedStarterSet`.
const starterSet = <StarterItem>[
  StarterItem(
    id: 'ds-retreat-4496',
    kind: LibraryKind.course,
    title: 'Practising the Jhānas',
    itemCount: 32,
    group: LibraryGroup.practice,
  ),
  StarterItem(
    id: 'ds-retreat-1084',
    kind: LibraryKind.course,
    title: 'The Loving Kindness (Metta) Retreat',
    itemCount: 10,
    group: LibraryGroup.practice,
  ),
  StarterItem(
    id: 'ds-retreat-1183',
    kind: LibraryKind.course,
    title: 'The Art Of Concentration (Samatha Meditation)',
    itemCount: 9,
    group: LibraryGroup.practice,
  ),
  StarterItem(
    id: 'ds-retreat-1308',
    kind: LibraryKind.course,
    title: 'Samatha Meditation',
    itemCount: 7,
    group: LibraryGroup.practice,
  ),
  // Follows Dharma Seed's own label for the recording.
  StarterItem(
    id: 'ds-talk-60864',
    kind: LibraryKind.single,
    title: 'Developing Piti, Developing Focus, Developing Wellbeing',
  ),
  // TODO(youtube): the YouTube slice appends its two playlists here once the
  // `yt-` source exists, using its playlist ID scheme, as courses. Until then
  // an ID no source can open would only be a dead row.
  //   Meditating with John Vervaeke (John Vervaeke's Lectern)
  //     https://www.youtube.com/playlist?list=PLND1JCRq8VujAHvDA482SXF1cJTQrwlx3
  //   Qualia Mastery: Building Your Toolkit for Navigating the State-Space of
  //   Consciousness (Qualia Research Institute)
  //     https://www.youtube.com/playlist?list=PLbmYHvGI-YSvnpbh3ppQqcG72lpw4aQdE
];
