import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/constants/types/type_constants.dart';

part 'pack_model.freezed.dart';
part 'pack_model.g.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class PackModel with _$PackModel {
  const factory PackModel({
    required String id,
    required String title,
    String? subtitle,
    String? coverUrl,
    String? path,
    String? description,
    @Default(false) bool isPublished,
    @Default(<PackItemsModel>[]) List<PackItemsModel> items,

    /// The course's lead teacher, for the Teacher section.
    PackTeacher? teacher,

    /// Credit owed where the course is shown; null for unlicensed content.
    SourceAttribution? attribution,
  }) = _PackModel;

  factory PackModel.fromJson(Map<String, dynamic> json) =>
      _$PackModelFromJson(json);
}

@Freezed(makeCollectionsUnmodifiable: false)
abstract class PackItemsModel with _$PackItemsModel {
  const factory PackItemsModel({
    required String type,
    required String id,
    required String title,
    String? subtitle,
    String? coverUrl,
    required String path,
    bool? isCompleted,

    /// Session details a course page shows beyond title and subtitle. All
    /// optional: sources without them get the plain row.
    String? kind,
    String? teacher,
    int? durationMs,

    /// Recording date as `yyyy-MM-dd`, for grouping a long course by day.
    String? date,

    /// The heading this session sits under ("Day 1"), in a course whose
    /// maker grouped it. Consecutive items with the same section form a group.
    String? section,

    /// True when the session's source no longer has it (a removed video, a
    /// withdrawn talk). The row stays, greyed, and is skipped when playing.
    bool? unavailable,
  }) = _PackItemsModel;

  factory PackItemsModel.fromJson(Map<String, dynamic> json) =>
      _$PackItemsModelFromJson(json);
}

/// Who leads a course: name, bio and photo, with a link to their own page.
@Freezed(makeCollectionsUnmodifiable: false)
abstract class PackTeacher with _$PackTeacher {
  const factory PackTeacher({
    /// The app ID of the teacher, e.g. `ds-teacher-210`.
    required String id,
    required String name,
    @Default('') String bio,
    @Default('') String photoUrl,
    @Default('') String pageUrl,
  }) = _PackTeacher;

  factory PackTeacher.fromJson(Map<String, dynamic> json) =>
      _$PackTeacherFromJson(json);
}

extension PackPlayableTracks on PackModel {
  /// The sessions that can be played, in order: not sub-packs or links, and
  /// not sessions a personal course lists whose source has lost them.
  /// Progress ("3 of 7") and the play button count these.
  List<PackItemsModel> get playableTracks => [
    for (final item in items)
      if (item.type == TypeConstants.track && item.unavailable != true) item,
  ];
}
