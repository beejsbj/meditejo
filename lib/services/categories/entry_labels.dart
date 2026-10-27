import 'package:flutter/foundation.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/services/categories/category_text.dart';

/// The key a label of the user's own is stored under: its folded words.
/// "Retreat prep" and "retreat  prep!" are one label.
String customLabelKey(String text) => foldWords(text).join('-');

/// What the user has said about one entry, as stored.
@immutable
class UserLabels {
  const UserLabels({this.added = const {}, this.excluded = const {}});

  /// Label key to the text the user typed (empty for a curated category).
  final Map<String, String> added;

  /// Automatic categories the user took off this entry.
  final Set<String> excluded;

  bool get isEmpty => added.isEmpty && excluded.isEmpty;
}

/// An entry's labels as the screens read them: its categories, each with the
/// reason it has them, and the user's own labels.
@immutable
class EntryLabels {
  const EntryLabels({this.categories = const [], this.custom = const []});

  static const none = EntryLabels();

  /// In the catalogue's order.
  final List<CategoryAssignment> categories;

  /// The user's own labels, as they typed them, alphabetical.
  final List<String> custom;

  bool get isEmpty => categories.isEmpty && custom.isEmpty;

  bool hasCategory(String id) => categories.any((c) => c.id == id);

  /// Whether the user, not the app, put [id] on this entry.
  bool userChose(String id) => categories.any(
    (c) => c.id == id && c.source == CategorySource.user,
  );

  /// Whether [key] is one of this entry's categories (by ID) or labels of the
  /// user's own (by [customLabelKey]); what a Library label chip filters on.
  bool hasLabel(String key) =>
      hasCategory(key) || custom.any((c) => customLabelKey(c) == key);

  bool hasCustom(String text) {
    final key = customLabelKey(text);
    return custom.any((c) => customLabelKey(c) == key);
  }
}

/// Combines what the app guessed with what the user said. The user wins:
/// an exclusion removes an automatic category, an added one stays whatever
/// the catalogue says, and neither depends on the catalogue edition, so a
/// refreshed catalogue changes only the guesses.
EntryLabels resolveLabels(
  CategoryCatalogue catalogue, {
  Iterable<CategoryAssignment> automatic = const [],
  UserLabels user = const UserLabels(),
}) {
  final categories = <String, CategoryAssignment>{
    for (final a in automatic)
      if (!user.excluded.contains(a.id)) a.id: a,
  };
  final custom = <String>[];
  for (final MapEntry(:key, :value) in user.added.entries) {
    if (catalogue.category(key) != null) {
      categories[key] = CategoryAssignment(key, CategorySource.user);
    } else {
      custom.add(value.isEmpty ? key : value);
    }
  }
  final order = {
    for (final (i, c) in catalogue.categories.indexed) c.id: i,
  };
  return EntryLabels(
    categories: categories.values.toList()
      ..sort((a, b) => (order[a.id] ?? 0).compareTo(order[b.id] ?? 0)),
    custom: custom..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
  );
}
