/// Identity of imported content: `lib-course-<hash>` and `lib-track-<hash>`.
///
/// IDs are stored permanently in stats, favourites, downloads and the native
/// completion queue, so they never change for the same thing. A feed or a URL
/// hashes its address, so adding it twice finds the first; a local file has
/// no address worth hashing, so it gets a random one.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

const libPrefix = 'lib-';
const _coursePrefix = 'lib-course-';
const _trackPrefix = 'lib-track-';

String _hash(String key) =>
    sha1.convert(utf8.encode(key)).toString().substring(0, 16);

String libCourseIdFor(String key) => '$_coursePrefix${_hash(key)}';

String libTrackIdFor(String key) => '$_trackPrefix${_hash(key)}';

/// The ID of a feed episode: unique to the feed and its own episode ID.
String libEpisodeId(String feedUrl, String guid) =>
    libTrackIdFor('$feedUrl\n$guid');

String newLibCourseId([Random? random]) => '$_coursePrefix${_random(random)}';

String newLibTrackId([Random? random]) => '$_trackPrefix${_random(random)}';

String _random(Random? random) {
  final rng = random ?? Random.secure();
  return List.generate(16, (_) => rng.nextInt(16).toRadixString(16)).join();
}

bool isLibCourseId(String id) => id.startsWith(_coursePrefix);

bool isLibTrackId(String id) => id.startsWith(_trackPrefix);
