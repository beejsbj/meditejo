/// Courses the user makes: `my-course-<random>`, an ordered list of sessions
/// from any source, with optional headings.
///
/// A course and a playlist are the same thing here. Completion is kept per
/// session, so a course's progress costs nothing extra; a playlist the user
/// never finishes simply shows its progress quietly. See DECISIONS.md.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/services/library/library_models.dart';

const myPrefix = 'my-';
const _coursePrefix = 'my-course-';

String newMyCourseId([Random? random]) {
  final rng = random ?? Random.secure();
  final hex = List.generate(16, (_) => rng.nextInt(16).toRadixString(16));
  return '$_coursePrefix${hex.join()}';
}

bool isMyCourseId(String id) => id.startsWith(_coursePrefix);

/// Whether [id] names a course (rather than a session) in any source.
bool isCourseId(String id) =>
    isMyCourseId(id) ||
    id.startsWith('ds-retreat-') ||
    id.startsWith('lib-course-') ||
    id.startsWith('yt-playlist-');

/// A session to put in a course, with what it looks like now, so the course
/// can still show it if its source later loses it.
@immutable
class MyItemDraft {
  const MyItemDraft({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.coverUrl = '',
    this.durationMs = 0,
    this.kind = '',
  });

  factory MyItemDraft.fromPackItem(PackItemsModel item) => MyItemDraft(
    id: item.id,
    title: item.title,
    subtitle: item.teacher ?? item.subtitle ?? '',
    coverUrl: item.coverUrl ?? '',
    durationMs: item.durationMs ?? 0,
    kind: item.kind ?? '',
  );

  factory MyItemDraft.fromTrack(Track track) {
    final voice = track.voices.firstOrNull;
    final file = voice?.audioFiles.firstOrNull;
    return MyItemDraft(
      id: track.id,
      title: track.title,
      subtitle: voice?.guideName ?? track.subtitle ?? track.artist?.name ?? '',
      coverUrl: track.coverUrl,
      durationMs: file?.duration ?? 0,
    );
  }

  final String id;
  final String title;
  final String subtitle;
  final String coverUrl;
  final int durationMs;
  final String kind;
}

/// One line of a course on the edit screen: a session or a heading.
@immutable
class MyCourseLine {
  const MyCourseLine.session(this.item, {this.unavailable = false})
    : heading = '';

  const MyCourseLine.heading(this.heading) : item = null, unavailable = false;

  /// The session; null for a heading.
  final MyItemDraft? item;
  final String heading;
  final bool unavailable;

  bool get isHeading => item == null;
}

/// Everything the edit screen changes, written in one go.
@immutable
class MyCourseEdit {
  const MyCourseEdit({
    required this.title,
    this.description = '',
    this.coverUrl = '',
    this.group = LibraryGroup.practice,
    this.lines = const [],
    this.offeredCovers = const [],
  });

  final String title;
  final String description;

  /// One of the sessions' artwork, or empty for generated art.
  final String coverUrl;

  /// Practice or Talks: where the course is filed, and how Home ranks it.
  final LibraryGroup group;
  final List<MyCourseLine> lines;

  /// The session artwork the editor offered when the edit began. It tells a
  /// cover that came from a session (which goes with it) from one carried
  /// from elsewhere, such as a copied retreat's photo (which stays).
  final List<String> offeredCovers;

  MyCourseEdit copyWith({
    String? title,
    String? description,
    String? coverUrl,
    LibraryGroup? group,
    List<MyCourseLine>? lines,
  }) => MyCourseEdit(
    title: title ?? this.title,
    description: description ?? this.description,
    coverUrl: coverUrl ?? this.coverUrl,
    group: group ?? this.group,
    lines: lines ?? this.lines,
    offeredCovers: offeredCovers,
  );

  /// The cover Save writes: [coverUrl], unless it was one of the offered
  /// session artworks and its session has since been taken out, in which
  /// case it is no longer a choice and the course goes back to generated art.
  String get effectiveCoverUrl =>
      coverUrl.isNotEmpty &&
          offeredCovers.contains(coverUrl) &&
          !coverChoices.contains(coverUrl)
      ? ''
      : coverUrl;

  /// Artwork the cover can be chosen from: each session's, once.
  List<String> get coverChoices => {
    for (final line in lines)
      if (line.item case final item? when item.coverUrl.isNotEmpty)
        item.coverUrl,
  }.toList();
}

/// A course as the "Add to course" sheet lists it.
@immutable
class MyCourseSummary {
  const MyCourseSummary({
    required this.id,
    required this.title,
    required this.sessionCount,
    this.coverUrl = '',
    this.contains = false,
  });

  final String id;
  final String title;
  final int sessionCount;
  final String coverUrl;

  /// Whether the course already holds what is being added.
  final bool contains;
}
