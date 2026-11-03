import 'package:flutter_test/flutter_test.dart';
import 'package:medito/utils/episode_title.dart';

/// #84: an episode's page drops what every episode of its course repeats.
void main() {
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

  test('a playlist\'s shared name goes; "Day 7" stays whole', () {
    expect(episodeTitle(vervaeke[6], siblings: vervaeke), 'Day 7 - Flow');
    // "Day 1" and "Day 12" share "Day 1": the cut is at the separator, not
    // inside the number.
    expect(
      episodeTitle(vervaeke[0], siblings: vervaeke),
      'Day 1 - Mindfulness',
    );
    expect(
      episodeTitle(vervaeke[11], siblings: vervaeke),
      'Day 12 - Compassion',
    );
  });

  test('a shared tail goes too ("| Livestream Mon-Fri 09:30 EST")', () {
    final titles = [
      for (var day = 1; day <= 12; day++)
        'Meditating with John Vervaeke | Day $day | '
            'Livestream Mon-Fri 09:30 EST',
    ];
    expect(episodeTitle(titles[0], siblings: titles), 'Day 1');
    expect(episodeTitle(titles[10], siblings: titles), 'Day 11');
  });

  test('titles that share nothing at a separator stay whole', () {
    // A retreat's talks: some start "Guided Meditation:", not all.
    final retreat = [
      'Opening Talk: Why Practise the Jhānas?',
      'Guided Meditation: Settling and Finding the Pleasant',
      'Developing Pīti, Developing Focus',
      'Guided Meditation: The Energy Body',
    ];
    for (final title in retreat) {
      expect(episodeTitle(title, siblings: retreat), title);
    }
    // A podcast's episodes share "Ep. 1" only inside their numbers.
    final podcast = [
      'Ep. 10 - Equanimity in the Midst of Change',
      'Ep. 11 - Kindness Towards the Body',
      'Ep. 12 - The Gradual Training',
    ];
    expect(episodeTitle(podcast[1], siblings: podcast), podcast[1]);
    // "09:30" and "Mon-Fri" are not separators.
    final times = ['Morning sit 09:30 Mon-Fri', 'Evening sit 19:30 Mon-Fri'];
    expect(episodeTitle(times[0], siblings: times), times[0]);
  });

  test('a course of one: its own name goes from the front', () {
    expect(
      episodeTitle(
        'Meditating with John Vervaeke: An Introduction',
        courseTitle: 'Meditating with John Vervaeke',
      ),
      'An Introduction',
    );
    // Not a separator after it: the title is a sentence that starts so.
    expect(
      episodeTitle(
        'Meditating with John Vervaeke in the morning',
        courseTitle: 'Meditating with John Vervaeke',
      ),
      'Meditating with John Vervaeke in the morning',
    );
  });

  test('never leaves less than a word', () {
    final numbered = ['Retreat talk: 1', 'Retreat talk: 2', 'Retreat talk: 3'];
    expect(episodeTitle(numbered[0], siblings: numbered), 'Retreat talk: 1');
    expect(
      episodeTitle('Course', courseTitle: 'Course', siblings: ['Course']),
      'Course',
    );
  });

  test('a title not among the siblings is still cleaned by their prefix', () {
    expect(
      episodeTitle(
        'Meditating with John Vervaeke: Day 19 - Bonus',
        siblings: vervaeke,
      ),
      'Day 19 - Bonus',
    );
  });
}
