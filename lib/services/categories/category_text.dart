/// Text folding for category matching: lower case, no diacritics, words only.
///
/// Dharma Seed titles mix "Jhāna", "jhana" and "Jhanas", so every comparison
/// in the category engine goes through [foldWords] first.
library;

const _groups = {
  'a': 'āăąáàâäãå',
  'c': 'ćčç',
  'd': 'ďđḍ',
  'e': 'ēĕėęéèêë',
  'g': 'ğģ',
  'h': 'ḥ',
  'i': 'īĭįíìîïı',
  'k': 'ķ',
  'l': 'ļłḷ',
  'm': 'ṃṁ',
  'n': 'ńňñṅṇ',
  'o': 'ōŏőóòôöõø',
  'r': 'ŕřṛ',
  's': 'śšşṣ',
  't': 'ţťṭ',
  'u': 'ūŭůűųúùûü',
  'y': 'ýÿ',
  'z': 'źżž',
};

final _foldMap = <int, String>{
  for (final MapEntry(:key, :value) in _groups.entries)
    for (final unit in value.runes) unit: key,
};

final _wordPattern = RegExp(r'[a-z0-9]+');

/// The words of [text], folded: `"Jhāna & Insight — Day 3"` becomes
/// `[jhana, insight, day, 3]`. Punctuation and hyphens separate words.
List<String> foldWords(String text) {
  final folded = StringBuffer();
  for (final unit in text.toLowerCase().runes) {
    folded.write(_foldMap[unit] ?? String.fromCharCode(unit));
  }
  final plain = folded.toString().replaceAll('ß', 'ss');
  return [for (final m in _wordPattern.allMatches(plain)) m[0]!];
}

/// One folded phrase to look for in a title or description. A trailing `*`
/// on the last word makes it a prefix (`jhan*` finds jhana and jhanas).
class CategoryTerm {
  CategoryTerm._(this.words, this.prefix, this.source);

  /// Parses [text]; null when it has no words.
  static CategoryTerm? parse(String text) {
    final prefix = text.trimRight().endsWith('*');
    final words = foldWords(text);
    if (words.isEmpty) return null;
    return CategoryTerm._(words, prefix, text);
  }

  final List<String> words;
  final bool prefix;

  /// The term as written in the asset.
  final String source;

  /// Whether [haystack] (already folded into words) contains the phrase as
  /// whole words, the last one allowed to run on when this is a prefix.
  bool matches(List<String> haystack) {
    final last = words.length - 1;
    for (var start = 0; start + words.length <= haystack.length; start++) {
      var all = true;
      for (var i = 0; i <= last; i++) {
        final word = haystack[start + i];
        final ok = i == last && prefix
            ? word.startsWith(words[i])
            : word == words[i];
        if (!ok) {
          all = false;
          break;
        }
      }
      if (all) return true;
    }
    return false;
  }

  /// This term as an FTS5 phrase: `"loving kindness"` or `"jhan"*`.
  String get ftsPhrase => '"${words.join(' ')}"${prefix ? '*' : ''}';
}
