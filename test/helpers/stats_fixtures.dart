import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';

const minuteMs = 60 * 1000;

/// Wednesday 21 October 2026, mid-afternoon: "now" for the stats fixtures.
final fixtureNow = DateTime(2026, 10, 21, 14);

LocalAudioCompleted fixtureEntry(
  String id,
  DateTime at, {
  int? minutes,
  String? kind,
  String? courseId,
  String? courseTitle,
}) => LocalAudioCompleted(
  id: id,
  timestamp: at.millisecondsSinceEpoch,
  durationMs: minutes == null ? null : minutes * minuteMs,
  kind: kind,
  courseId: courseId,
  courseTitle: courseTitle,
);

/// Seven sessions across five days, with every case the stats page has to
/// tell apart: a course talk, a timer, a guided course, a manual entry, a
/// single from YouTube, a session from before lengths were recorded, and a
/// timer whose length is only in its id. Totals are worked out in
/// `practice_summary_test.dart`.
LocalAllStats fixtureStats() => LocalAllStats.empty().copyWith(
  totalTimeListened: 200 * minuteMs,
  totalTracksCompleted: 7,
  streakCurrent: 2,
  streakLongest: 9,
  consistencyScore: 0.62,
  updated: 1,
  audioCompleted: [
    fixtureEntry(
      'ds-talk-1',
      DateTime(2026, 10, 21, 8),
      minutes: 60,
      kind: 'talks',
      courseId: 'ds-retreat-4496',
      courseTitle: 'Practising the Jhānas',
    ),
    fixtureEntry('timer-600', DateTime(2026, 10, 21, 12), minutes: 10),
    fixtureEntry(
      'lib-track-x',
      DateTime(2026, 10, 20, 21),
      minutes: 20,
      kind: 'practice',
      courseId: 'lib-course-a',
      courseTitle: 'Metta',
    ),
    fixtureEntry('manual2', DateTime(2026, 10, 18, 12), minutes: 30),
    fixtureEntry(
      'yt-video-1',
      DateTime(2026, 10, 3, 9),
      minutes: 15,
      kind: 'talks',
    ),
    fixtureEntry('ds-talk-9', DateTime(2026, 9, 28, 7)),
    fixtureEntry('timer-300', DateTime(2026, 9, 28, 20)),
  ],
);
