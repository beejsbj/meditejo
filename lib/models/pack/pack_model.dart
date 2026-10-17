import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:medito/models/attribution/source_attribution.dart';

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
