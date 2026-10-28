import 'package:drift/drift.dart' show Variable;
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/services/categories/entry_labels.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';

/// What a category page lists: the user's own library first, then Dharma
/// Seed, each split into Practice and Talks (decision 11).
class CategoryListing {
  const CategoryListing({
    required this.category,
    this.libraryPractice = const [],
    this.libraryTalks = const [],
    this.courses = const [],
    this.practiceSessions = const [],
    this.talkSessions = const [],
  });

  final PracticeCategory category;

  /// Entries in the library with this category, whatever their source.
  final List<LibraryEntry> libraryPractice;
  final List<LibraryEntry> libraryTalks;

  /// Dharma Seed retreats not yet in the library. A retreat is Practice.
  final List<PackItemsModel> courses;

  /// Dharma Seed sessions not yet in the library, by their recording type.
  final List<PackItemsModel> practiceSessions;
  final List<PackItemsModel> talkSessions;

  bool get hasPractice =>
      libraryPractice.isNotEmpty ||
      courses.isNotEmpty ||
      practiceSessions.isNotEmpty;

  bool get hasTalks => libraryTalks.isNotEmpty || talkSessions.isNotEmpty;

  bool get isEmpty => !hasPractice && !hasTalks;
}

/// Reads and edits categories and labels. Everything is on the device: the
/// curated mapping is an asset, the guesses are computed here from the title
/// and description, and the user's labels live in the library database.
class CategoryService {
  CategoryService({
    required this.catalogue,
    required this.library,
    this.dharmaSeed,
  });

  final CategoryCatalogue catalogue;
  final LibraryStore library;
  final DharmaSeedDatabase? dharmaSeed;

  /// How many guessed courses (the model pass's and the keyword rules',
  /// newest first) and keyword-matched sessions a page lists. Hand-picked
  /// ones are always listed; this bounds the long tail.
  static const guessCourseLimit = 50;
  static const ruleSessionLimit = 30;

  // ---------------------------------------------------------------- labels

  /// What the app itself thinks [sourceId] is about. Dharma Seed items are
  /// read from the on-device catalogue (title and description); anything
  /// else is read from the [title] it is shown with, so a library entry and
  /// its own page always agree.
  Future<List<CategoryAssignment>> automatic(
    String sourceId, {
    String title = '',
    Map<String, List<CategoryAssignment>>? memo,
  }) async {
    final cache = memo ?? {};
    final cached = cache[sourceId];
    if (cached != null) return cached;
    final result = await _automatic(sourceId, title, cache);
    return cache[sourceId] = result;
  }

  Future<List<CategoryAssignment>> _automatic(
    String sourceId,
    String title,
    Map<String, List<CategoryAssignment>> memo,
  ) async {
    final db = dharmaSeed;
    final retreatId = parseDsRetreatId(sourceId);
    final talkId = parseDsTalkId(sourceId);
    if (db != null && retreatId != null) {
      final retreat = await db.retreatById(retreatId);
      if (retreat != null) {
        return catalogue.classify(
          sourceId,
          title: retreat.name,
          description: retreat.description,
        );
      }
    } else if (db != null && talkId != null) {
      final talk = await db.talkById(talkId);
      if (talk != null) {
        final retreat = talk.retreatId;
        return catalogue.classify(
          sourceId,
          title: talk.title,
          description: talk.description,
          inherited: retreat == null
              ? const []
              : await automatic(dsRetreatId(retreat), memo: memo),
        );
      }
    }
    return catalogue.classify(sourceId, title: title);
  }

  /// The labels of every non-teacher entry in [entries], by content ID.
  Future<Map<String, EntryLabels>> labelsOfEntries(
    Iterable<LibraryEntry> entries,
  ) async {
    final user = await library.userLabels();
    final memo = <String, List<CategoryAssignment>>{};
    final result = <String, EntryLabels>{};
    for (final entry in entries) {
      if (entry.kind == LibraryKind.teacher) continue;
      result[entry.sourceId] = resolveLabels(
        catalogue,
        automatic: await automatic(
          entry.sourceId,
          title: entry.title,
          memo: memo,
        ),
        user: user[entry.sourceId] ?? const UserLabels(),
      );
    }
    return result;
  }

