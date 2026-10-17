import 'package:medito/services/dharma_seed/dharma_seed_database.dart';

/// One talk record as Dharma Seed's API returns it, with the fields the
/// database reads.
Map<String, Object?> dsTalkRecord(
  String title, {
  required int teacher,
  int? retreat,
  String type = 'Talk',
  double minutes = 30,
  String date = '2014-03-01 10:00:00',
  String description = '',
  List<int> teachers = const [],
}) => {
  'title': title,
  'description': description,
  'teacher_id': teacher,
  'retreat_id': retreat ?? 0,
  'audio_url': '/talks/1/file.mp3',
  'duration_in_minutes': minutes,
  'recording_type': type,
  'rec_date': date,
  'teachers': teachers,
};

/// A small catalogue with every shape the screens care about:
///
/// - teacher 1 "Rob Burbea" (photo, bio) and teacher 2 "Leigh Brasington"
///   (no photo, no bio);
/// - retreat 100 "Jhana Retreat" (Burbea, 2014): 3 guided meditations, 1 talk
///   → mostly practice;
/// - retreat 200 "Dharma Talks Winter" (Brasington): a talk co-taught with
///   Burbea and a Q & A → talks;
/// - retreat 300 "Mixed Weekend": 1 meditation, 1 talk → at least half
///   practice, so it counts as practice;
/// - one single talk with no retreat and no recording type.
Future<void> seedDharmaSeedCatalogue(DharmaSeedDatabase db) async {
  await db.upsertTeacherRecords({
    1: {'name': 'Rob Burbea', 'bio': 'Taught at Gaia House.', 'photo': 'p.png'},
    2: {'name': 'Leigh Brasington', 'bio': '', 'photo': ''},
  });
  await db.upsertRetreatRecords({
    100: {
      'name': 'Jhana Retreat',
      'description': 'Seven days of jhana.',
      'start_date': '2014-03-01',
      'talks': [1, 2, 3, 4],
    },
    200: {
      'name': 'Dharma Talks Winter',
      'description': '',
      'start_date': '2015-01-10',
      'talks': [5, 6],
    },
    300: {
      'name': 'Mixed Weekend',
      'description': '',
      'start_date': '2016-06-01',
      'talks': [7, 8],
    },
  });
  await db.upsertTalkRecords({
    1: dsTalkRecord(
      'Settling',
      teacher: 1,
      retreat: 100,
      type: 'Meditation',
      minutes: 9.5,
      date: '2014-03-01 08:00:00',
    ),
    2: dsTalkRecord(
      'Jhana basics',
      teacher: 1,
      retreat: 100,
      type: 'Talk',
      minutes: 60,
      date: '2014-03-01 20:00:00',
    ),
    3: dsTalkRecord(
      'Breath meditation',
      teacher: 1,
      retreat: 100,
      type: 'Meditation',
      minutes: 45,
      date: '2014-03-02 08:00:00',
    ),
    4: dsTalkRecord(
      'Metta',
      teacher: 1,
      retreat: 100,
      type: 'Meditation',
      minutes: 20,
      date: '2014-03-03 08:00:00',
    ),
    5: dsTalkRecord(
      'Winter talk',
      teacher: 2,
      retreat: 200,
      minutes: 50,
      date: '2015-01-10 19:00:00',
      teachers: [1, 2],
    ),
    6: dsTalkRecord(
      'Winter questions',
      teacher: 2,
      retreat: 200,
      type: 'Q & A',
      minutes: 10,
      date: '2015-01-11 19:00:00',
    ),
    7: dsTalkRecord(
      'Sit',
      teacher: 2,
      retreat: 300,
      type: 'Meditation',
      minutes: 30,
      date: '2016-06-01 08:00:00',
    ),
    8: dsTalkRecord(
      'Talk about sitting',
      teacher: 2,
      retreat: 300,
      minutes: 44.9,
      date: '2016-06-01 20:00:00',
    ),
    9: dsTalkRecord(
      'Untyped talk about jhana',
      teacher: 1,
      type: '',
      minutes: 15,
      date: '2017-01-01 10:00:00',
    ),
  });
}
