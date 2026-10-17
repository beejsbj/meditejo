import 'package:flutter/foundation.dart';
import 'package:medito/models/pack/pack_model.dart';

/// A teacher as a screen shows them: a row, an avatar or a page header.
@immutable
class DsTeacherItem {
  const DsTeacherItem({
    required this.id,
    required this.name,
    this.photoUrl = '',
    this.bio = '',
    this.website = '',
    this.pageUrl = '',
    this.talkCount = 0,
    this.retreatCount = 0,
  });

  /// The app ID, `ds-teacher-<id>`.
  final String id;
  final String name;
  final String photoUrl;
  final String bio;
  final String website;
  final String pageUrl;
  final int talkCount;
  final int retreatCount;
}

/// What the Explore tab shows for one content group (or both when null).
/// Courses are retreats; talks are singles, as session rows.
@immutable
class DsExplore {
  const DsExplore({
    this.saved = const [],
    this.courses = const [],
    this.teachers = const [],
    this.talks = const [],
    this.savedTeachers = const [],
    this.hasCatalogue = false,
  });

  final List<PackItemsModel> saved;
  final List<PackItemsModel> courses;
  final List<DsTeacherItem> teachers;
  final List<DsTeacherItem> savedTeachers;
  final List<PackItemsModel> talks;

  /// Whether any retreat is stored yet. False on a first launch before the
  /// first sync pass has brought courses in.
  final bool hasCatalogue;

  bool get isEmpty =>
      saved.isEmpty && courses.isEmpty && teachers.isEmpty && talks.isEmpty;
}

/// Grouped search results: teachers first, then courses, then talks.
@immutable
class DsSearchResults {
  const DsSearchResults({
    this.teachers = const [],
    this.courses = const [],
    this.talks = const [],
  });

  final List<DsTeacherItem> teachers;
  final List<PackItemsModel> courses;
  final List<PackItemsModel> talks;

  bool get isEmpty => teachers.isEmpty && courses.isEmpty && talks.isEmpty;
}

/// A teacher's page: who they are, their courses, and a first page of talks.
@immutable
class DsTeacherPage {
  const DsTeacherPage({
    required this.teacher,
    this.courses = const [],
    this.talks = const [],
    this.hasMoreTalks = false,
  });

  final DsTeacherItem teacher;
  final List<PackItemsModel> courses;
  final List<PackItemsModel> talks;
  final bool hasMoreTalks;
}
