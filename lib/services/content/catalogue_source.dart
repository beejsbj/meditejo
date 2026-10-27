import 'package:flutter/foundation.dart';
import 'package:medito/models/catalogue/catalogue_models.dart';
import 'package:medito/models/explore/session_length.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/library/library_models.dart';

/// A built-in catalogue the Explore tab can browse and search: Dharma Seed,
/// dhammatalks.org, and any source that joins them.
///
/// It is a [ContentSource] (courses, sessions, search rows, saving) plus the
/// reads the Explore, search and teacher screens make. Those reads return the
/// source-neutral view models in `catalogue_models.dart`, so the screens ask
/// every catalogue the same questions and merge the answers.
///
/// Rules for implementers, beyond [ContentSource]'s:
/// - Reads never throw for lack of a network: they answer from what is on the
///   device (a bundle, a cache) or with empty results.
/// - [catchUp] is the only call that may use the network to refresh the
///   catalogue, and it runs when the user opens Explore, never at startup.
/// - Each item carries its own [SourceAttribution] where one is shown, with
///   the licence link the source's terms ask for.
abstract interface class CatalogueSource implements ContentSource {
  /// The name the source filter shows ("Dharma Seed").
  String get name;

  /// Whether [id] names one of this source's teachers (`ds-teacher-…`).
  bool ownsTeacher(String id);

  /// Changes whenever a refresh lands records, so a screen that watches it
  /// re-reads.
  ValueListenable<int> get revision;

  /// The Explore tab's browse content for one group, or both when [group] is
  /// null: courses, teachers and the latest sessions.
  Future<CatalogueExplore> explore({ContentGroup? group});

  /// Grouped search: teachers, courses, talks. Only talks honour [length].
  Future<CatalogueSearchResults> search(String query, {SessionLength? length});

  /// A teacher's page, or `CatalogueEntryUnavailable` when unknown.
  Future<CatalogueTeacherPage> teacherPage(String id, {int talkPage = 30});

  /// More of a teacher's talks, after the [offset] already shown.
  Future<List<PackItemsModel>> teacherTalks(
    String id, {
    required int offset,
    int limit = 30,
  });

  /// How the library describes one of this source's courses, sessions or
  /// teachers, or null when it does not hold [id]. It is what Add to library
  /// and a pasted link store.
  Future<LibraryDraft?> libraryDraft(String id);

  /// Fetches what changed since the bundled snapshot (or the last time). Cheap
  /// when nothing has, and quiet when offline. [force] ignores the
  /// source's own "not due yet" rule (pull to refresh).
  Future<void> catchUp({bool force = false});
}
