import 'package:medito/models/catalogue/catalogue_models.dart';

/// Alternates between [lists] (first of each, second of each, …), so no one
/// source fills a merged list before another shows. Each list keeps its own
/// order, and an item whose [key] was already taken is dropped.
List<T> interleave<T>(Iterable<List<T>> lists, {Object? Function(T)? key}) {
  final source = [for (final list in lists) list];
  final seen = <Object?>{};
  final merged = <T>[];
  for (var i = 0; source.any((list) => i < list.length); i++) {
    for (final list in source) {
      if (i >= list.length) continue;
      final item = list[i];
      if (key == null || seen.add(key(item))) merged.add(item);
    }
  }
  return merged;
}

/// Explore from several catalogues as one: courses and sessions alternate
/// between sources, teachers rank by how much they have recorded, and the
/// teachers the user follows stay in front.
CatalogueExplore mergeExplores(List<CatalogueExplore> parts) {
  if (parts.length == 1) return parts.single;
  final teachers = [for (final part in parts) ...part.teachers]
    ..sort((a, b) => b.talkCount.compareTo(a.talkCount));
  return CatalogueExplore(
    courses: interleave([for (final part in parts) part.courses]),
    savedTeachers: [for (final part in parts) ...part.savedTeachers],
    teachers: teachers,
    talks: interleave([for (final part in parts) part.talks]),
    archives: [for (final part in parts) ...part.archives],
    hasCatalogue: parts.any((part) => part.hasCatalogue),
  );
}

/// Search results from several catalogues as one, in the order of
/// [mergeExplores].
CatalogueSearchResults mergeSearches(List<CatalogueSearchResults> parts) {
  if (parts.length == 1) return parts.single;
  return CatalogueSearchResults(
    teachers: interleave([for (final part in parts) part.teachers]),
    courses: interleave([for (final part in parts) part.courses]),
    talks: interleave([for (final part in parts) part.talks]),
  );
}
