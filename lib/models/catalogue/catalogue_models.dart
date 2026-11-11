import 'package:flutter/foundation.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/pack/pack_model.dart';

/// What the Explore screens show, whichever built-in catalogue it came from
/// (`CatalogueSource`). The two content groups of the Explore chips: Practice
/// is what you do along with the audio; Talks is everything you listen to,
/// including `Other` and recordings with no type.
enum ContentGroup { practice, talks }

/// A teacher as a screen shows them: a row, an avatar or a page header.
@immutable
class CatalogueTeacher {
  const CatalogueTeacher({
    required this.id,
    required this.name,
    this.photoUrl = '',
    this.bio = '',
    this.website = '',
    this.pageUrl = '',
    this.talkCount = 0,
    this.retreatCount = 0,
    this.attribution,
  });

  /// The app ID, `ds-teacher-<id>`, `dt-teacher-thanissaro`.
  final String id;
  final String name;
  final String photoUrl;
  final String bio;
  final String website;
  final String pageUrl;
  final int talkCount;
  final int retreatCount;

  /// What the teacher's page credits and links (source, licence).
  final SourceAttribution? attribution;
}

/// What the Explore tab shows for one content group (or both when null).
/// Courses are retreats; talks are singles, as session rows. What the user
/// has added to the library keeps its place: Explore is not tied to the
/// library, and a card shows its saved state.
@immutable
class CatalogueExplore {
  const CatalogueExplore({
    this.courses = const [],
    this.teachers = const [],
    this.talks = const [],
    this.hasCatalogue = false,
  });

  final List<PackItemsModel> courses;
  final List<CatalogueTeacher> teachers;
  final List<PackItemsModel> talks;

  /// Whether any retreat is stored yet. False on a first launch before the
  /// first sync pass has brought courses in.
  final bool hasCatalogue;

  bool get isEmpty => courses.isEmpty && teachers.isEmpty && talks.isEmpty;
}

/// Grouped search results: teachers first, then courses, then talks.
@immutable
class CatalogueSearchResults {
  const CatalogueSearchResults({
    this.teachers = const [],
    this.courses = const [],
    this.talks = const [],
  });

  final List<CatalogueTeacher> teachers;
  final List<PackItemsModel> courses;
  final List<PackItemsModel> talks;

  bool get isEmpty => teachers.isEmpty && courses.isEmpty && talks.isEmpty;
}

/// A teacher's page: who they are, their courses, a first page of talks and,
/// for a source with a large archive, the archive.
@immutable
class CatalogueTeacherPage {
  const CatalogueTeacherPage({
    required this.teacher,
    this.courses = const [],
    this.talks = const [],
    this.hasMoreTalks = false,
    this.archive = const [],
  });

  final CatalogueTeacher teacher;
  final List<PackItemsModel> courses;
  final List<PackItemsModel> talks;
  final bool hasMoreTalks;

  /// The teacher's whole archive, as sections (evening, morning) of groups
  /// (years). The page lists the groups closed; a group's talks are read only
  /// when it is opened ([CatalogueSource.archiveTalks]). Empty when the source
  /// has none, in which case [talks] pages through everything.
  final List<CatalogueArchiveSection> archive;
}

/// One way of cutting an archive, such as the evening talks, as years.
@immutable
class CatalogueArchiveSection {
  const CatalogueArchiveSection({required this.title, required this.groups});

  final String title;

  /// Newest first.
  final List<CatalogueArchiveGroup> groups;
}

/// A closed group of an archive: one year of one section.
@immutable
class CatalogueArchiveGroup {
  const CatalogueArchiveGroup({
    required this.id,
    required this.title,
    required this.talkCount,
  });

  /// What [CatalogueSource.archiveTalks] reads it by.
  final String id;
  final String title;
  final int talkCount;
}
