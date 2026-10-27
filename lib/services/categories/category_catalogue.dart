import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:medito/services/categories/category_text.dart';

/// Where the app keeps the curated mapping. It is a versioned asset so the
/// list can grow without touching code; `test/services/categories` checks it
/// against the bundled Dharma Seed catalogue.
const categoriesAsset = 'assets/categories/categories.json';

/// The newest asset layout this build reads.
const categoriesFormat = 1;

/// Why an item has a category. Higher outranks lower: the user's own choice,
/// then the curated mapping, then the keyword rules.
enum CategorySource {
  rule,
  curated,
  user;

  bool outranks(CategorySource other) => index > other.index;
}

/// One browse category: a practice or method the user can find and filter by.
@immutable
class PracticeCategory {
  const PracticeCategory({
    required this.id,
    required this.name,
    this.blurb = '',
    this.aliases = const [],
  });

  /// Stable slug, stored in the user's labels (`metta`, `open-awareness`).
  final String id;

  /// What the screens show. Practice terms are not translated.
  final String name;

  /// One line saying what the category gathers.
  final String blurb;

  /// Other names a user might type for it ("Insight" for Vipassanā).
  final List<String> aliases;
}

/// A category an item carries, and the reason.
@immutable
class CategoryAssignment {
  const CategoryAssignment(this.id, this.source);

  final String id;
  final CategorySource source;

  @override
  bool operator ==(Object other) =>
      other is CategoryAssignment && other.id == id && other.source == source;

  @override
  int get hashCode => Object.hash(id, source);

  @override
  String toString() => '$id (${source.name})';
}

/// Keyword rules for one category: words to look for in titles, and a
/// stricter list for descriptions (which mention everything in passing).
class CategoryRule {
  CategoryRule({
    required this.category,
    required this.title,
    required this.description,
  });

  final String category;
  final List<CategoryTerm> title;
  final List<CategoryTerm> description;

  bool matches(List<String> titleWords, List<String> descriptionWords) =>
      title.any((t) => t.matches(titleWords)) ||
      description.any((t) => t.matches(descriptionWords));
}

/// The curated mapping, and the arithmetic of applying it.
///
/// Precedence for one item: a curated entry (even an empty one, which says
/// "none of the keyword guesses apply") replaces the rules; otherwise the
/// rules run over the title and description, and a talk also takes what its
/// retreat has. The user's own labels sit above all of this and are applied
/// by the library, not here (see `LibraryLabelIndex`).
class CategoryCatalogue {
  CategoryCatalogue._({
    required this.version,
    required this.updated,
    required this.categories,
    required Map<String, List<String>> curated,
    required Map<String, String> curatedNames,
    required this.rules,
  }) : _curated = curated,
       curatedNames = Map.unmodifiable(curatedNames),
       _byId = {for (final c in categories) c.id: c} {
    for (final c in categories) {
      for (final name in [c.id, c.name, ...c.aliases]) {
        _byName[foldWords(name).join(' ')] = c;
      }
    }
  }

  /// Reads the asset's JSON. Throws [FormatException] on a layout this build
  /// does not know or an unknown category in a mapping, so a bad edit fails a
  /// test instead of quietly hiding items.
  factory CategoryCatalogue.parse(String source) {
    final json = jsonDecode(source);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('categories.json is not an object');
    }
    final format = json['format'];
    if (format is! int || format > categoriesFormat) {
      throw FormatException('Unsupported categories format: $format');
    }
    final categories = [
      for (final raw in _list(json['categories']))
        PracticeCategory(
          id: _string(raw, 'id'),
          name: _string(raw, 'name'),
          blurb: raw['blurb'] as String? ?? '',
          aliases: _strings(raw['aliases']),
        ),
    ];
    final ids = {for (final c in categories) c.id};
    if (ids.length != categories.length) {
      throw const FormatException('Duplicate category id');
    }

    void checkKnown(Iterable<String> used, String where) {
      for (final id in used) {
        if (!ids.contains(id)) {
          throw FormatException('Unknown category "$id" in $where');
        }
      }
    }

    final curated = <String, List<String>>{};
    final names = <String, String>{};
    for (final raw in _list(json['curated'])) {
      final id = _string(raw, 'id');
      final used = _strings(raw['categories']);
      checkKnown(used, id);
      if (curated.containsKey(id)) {
        throw FormatException('Duplicate curated item $id');
      }
      curated[id] = used;
      final name = raw['name'];
      if (name is String) names[id] = name;
    }