  /// The labels of one thing, in the library or not. The user's own labels
  /// are only ever on library entries, so a stranger shows the guesses.
  Future<EntryLabels> labelsOf(String sourceId, {String title = ''}) async =>
      resolveLabels(
        catalogue,
        automatic: await automatic(sourceId, title: title),
        user: (await library.userLabels())[sourceId] ?? const UserLabels(),
      );

  // ----------------------------------------------------------------- edits

  /// Puts [categoryId] on [sourceId], or takes it off. Putting it on is
  /// remembered even when the app already guessed it, so a later catalogue
  /// refresh cannot lose it; taking off an automatic one is remembered as an
  /// exclusion, and taking off one the user added simply forgets it.
  Future<void> setCategory(
    String sourceId,
    String categoryId, {
    required bool on,
    required EntryLabels current,
    String title = '',
  }) async {
    if (on) {
      await library.addLabel(sourceId, categoryId);
      return;
    }
    final guessed = current.categories.any(
      (c) => c.id == categoryId && c.source != CategorySource.user,
    );
    if (guessed) {
      await library.excludeCategory(sourceId, categoryId);
    } else {
      // The user's own addition, or an excluded one that shows nowhere.
      final automaticNow = await automatic(sourceId, title: title);
      if (automaticNow.any((a) => a.id == categoryId)) {
        await library.excludeCategory(sourceId, categoryId);
      } else {
        await library.clearLabel(sourceId, categoryId);
      }
    }
  }

  /// Adds what the user typed: a curated category when the text names one
  /// ("jhana" is Jhāna), else a label of their own. Returns the category it
  /// became, or null for a plain label or blank text.
  Future<PracticeCategory?> addLabel(String sourceId, String text) async {
    final trimmed = text.trim();
    if (customLabelKey(trimmed).isEmpty) return null;
    final category = catalogue.categoryNamed(trimmed);
    if (category != null) {
      await library.addLabel(sourceId, category.id);
      return category;
    }
    await library.addLabel(sourceId, customLabelKey(trimmed), display: trimmed);
    return null;
  }

  Future<void> removeCustomLabel(String sourceId, String text) =>
      library.clearLabel(sourceId, customLabelKey(text));

  // --------------------------------------------------------------- listing

  /// The categories with something to show: a library entry carries it
  /// (guessed or the user's), or Dharma Seed has a retreat or talk in it.
  /// Browsing offers only these; the labels sheet still offers every one, so
  /// an empty category can be filled.
  Future<Set<String>> nonEmpty({required List<LibraryEntry> entries}) async {
    final found = <String>{
      for (final labels in (await labelsOfEntries(entries)).values)
        for (final c in labels.categories) c.id,
    };
    final db = dharmaSeed;
    if (db == null) return found;
    for (final category in catalogue.categories) {
      if (found.contains(category.id)) continue;
      if (await _dharmaSeedHas(category, db)) found.add(category.id);
    }
    return found;
  }

  Future<bool> _dharmaSeedHas(
    PracticeCategory category,
    DharmaSeedDatabase db,
  ) async {
    final listed = [
      ...catalogue.curatedIn(category.id),
      ...catalogue.modelIn(category.id),
    ];
    final retreats = [for (final id in listed) ?parseDsRetreatId(id)];
    for (final r in await db.retreatsById(retreats)) {
      if (DharmaSeedDatabase.talkIdsOf(r).isNotEmpty) return true;
    }
    for (final id in listed) {
      final talk = parseDsTalkId(id);
      if (talk != null && await db.talkById(talk) != null) return true;
    }
    // The rules: a few index hits, re-checked, are enough to know.
    for (final (table, column) in [
      ('ds_retreats', 'name'),
      ('ds_talks', 'title'),
    ]) {
      final match = _match(category.id, titleColumn: column);
      if (match == null) continue;
      final rows = await db
          .customSelect(
            'SELECT x.id, x.$column AS t, x.description AS d '
            'FROM ${table}_fts f JOIN $table x ON x.id = f.rowid '
            'WHERE ${table}_fts MATCH ? LIMIT 20',
            variables: [Variable.withString(match)],
            readsFrom: {db.dsRetreats, db.dsTalks},
          )
          .get();
      for (final row in rows) {
        final id = row.read<int>('id');
        final result = catalogue.classify(
          table == 'ds_retreats' ? dsRetreatId(id) : dsTalkId(id),
          title: row.read<String>('t'),
          description: row.read<String>('d'),
        );
        if (result.any((a) => a.id == category.id)) return true;
      }
    }
    return false;
  }

