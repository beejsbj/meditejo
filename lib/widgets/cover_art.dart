import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/services/categories/entry_labels.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/art/engine/compose.dart';

/// The art a cover stands for, keyed by **id** (never title) so an item keeps
/// its art when it's renamed, and shows the same art wherever it appears.

/// A course, or a playlist when [id] is one the user made. [practice], when
/// the item carries one with its own figure variants, widens what its
/// generated art may draw.
ArtSubject courseArt(String id, {String? practice}) => ArtSubject.cover(
  isMyCourseId(id) ? ArtCoverKind.playlist : ArtCoverKind.course,
  id,
  practice: practice,
);

ArtSubject singleArt(String id, {String? practice}) =>
    ArtSubject.cover(ArtCoverKind.single, id, practice: practice);

ArtSubject teacherArt(String id) => ArtSubject.cover(ArtCoverKind.teacher, id);

/// The art of a library entry (or an import preview) of [kind] stored as [id].
ArtSubject libraryArt(LibraryKind kind, String id, {String? practice}) =>
    switch (kind) {
      LibraryKind.course => courseArt(id, practice: practice),
      LibraryKind.single => singleArt(id, practice: practice),
      LibraryKind.teacher => teacherArt(id),
    };

/// The first practice in [labels] that has figure variants of its own
/// (`ArtMap.practiceLibrary`: Noting, the Headless Way, Trāṭaka), or null.
String? artPractice(EntryLabels? labels) {
  for (final c in labels?.categories ?? const <CategoryAssignment>[]) {
    if (ArtMap.practiceLibrary.containsKey(c.id)) return c.id;
  }
  return null;
}

/// The cover URL worth drawing for [art]; empty when the art should show
/// instead. The cover rule, in one place:
///
/// 1. Curated art for a shipped id wins over any picture, so a starter
///    YouTube course shows its curated card, not its thumbnail.
/// 2. Otherwise a real cover wins (a YouTube thumbnail, a feed's artwork).
/// 3. Otherwise the art is generated from the id.
///
/// A teacher's own photo wins only for teachers, so Dharma Seed courses and
/// talks drop theirs (library entries stored before that carry it).
String shownCoverUrl(ArtSubject? art, String url) {
  if (art is! CoverArt || art.kind == ArtCoverKind.teacher) return url;
  if (hasCuratedCover(art.id)) return '';
  return dsCoverUrl(art.id, url);
}

/// Whether [id] ships with a curated card (once the curated file is in).
bool hasCuratedCover(String id) {
  final entry = CuratedArt.instance.entry(id);
  return entry != null && entry['kind'] != 'bell';
}
