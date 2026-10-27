import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/local_catalogue.dart';

/// A source owning `x-` IDs: sessions `x-<n>` and courses `x-course-<name>`,
/// scripted per test. A session in [gone] is withdrawn; with [offline] set,
/// every read fails the way a dropped connection does.
class FakeSessionSource implements ContentSource, ParentedContentSource {
  final Map<String, PackModel> packs = {};
  final Set<String> gone = {};
  bool offline = false;

  /// Sessions are not stored and the source cannot be asked, the way
  /// Dharma Seed answers a talk it has not synced while offline.
  bool unreachable = false;

  /// Sessions' own titles, when a test renames one upstream.
  final Map<String, String> titles = {};

  /// Sessions' own artwork, when a test changes one upstream.
  final Map<String, String> covers = {};

  @override
  String get prefix => 'x-';

  static Track session(String id, {String? title, String? coverUrl}) => Track(
    id: id,
    title: title ?? 'Session $id',
    description: '',
    coverUrl: coverUrl ?? 'https://img.test/$id.jpg',
    isPublished: true,
    hasBackgroundSound: true,
    voices: [
      TrackVoice(
        guideName: 'Teacher of $id',
        audioFiles: [
          TrackAudioFile(id: id, path: 'https://a.test/$id', duration: 600000),
        ],
      ),
    ],
  );

  /// Adds a course `x-course-<name>` of the sessions [ids], in order.
  PackModel addCourse(String name, List<String> ids) {
    final pack = PackModel(
      id: 'x-course-$name',
      title: 'Course $name',
      description: 'About $name',
      coverUrl: 'https://img.test/$name.jpg',
      items: [
        for (final id in ids)
          PackItemsModel(
            type: TypeConstants.track,
            id: id,
            title: 'Session $id',
            teacher: 'Teacher of $id',
            coverUrl: 'https://img.test/$id.jpg',
            path: '/tracks/$id',
            durationMs: 600000,
            kind: 'Guided Meditation',
          ),
      ],
    );
    packs[pack.id] = pack;
    return pack;
  }

  @override
  Future<Track> track(String id) async {
    if (offline) throw Exception('Failed host lookup');
    if (unreachable) throw CatalogueEntryUnreachable('track', id);
    if (gone.contains(id) || id.startsWith('x-course-')) {
      throw CatalogueEntryUnavailable('track', id);
    }
    return session(id, title: titles[id], coverUrl: covers[id]);
  }

  @override
  Future<PackModel> pack(String id) async {
    if (offline) throw Exception('Failed host lookup');
    return packs[id] ?? (throw CatalogueEntryUnavailable('pack', id));
  }

  @override
  Future<String?> parentOf(String trackId) async {
    for (final pack in packs.values) {
      if (pack.items.any((i) => i.id == trackId)) return pack.id;
    }
    return null;
  }

  @override
  Future<List<PackModel>> browsePacks() async => packs.values.toList();

  @override
  Future<Map<String, List<String>>> packTrackIds({
    Set<String> startedTrackIds = const {},
  }) async => {
    for (final pack in packs.values)
      pack.id: [for (final item in pack.items) item.id],
  };

  @override
  Future<List<PackItemsModel>> searchPacks(String query) async => const [];

  @override
  Future<List<TrackSearchModel>> searchTracks(String query) async => const [];
}