  /// Everything the app knows for [categoryId]. Library entries are exact
  /// (their labels, including the user's); Dharma Seed is the curated items
  /// plus what the keyword rules find in the on-device index.
  Future<CategoryListing> listing(
    String categoryId, {
    required List<LibraryEntry> entries,
  }) async {
    final category = catalogue.category(categoryId);
    if (category == null) {
      throw ArgumentError.value(categoryId, 'categoryId', 'Unknown category');
    }
    final labels = await labelsOfEntries(entries);
    final inLibrary = [
      for (final e in entries)
        if (labels[e.sourceId]?.hasCategory(categoryId) ?? false) e,
    ];
    final owned = {for (final e in entries) e.sourceId};
    // Retreats already shown at the top of the page: their sessions are not
    // repeated below.
    final shownRetreats = {
      for (final e in inLibrary) ?parseDsRetreatId(e.sourceId),
    };

    final db = dharmaSeed;
    var courses = <PackItemsModel>[];
    var practice = <PackItemsModel>[];
    var talks = <PackItemsModel>[];
    if (db != null) {
      final found = await _dharmaSeedFor(category, db, owned, shownRetreats);
      courses = found.courses;
      practice = found.practice;
      talks = found.talks;
    }

    return CategoryListing(
      category: category,
      libraryPractice: [
        for (final e in inLibrary)
          if (e.group == LibraryGroup.practice) e,
      ],
      libraryTalks: [
        for (final e in inLibrary)
          if (e.group == LibraryGroup.talks) e,
      ],
      courses: courses,
      practiceSessions: practice,
      talkSessions: talks,
    );
  }

