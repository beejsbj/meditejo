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
/// Courses are retreats; talks are singles, as session rows. Courses the user
/// has added to the library are left out: the library lists them itself.
@immutable
class CatalogueExplore {
  const CatalogueExplore({
    this.courses = const [],
    this.teachers = const [],
    this.talks = const [],
    this.savedTeachers = const [],
    this.archives = const [],
    this.hasCatalogue = false,
  });

  final List<PackItemsModel> courses;
  final List<CatalogueTeacher> teachers;
  final List<CatalogueTeacher> savedTeachers;
  final List<PackItemsModel> talks;

  /// Lists to browse by, such as a source's talks year by year; each opens as
  /// a course page but cannot be kept.
  final List<PackItemsModel> archives;

  /// Whether any retreat is stored yet. False on a first launch before the
  /// first sync pass has brought courses in.
  final bool hasCatalogue;

  bool get isEmpty =>
      courses.isEmpty &&
      teachers.isEmpty &&
      savedTeachers.isEmpty &&
      talks.isEmpty &&
      archives.isEmpty;
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

/// A teacher's page: who they are, their courses, and a first page of talks.
@immutable
class CatalogueTeacherPage {
  const CatalogueTeacherPage({
    required this.teacher,
    this.courses = const [],
    this.talks = const [],
    this.hasMoreTalks = false,
  });

  final CatalogueTeacher teacher;
  final List<PackItemsModel> courses;
  final List<PackItemsModel> talks;
  final bool hasMoreTalks;
}