    final rules = <CategoryRule>[];
    for (final raw in _list(json['rules'])) {
      final category = _string(raw, 'category');
      checkKnown([category], 'a rule');
      List<CategoryTerm> terms(String key) => [
        for (final t in _strings(raw[key])) ?CategoryTerm.parse(t),
      ];
      rules.add(
        CategoryRule(
          category: category,
          title: terms('title'),
          description: terms('description'),
        ),
      );
    }

    return CategoryCatalogue._(
      version: json['version'] as int? ?? 0,
      updated: json['updated'] as String? ?? '',
      categories: List.unmodifiable(categories),
      curated: curated,
      curatedNames: names,
      rules: List.unmodifiable(rules),
    );
  }

  static Future<CategoryCatalogue> load([AssetBundle? bundle]) async =>
      CategoryCatalogue.parse(
        await (bundle ?? rootBundle).loadString(categoriesAsset),
      );

  static List<Map<String, dynamic>> _list(Object? value) =>
      value is List ? value.whereType<Map<String, dynamic>>().toList() : [];

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : [];

  static String _string(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Missing "$key" in ${jsonEncode(map)}');
  }

  /// Bumped by hand whenever the mapping changes, so a release can say which
  /// edition of the curation it carries.
  final int version;

  /// The ISO date of the last edit.
  final String updated;

  /// In the order the screens show them.
  final List<PracticeCategory> categories;

  final List<CategoryRule> rules;

  final Map<String, List<String>> _curated;
  final Map<String, PracticeCategory> _byId;
  final Map<String, PracticeCategory> _byName = {};

  /// Reviewer's names for the curated items, by item ID.
  final Map<String, String> curatedNames;

  /// Every curated item ID (`ds-retreat-4496`, `ds-talk-60864`, …).
  Iterable<String> get curatedIds => _curated.keys;

  PracticeCategory? category(String id) => _byId[id];

  /// The category a user's typed [text] means ("metta", "Jhāna", "insight"),
  /// or null when it is a label of their own.
  PracticeCategory? categoryNamed(String text) =>
      _byName[foldWords(text).join(' ')];

  /// The curated categories of [sourceId], or null when it is not curated.
  /// An empty list means "curated as none".
  List<String>? curatedFor(String sourceId) => _curated[sourceId];

  /// Item IDs curated into [categoryId], in the asset's order.
  List<String> curatedIn(String categoryId) => [
    for (final MapEntry(:key, :value) in _curated.entries)
      if (value.contains(categoryId)) key,
  ];

  /// The rules that name [categoryId].
  List<CategoryRule> rulesFor(String categoryId) => [
    for (final rule in rules)
      if (rule.category == categoryId) rule,
  ];

  /// What the app itself thinks [sourceId] is about, before the user's say.
  ///
  /// [inherited] is what a talk's retreat carries; it only applies when the
  /// talk has no curated entry of its own. Results are in the catalogue's
  /// category order.
  List<CategoryAssignment> classify(
    String sourceId, {
    String title = '',
    String description = '',
    Iterable<CategoryAssignment> inherited = const [],
  }) {
    final curated = _curated[sourceId];
    if (curated != null) {
      return _ordered([
        for (final id in curated)
          CategoryAssignment(id, CategorySource.curated),
      ]);
    }
    final titleWords = foldWords(title);
    final descriptionWords = foldWords(description);
    final found = <String, CategoryAssignment>{
      for (final a in inherited) a.id: a,
    };
    for (final rule in rules) {
      if (found[rule.category]?.source == CategorySource.curated) continue;
      if (rule.matches(titleWords, descriptionWords)) {
        found.putIfAbsent(
          rule.category,
          () => CategoryAssignment(rule.category, CategorySource.rule),
        );
      }
    }
    return _ordered(found.values);
  }

  List<CategoryAssignment> _ordered(Iterable<CategoryAssignment> items) {
    final order = {for (final (i, c) in categories.indexed) c.id: i};
    return items.toList()
      ..sort((a, b) => (order[a.id] ?? 0).compareTo(order[b.id] ?? 0));
  }
}