  Future<
    ({
      List<PackItemsModel> courses,
      List<PackItemsModel> practice,
      List<PackItemsModel> talks,
    })
  >
  _dharmaSeedFor(
    PracticeCategory category,
    DharmaSeedDatabase db,
    Set<String> owned,
    Set<int> shownRetreats,
  ) async {
    Future<bool> belongs(String id, String title, String description) async {
      final result = catalogue.classify(
        id,
        title: title,
        description: description,
        inherited: const [],
      );
      return result.any((a) => a.id == category.id);
    }

    // ---- Courses: hand-picked retreats first, then the guesses (the model
    // pass's and what the rules find), newest first.
    Future<List<DsRetreat>> withTalks(Iterable<String> ids) async => [
      for (final r in await db.retreatsById([
        for (final id in ids) ?parseDsRetreatId(id),
      ]))
        if (DharmaSeedDatabase.talkIdsOf(r).isNotEmpty) r,
    ];
    final curatedRows = await withTalks(catalogue.curatedIn(category.id));
    final modelRows = await withTalks(catalogue.modelIn(category.id));
    final ruleRows = <DsRetreat>[];
    final match = _match(category.id, titleColumn: 'name');
    if (match != null) {
      final rows = await db
          .customSelect(
            'SELECT r.* FROM ds_retreats_fts f JOIN ds_retreats r '
            'ON r.id = f.rowid WHERE ds_retreats_fts MATCH ? '
            "AND r.talk_ids != '[]' "
            'ORDER BY r.start_date DESC, r.id DESC LIMIT ?',
            variables: [
              Variable.withString(match),
              Variable.withInt(guessCourseLimit * 3),
            ],
            readsFrom: {db.dsRetreats},
          )
          .get();
      for (final row in rows) {
        final retreat = db.dsRetreats.map(row.data);
        // The index is looser than the rules (and knows nothing of curated
        // exclusions), so the rules decide.
        if (await belongs(
          dsRetreatId(retreat.id),
          retreat.name,
          retreat.description,
        )) {
          ruleRows.add(retreat);
        }
        if (ruleRows.length >= guessCourseLimit) break;
      }
    }
    final seen = <int>{for (final r in curatedRows) r.id};
    final guessed =
        [
          for (final r in [...modelRows, ...ruleRows])
            if (seen.add(r.id)) r,
        ]..sort((a, b) {
          final byDate = b.startDate.compareTo(a.startDate);
          return byDate != 0 ? byDate : b.id.compareTo(a.id);
        });
    final found = [...curatedRows, ...guessed.take(guessCourseLimit)];
    final retreats = [
      for (final r in found)
        if (!owned.contains(dsRetreatId(r.id))) r,
    ];
    final leads = await db.leadTeacherOfRetreats([
      for (final r in retreats) r.id,
    ]);
    final leadTeachers = await db.teachersById(leads.values);
    final courses = [
      for (final r in retreats)
        DharmaSeedSource.retreatItem(r, leadTeachers[leads[r.id]]),
    ];

    // ---- Sessions: curated talks, then keyword hits, Practice kinds apart.
    // Covered by a course on this page, whether it is the library's or the
    // catalogue's.
    final listedRetreats = {...shownRetreats, for (final r in retreats) r.id};
    final curatedTalkIds = [
      for (final id in catalogue.curatedIn(category.id)) ?parseDsTalkId(id),
    ];
    final talkRows = <DsTalk>[];
    final talkSeen = <int>{};
    bool addTalk(DsTalk t) {
      if (!talkSeen.add(t.id)) return false;
      if (owned.contains(dsTalkId(t.id))) return false;
      // A session already covered by a course on this page is not repeated.
      if (t.retreatId != null && listedRetreats.contains(t.retreatId)) {
        return false;
      }
      talkRows.add(t);
      return true;
    }

    for (final id in curatedTalkIds) {
      final talk = await db.talkById(id);
      if (talk != null) addTalk(talk);
    }
    final talkMatch = _match(category.id, titleColumn: 'title');
    if (talkMatch != null) {
      for (final group in DsContentGroup.values) {
        final rows = await db
            .customSelect(
              'SELECT t.* FROM ds_talks_fts f JOIN ds_talks t ON t.id = f.rowid '
              'WHERE ds_talks_fts MATCH ? AND '
              '${DharmaSeedDatabase.groupCondition(group, 't')} '
              'ORDER BY t.rec_date DESC, t.id DESC LIMIT ?',
              variables: [
                Variable.withString(talkMatch),
                Variable.withInt(ruleSessionLimit * 3),
              ],
              readsFrom: {db.dsTalks},
            )
            .get();
        var kept = 0;
        for (final row in rows) {
          final talk = db.dsTalks.map(row.data);
          if (kept >= ruleSessionLimit) break;
          if (!await belongs(dsTalkId(talk.id), talk.title, talk.description)) {
            continue;
          }
          if (addTalk(talk)) kept++;
        }
      }
    }

    final teachers = await db.teachersById(
      talkRows.map((t) => t.teacherId).nonNulls,
    );
    final items = [
      for (final talk in talkRows)
        (
          talk: talk,
          item: DharmaSeedSource.talkItem(
            DsTalkWithTeacher(talk, teachers[talk.teacherId]),
          ),
        ),
    ];
    bool isPractice(DsTalk t) =>
        DharmaSeedKind.fromRecordingType(t.recordingType).isPractice;
    return (
      courses: courses,
      practice: [
        for (final x in items)
          if (isPractice(x.talk)) x.item,
      ],
      talks: [
        for (final x in items)
          if (!isPractice(x.talk)) x.item,
      ],
    );
  }

  /// An FTS5 expression for the keyword rules of [categoryId]: the title
  /// terms in [titleColumn] and the description terms in `description`.
  /// Null when the category has no rules.
  String? _match(String categoryId, {required String titleColumn}) {
    final titles = <String>{};
    final descriptions = <String>{};
    for (final rule in catalogue.rulesFor(categoryId)) {
      titles.addAll(rule.title.map((t) => t.ftsPhrase));
      descriptions.addAll(rule.description.map((t) => t.ftsPhrase));
    }
    final parts = [
      if (titles.isNotEmpty) '$titleColumn : (${titles.join(' OR ')})',
      if (descriptions.isNotEmpty)
        'description : (${descriptions.join(' OR ')})',
    ];
    return parts.isEmpty ? null : parts.map((p) => '($p)').join(' OR ');
  }
}
