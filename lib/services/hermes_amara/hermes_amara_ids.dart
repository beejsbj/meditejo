/// Hermes Amāra Foundation identity: app IDs, public URLs and credit.
///
/// Rob Burbea's teachings at hermesamara.org. The site states no licence
/// ("Copyright Hermes Amāra Foundation for the benefit of all beings"), so
/// the attribution carries no licence link and the app never re-hosts audio.
/// IDs: `ha-talk-<slug>` for a talk, `ha-retreat-<slug of the event>` for a
/// retreat (a course).
library;

import 'package:medito/models/attribution/source_attribution.dart';

const hermesAmaraPrefix = 'ha-';
const _talkPrefix = 'ha-talk-';
const _retreatPrefix = 'ha-retreat-';

const hermesAmaraSite = 'https://hermesamara.org';

/// The page the whole listing is read from.
const haListingUrl = '$hermesAmaraSite/resources/audio';

const haSourceName = 'Hermes Amāra Foundation';
const haDefaultCreator = 'Rob Burbea';

/// The notice the site carries; no licence is stated, so none is invented.
const haLicenceName = 'Copyright Hermes Amāra Foundation';
const haLicenceUrl = '';

/// The file the site's own talk page plays.
const _audioBase = 'https://storage.googleapis.com/hermes-amara/stems';

String haTalkId(String slug) => '$_talkPrefix$slug';
String haRetreatId(String eventSlug) => '$_retreatPrefix$eventSlug';

bool isHaTalkId(String id) => id.startsWith(_talkPrefix);
bool isHaRetreatId(String id) => id.startsWith(_retreatPrefix);

/// The slug in a talk ID, or null.
String? parseHaTalkId(String id) =>
    isHaTalkId(id) && id.length > _talkPrefix.length
    ? id.substring(_talkPrefix.length)
    : null;

/// The event slug in a retreat ID, or null.
String? parseHaRetreatId(String id) =>
    isHaRetreatId(id) && id.length > _retreatPrefix.length
    ? id.substring(_retreatPrefix.length)
    : null;

/// The audio URL the site's own talk page plays, streamed unmodified.
String haAudioUrl(String slug) =>
    '$_audioBase/${Uri.encodeComponent(slug)}.mp3';

/// A talk's own page, for attribution.
String haTalkPageUrl(String slug) =>
    '$hermesAmaraSite/resources/talk/${Uri.encodeComponent(slug)}';

/// An event name as an ID-safe slug: lower case, diacritics folded, runs of
/// anything else a single dash. `Silent Autumn Retreat, Finland 2006` is
/// `silent-autumn-retreat-finland-2006`.
String haEventSlug(String event) => haTerms(event).join('-');

SourceAttribution haAttribution({required String url, String? creator}) =>
    SourceAttribution(
      source: haSourceName,
      creator: creator == null || creator.isEmpty ? haDefaultCreator : creator,
      url: url,
      licenseName: haLicenceName,
      licenseUrl: haLicenceUrl,
    );

const _fold = {
  'ā': 'a',
  'ī': 'i',
  'ū': 'u',
  'ṅ': 'n',
  'ñ': 'n',
  'ṇ': 'n',
  'ṭ': 't',
  'ḍ': 'd',
  'ḷ': 'l',
  'ṃ': 'm',
  'ṁ': 'm',
  'ś': 's',
  'ṣ': 's',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ü': 'u',
  'ö': 'o',
  'ä': 'a',
  'á': 'a',
  'à': 'a',
  'í': 'i',
  'ó': 'o',
  'ú': 'u',
  'ç': 'c',
};

/// Lower-case words of [text], apostrophes dropped, diacritics folded, so
/// "samadhi" finds "Samādhi". Kept here rather than shared with the
/// dhammatalks adapter, which keeps its own.
List<String> haTerms(String text) {
  final folded = text
      .toLowerCase()
      .replaceAll(RegExp(r"['’‘`]"), '')
      .split('')
      .map((c) => _fold[c] ?? c)
      .join();
  return folded
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
}
