import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/widgets/art/art_subject.dart';

/// The art a cover stands for, keyed by **id** (never title) so an item keeps
/// its art when it's renamed, and shows the same art wherever it appears.

/// A course, or a playlist when [id] is one the user made.
ArtSubject courseArt(String id) => ArtSubject.cover(
  isMyCourseId(id) ? ArtCoverKind.playlist : ArtCoverKind.course,
  id,
);

ArtSubject singleArt(String id) => ArtSubject.cover(ArtCoverKind.single, id);

ArtSubject teacherArt(String id) => ArtSubject.cover(ArtCoverKind.teacher, id);

/// The art of a library entry (or an import preview) of [kind] stored as [id].
ArtSubject libraryArt(LibraryKind kind, String id) => switch (kind) {
  LibraryKind.course => courseArt(id),
  LibraryKind.single => singleArt(id),
  LibraryKind.teacher => teacherArt(id),
};

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
