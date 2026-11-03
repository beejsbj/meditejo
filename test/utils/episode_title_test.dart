import 'package:flutter_test/flutter_test.dart';
import 'package:medito/utils/episode_title.dart';

/// #84: an episode's page drops what every episode of its course repeats,
/// and nothing that tells the episodes apart. The cases marked "real" are
/// Dharma Seed titles, with their retreat's other titles.
void main() {
  const vervaekeCourse = 'Meditating with John Vervaeke';
  final vervaeke = [
    for (final (i, topic) in const [
      'Mindfulness',
      'Breath and Body',
      'Sitting with Distraction',
      'Contemplation',
      'Insight',
      'Loving-Kindness',
      'Flow',
      'Walking Meditation',
      'Tai Chi and Embodiment',
      'Dialectic into Dialogos',
      'Imaginal Practice',
      'Compassion',
    ].indexed)
      'Meditating with John Vervaeke: Day ${i + 1} - $topic',
  ];

  String clean(
    String title,
    List<String> siblings, {
    String course = '',
    String? teacher,
  }) => episodeTitle(
    title,
    courseTitle: course,
    teacher: teacher,
    siblings: siblings,
  );

  group('the course\'s name goes', () {
    test('in front of each episode; "Day 7" stays whole', () {
      expect(
        clean(vervaeke[6], vervaeke, course: vervaekeCourse),
        'Day 7 - Flow',
      );
      expect(
        clean(vervaeke[11], vervaeke, course: vervaekeCourse),
        'Day 12 - Compassion',
      );
    });

    test('and a long series\' repeated tail with it', () {
      final titles = [
        for (var day = 1; day <= 12; day++)
          'Meditating with John Vervaeke | Day $day | '
              'Livestream Mon-Fri 09:30 EST',
      ];
      expect(clean(titles[0], titles, course: vervaekeCourse), 'Day 1');
      expect(clean(titles[10], titles, course: vervaekeCourse), 'Day 11');
    });

    test('a course of one: its own name, from the front', () {
      expect(
        clean(
          'Meditating with John Vervaeke: An Introduction',
          const [],
          course: vervaekeCourse,
        ),
        'An Introduction',
      );
      // No separator after it: a sentence that starts so.
      expect(
        clean(
          'Meditating with John Vervaeke in the morning',
          const [],
          course: vervaekeCourse,
        ),
        'Meditating with John Vervaeke in the morning',
      );
    });

    test('a short course\'s shared tail, when it is the course\'s name', () {
      final titles = [
        'Compassion - Educators Retreat',
        'Deeper Peace - Educators Retreat',
      ];
      expect(
        clean(titles[0], titles, course: 'Educators Retreat'),
        'Compassion',
      );
      // Named otherwise, a short course keeps it.
      expect(clean(titles[0], titles, course: 'Spring Gathering'), titles[0]);
    });

    test('fullwidth and unspaced em-dash separators count', () {
      expect(
        clean('瞑想入門：第一日', const ['瞑想入門：第一日', '瞑想入門：第二日'], course: '瞑想入門'),
        '第一日',
      );
      expect(
        clean('Being Dharma—Stream Entry', const [
          'Being Dharma—Stream Entry',
          'Being Dharma—The Five Precepts',
        ], course: 'Being Dharma'),
        'Stream Entry',
      );
    });
  });

  group('what tells the episodes apart stays', () {
    test('a separator where the titles part ways is not shared (real)', () {
      final gampo = [
        'Transcendental Dependent Arising',
        'Transcendental Dependent Arising - Questions',
      ];
      expect(
        clean(gampo[1], gampo, course: 'Retreat @ Gampo'),
        'Transcendental Dependent Arising - Questions',
      );
      final days = [
        'Day 1: Arriving',
        for (var day = 10; day <= 12; day++) 'Day $day: Practice',
      ];
      expect(clean(days[0], days, course: 'Day'), 'Day 1: Arriving');
    });

    test('never cut inside brackets (real)', () {
      final titles = [
        for (var week = 1; week <= 9; week++) ...[
          '7 Factors of Awakening - Week $week - Meditation - (2011) '
              '(Note: An updated course offered in 2017)',
          '7 Factors of Awakening - Week $week - Talk - (2011) '
              '(Note: An updated course offered in 2017)',
        ],
      ];
      final course =
          'Buddhist Studies Course - (2011) 7 Factors of Awakening '
          '(Note: an updated course was offered in 2017)';
      final cleaned = clean(titles[0], titles, course: course);
      expect(cleaned, isNot(contains('(Note')));
      expect(cleaned, isNot(endsWith('(')));
      expect(
        RegExp(r'\(').allMatches(cleaned).length,
        RegExp(r'\)').allMatches(cleaned).length,
      );
    });

    test('never leaves just a kind of session (real)', () {
      for (final (titles, course) in const [
        (
          [
            'Wisdom and Compassion Working Together - Part 1 - Talk',
            'Wisdom and Compassion Working Together - Part 1 - Meditation',
          ],
          'Labor Day Retreat',
        ),
        (
          [
            'Introduction to Awareness Practice - Day 1 - Meditation',
            'Introduction to Awareness Practice - Day 1 - Talk',
          ],
          'Fall Retreat',
        ),
        (
          ['Understanding Dukkha - Meditation', 'Understanding Dukkha - Talk'],
          'Buddhist Studies',
        ),
      ]) {
        for (final title in titles) {
          expect(clean(title, titles, course: course), title);
        }
      }
    });

    test('a name may always go, even leaving a kind word', () {
      final village = [
        'Walking Meditation | Plum Village',
        'How to Sit | Plum Village',
      ];
      expect(
        clean(
          village[0],
          village,
          course: 'Mindful Moments',
          teacher: 'Plum Village',
        ),
        'Walking Meditation',
      );
      expect(
        clean(
          village[1],
          village,
          course: 'Mindful Moments',
          teacher: 'Plum Village',
        ),
        'How to Sit',
      );
      // Real: "Meditation Day - Liberation Through Kindness".
      final day = [
        'Liberation Through Kindness - Q & A Session',
        'Liberation Through Kindness - Guided Meditation',
      ];
      expect(
        clean(
          day[0],
          day,
          course: 'Meditation Day - Liberation Through Kindness',
        ),
        'Q & A Session',
      );
    });

    test('never drops a kind of session (real)', () {
      final gita = [
        'Lecture 7: Meditation Instructions',
        'Lecture 8: Meditation Instructions',
        'Lecture 9: Meditation Instructions',
        'Lecture 10: Meditation Instructions',
        'Lecture 11: Meditation Instructions',
      ];
      expect(
        clean(gita[1], gita, course: 'The Yogas of the Bhagavad Gita'),
        'Lecture 8: Meditation Instructions',
      );
    });

    test('a shared front that is not the course\'s name stays (real)', () {
      final forest = [
        'The five spiritual faculties: Faith',
        'The five spiritual faculties: energy and mindfulness.',
        'The five spiritual faculties: samadhi/collectedness and wisdom.',
      ];
      expect(
        clean(
          forest[0],
          forest,
          course: 'September 2017 at IMS - Forest Refuge',
        ),
        'The five spiritual faculties: Faith',
      );
      // However long the course.
      final parts = [
        for (var i = 1; i <= 5; i++)
          'Learning How To Live—Self-Knowing In Action: Part $i',
      ];
      expect(
        clean(parts[0], parts, course: 'Vipassana & Viniyoga Retreat'),
        parts[0],
      );
    });

    test('a teacher\'s name may go like the course\'s', () {
      final talks = [
        'Ajahn Sucitto: Wise Attention',
        'Ajahn Sucitto: Steadying the Mind',
      ];
      expect(
        clean(talks[0], talks, course: 'Cittaviveka', teacher: 'Ajahn Sucitto'),
        'Wise Attention',
      );
    });

    test('a tail repeated in a short course stays unless it is a name', () {
      final titles = [
        'Opening: Arriving | Spring sangha',
        'Settling: Body | Spring sangha',
      ];
      expect(clean(titles[0], titles, course: 'Weekend'), titles[0]);
    });

    test('nothing left but the course\'s name: the title whole (real)', () {
      final titles = [
        'Releasing, Receiving and Awakening Our Life - A Dana Retreat',
        'Releasing, Receiving and Awakening Our Life - Closing',
      ];
      expect(
        clean(
          titles[0],
          titles,
          course: 'Releasing Receiving And Awakening Our Life A Dana Retreat',
        ),
        titles[0],
      );
    });

    test('titles that share nothing at a separator stay whole', () {
      final retreat = [
        'Opening Talk: Why Practise the Jhānas?',
        'Guided Meditation: Settling and Finding the Pleasant',
        'Developing Pīti, Developing Focus',
      ];
      for (final title in retreat) {
        expect(clean(title, retreat, course: 'Practising the Jhānas'), title);
      }
      final times = ['Morning sit 09:30 Mon-Fri', 'Evening sit 19:30 Mon-Fri'];
      expect(clean(times[0], times, course: 'Sits'), times[0]);
    });
  });
}
