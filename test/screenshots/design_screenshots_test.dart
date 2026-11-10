// Screenshots for the design pass's PR, written to docs/fork/design/. Not
// part of the normal run (they render real fonts and write files):
//
//   MEDITEJO_SCREENSHOTS=1 flutter test test/screenshots
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:medito/services/home/favourites_migration.dart';
import 'package:medito/views/home/widgets/pinned/pinned_list_view.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/views/explore/widgets/explore_view.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/services/my_courses/my_course_source.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/views/bottom_navigation/widgets/medito_nav_bar.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/library/item_actions.dart';
import 'package:medito/views/library/library_view.dart';
import 'package:medito/views/soundscape/sound_credits_view.dart';
import 'package:medito/views/soundscape/sounds_view.dart';
import 'package:medito/views/soundscape/synth_editors.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/views/timer/timer_view.dart';
import 'package:medito/views/track/track_view.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/views/cues/bell_maker_view.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/widgets/inputs/wheel_picker.dart';
import 'package:medito/views/player/widgets/autoplay_control.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medito/constants/theme/palette_theme.dart';
import 'package:medito/services/identity/daily_mark.dart';
import 'package:medito/services/identity/mark_generator.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/youtube/youtube_source.dart';
import 'package:medito/src/youtube_api.g.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/teacher/teacher_view.dart';

import 'package:medito/providers/stats/practice_summary_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/views/stats/stats_screen.dart';
import 'package:medito/views/intro/intro_view.dart';
import 'package:medito/views/settings/settings_screen.dart';

import '../helpers/dharma_seed_app.dart';
import '../helpers/dharma_seed_catalogue.dart';
import '../helpers/dharma_seed_fake_api.dart';
import '../helpers/fake_session_source.dart';
import 'package:medito/providers/library/episode_course_provider.dart';
import '../helpers/fake_savable_source.dart';
import '../helpers/library_app.dart';
import '../helpers/stats_fixtures.dart';
import '../helpers/update_fakes.dart';
import '../helpers/soundscape_fakes.dart';
import '../helpers/youtube_fake.dart' show FakeYoutubeApi;

/// Where captures go, and under which palette (the generated art's
/// screenshots run this twice: MEDITEJO_SHOT_PALETTE=tide and another, into
/// `docs/fork/design/art/<palette>`).
final _out = Platform.environment['MEDITEJO_SHOT_DIR'] ?? 'docs/fork/design';
final _palette = IdentityPalettes.byId(
  Platform.environment['MEDITEJO_SHOT_PALETTE'],
);
final _enabled = Platform.environment['MEDITEJO_SCREENSHOTS'] == '1';

Future<void> _loadFonts() async {
  final sans = FontLoader('Google Sans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    sans.addFont(rootBundle.load('assets/fonts/google-sans/GoogleSans-$w.ttf'));
  }
  await sans.load();
  // The tester runs from bin/cache/artifacts/engine/<host>/ in the SDK.
  var root = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    root = root.parent;
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File(
        '${root.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes().then((b) => ByteData.sublistView(b)),
    );
  await icons.load();
  // The tab bar's and the Sounds screen's Material Symbols.
  final symbols =
      FontLoader(
        'packages/material_symbols_icons/MaterialSymbolsRounded',
      )..addFont(
        rootBundle.load(
          'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
        ),
      );
  await symbols.load();
}

final _boundary = GlobalKey();

class _FakeTracks extends Tracks {
  _FakeTracks(this.track);
  final Track track;

  @override
  Future<Track> build({required String trackId}) async => track;
}

/// Courses and sessions to pin, with real titles and counts (#79).
final _pinPacks = [
  for (final (id, title, total, done) in [
    ('ds-retreat-4496', 'Practising the Jhānas', 32, 11),
    ('yt-playlist-vervaeke', 'Meditating with John Vervaeke', 18, 4),
    ('lib-course-c', 'The Art of Concentration', 9, 3),
  ])
    PackModel(
      id: id,
      title: title,
      subtitle: 'Leigh Brasington',
      items: [
        for (var i = 0; i < total; i++)
          PackItemsModel(
            type: 'track',
            id: '$id-$i',
            title: 'Session ${i + 1}',
            path: '/tracks/$id-$i',
            kind: i.isEven ? 'Meditation' : 'Talk',
            isCompleted: i < done,
          ),
      ],
    ),
];

/// The course page at full length (#81): a 32-session retreat over eight
/// days with real-length titles, in progress, and an 18-part YouTube series
/// that has not been started.
final _jhanas = PackModel(
  id: 'ds-retreat-4496',
  title: 'Practising the Jhānas',
  subtitle: 'Rob Burbea · 2019 · 32 talks',
  description:
      'A retreat on the jhānas as a path of samatha: developing pīti and '
      'sukha, working with the energy body, and letting concentration open '
      'into insight.',
  teacher: const PackTeacher(
    id: 'ds-teacher-210',
    name: 'Rob Burbea',
    bio: 'Rob Burbea was resident teacher at Gaia House, Devon.',
  ),
  attribution: const SourceAttribution(
    source: 'Dharma Seed',
    creator: 'Rob Burbea',
    url: 'https://dharmaseed.org/retreats/4496/',
    licenseName: 'CC BY-NC-ND 4.0',
    licenseUrl: 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
  ),
  items: [
    for (final (i, title) in const [
      'Opening Talk: Why Practise the Jhānas?',
      'Guided Meditation: Settling and Finding the Pleasant',
      'Developing Pīti, Developing Focus',
      'Guided Meditation: The Energy Body',
      'Working with Hindrances in Samatha Practice',
      'Q & A: Restlessness, Sleepiness and Doubt',
      'Guided Meditation: Breath and Well-being',
      'The Place of Pleasure on the Path',
      'Guided Meditation: Opening to Pīti',
      'First Jhāna: Vitakka and Vicāra',
      'Guided Meditation: Steadying Attention',
      'Second Jhāna: Pīti Without Effort',
      'Q & A: Is This Jhāna Yet?',
      'Guided Meditation: Sukha, Softening',
      'Third Jhāna: Contentment and Equanimity',
      'Guided Meditation: Resting in Sukha',
      'Fourth Jhāna: Stillness and Brightness',
      'Guided Meditation: Wide, Still Awareness',
      'The Formless Realms: Infinite Space',
      'Q & A: Fear, Intensity and Letting Go',
      'Guided Meditation: Boundless Space',
      'Infinite Consciousness and Nothingness',
      'Guided Meditation: Neither Perception nor Non-perception',
      'Jhāna and Insight: Seeing Emptiness',
      'Guided Meditation: Fabrication and Fading',
      'The Jhānas in Daily Life',
      'Q & A: Practice After the Retreat',
      'Guided Meditation: Metta as a Samatha Object',
      'Beauty, Eros and the Imaginal',
      'Guided Meditation: Gratitude',
      'Closing Talk: Carrying the Practice On',
      'Closing Meditation and Dedication of Merit',
    ].indexed)
      PackItemsModel(
        type: 'track',
        id: 'ds-talk-4496-$i',
        title: title,
        path: '/tracks/ds-talk-4496-$i',
        kind: title.startsWith('Guided') || title.startsWith('Closing Med')
            ? 'Guided meditation'
            : title.startsWith('Q & A')
            ? 'Q & A'
            : 'Talk',
        teacher: 'Rob Burbea',
        durationMs: (38 + (i * 7) % 31) * 60000,
        date: '2019-03-0${1 + i ~/ 4}',
        isCompleted: i < 11,
      ),
  ],
);

final _vervaeke = PackModel(
  id: 'yt-playlist-vervaeke',
  title: 'Meditating with John Vervaeke',
  subtitle: 'John Vervaeke',
  attribution: const SourceAttribution(
    source: 'YouTube',
    creator: 'John Vervaeke',
    url: 'https://www.youtube.com/playlist?list=vervaeke',
    licenseName: '',
    licenseUrl: '',
  ),
  items: [
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
      'Wisdom and Virtue',
      'Equanimity',
      'Self-Transcendence',
      'Participatory Knowing',
      'Relevance Realisation',
      'Closing Reflections',
    ].indexed)
      PackItemsModel(
        type: 'track',
        id: 'yt-video-v$i',
        title: 'Meditating with John Vervaeke: Day ${i + 1} - $topic',
        path: '/tracks/yt-video-v$i',
        teacher: 'John Vervaeke',
        durationMs: (24 + (i * 5) % 22) * 60000,
      ),
  ],
);

/// A nine-day Dharma Seed retreat with a teaching team (#82): instructions,
/// guided sits, talks and Q & A, two to four a day, led by Joseph Goldstein
/// with three other teachers taking sessions.
final _insight = PackModel(
  id: 'ds-retreat-7012',
  title: 'Spring Insight Meditation Retreat',
  subtitle: 'Joseph Goldstein · 2023 · 29 talks',
  teacher: const PackTeacher(
    id: 'ds-teacher-96',
    name: 'Joseph Goldstein',
    bio: 'A co-founder of the Insight Meditation Society.',
  ),
  attribution: const SourceAttribution(
    source: 'Dharma Seed',
    creator: 'Joseph Goldstein',
    url: 'https://dharmaseed.org/retreats/7012/',
    licenseName: 'CC BY-NC-ND 4.0',
    licenseUrl: 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
  ),
  items: [
    for (final (i, (day, kind, teacher, title)) in const [
      (14, 'Talk', 'Joseph Goldstein', 'Opening Talk: Arriving in Silence'),
      (14, 'Guided meditation', 'Sharon Salzberg', 'Settling with the Breath'),
      (
        15,
        'Guided meditation',
        'Joseph Goldstein',
        'Morning Instructions: Mindfulness of Breathing',
      ),
      (15, 'Guided meditation', 'Kamala Masters', 'Walking Meditation'),
      (15, 'Talk', 'Sharon Salzberg', 'The Power of Attention'),
      (
        16,
        'Guided meditation',
        'Joseph Goldstein',
        'Morning Instructions: Sensations in the Body',
      ),
      (16, 'Guided meditation', 'Tempel Smith', 'Metta for a Benefactor'),
      (16, 'Talk', 'Joseph Goldstein', 'The Four Foundations of Mindfulness'),
      (16, 'Q & A', 'Joseph Goldstein', 'Q & A: Sleepiness and Restlessness'),
      (
        17,
        'Guided meditation',
        'Sharon Salzberg',
        'Morning Instructions: Hearing',
      ),
      (17, 'Talk', 'Kamala Masters', 'Patience as a Pāramī'),
      (17, 'Guided meditation', 'Joseph Goldstein', 'Evening Sit'),
      (
        18,
        'Guided meditation',
        'Joseph Goldstein',
        'Morning Instructions: Thoughts and Images',
      ),
      (18, 'Guided meditation', 'Tempel Smith', 'Metta for a Difficult Person'),
      (18, 'Talk', 'Tempel Smith', 'Wise Effort: Not Too Tight, Not Too Loose'),
      (
        19,
        'Guided meditation',
        'Joseph Goldstein',
        'Morning Instructions: Emotions',
      ),
      (19, 'Talk', 'Joseph Goldstein', 'Hindrances as Teachers'),
      (19, 'Q & A', 'Sharon Salzberg', 'Q & A: Doubt and Self-Judgement'),
      (
        20,
        'Guided meditation',
        'Kamala Masters',
        'Morning Instructions: Mind States',
      ),
      (20, 'Talk', 'Sharon Salzberg', 'Faith, Doubt and the Path'),
      (20, 'Guided meditation', 'Sharon Salzberg', 'Metta for All Beings'),
      (
        21,
        'Guided meditation',
        'Joseph Goldstein',
        'Morning Instructions: Choiceless Awareness',
      ),
      (
        21,
        'Talk',
        'Joseph Goldstein',
        'Emptiness of Self in Ordinary Experience',
      ),
      (21, 'Guided meditation', 'Tempel Smith', 'Equanimity Practice'),
      (21, 'Q & A', 'Kamala Masters', 'Q & A: Practice at Home'),
      (
        22,
        'Guided meditation',
        'Sharon Salzberg',
        'Morning Instructions: Returning',
      ),
      (
        22,
        'Talk',
        'Joseph Goldstein',
        'Closing Talk: Taking the Practice Home',
      ),
      (22, 'Guided meditation', 'Sharon Salzberg', 'Closing Metta'),
      (22, 'Talk', 'Kamala Masters', 'Dedication of Merit'),
    ].indexed)
      PackItemsModel(
        type: 'track',
        id: 'ds-talk-7012-$i',
        title: title,
        path: '/tracks/ds-talk-7012-$i',
        kind: kind,
        teacher: teacher,
        durationMs: (24 + (i * 11) % 39) * 60000,
        date: '2023-04-$day',
        isCompleted: i < 6,
      ),
  ],
);

/// A weekly podcast over five months (#82): talks only, by the feed's
/// author with a few guests, each dated. No retreat days to group.
final _podcast = PackModel(
  id: 'lib-course-audiodharma',
  title: 'Audio Dharma: Sunday Talks',
  subtitle: 'Gil Fronsdal',
  attribution: const SourceAttribution(
    source: 'Audio Dharma',
    creator: 'Gil Fronsdal',
    url: 'https://www.audiodharma.org/',
    licenseName: 'CC BY-NC-ND 4.0',
    licenseUrl: 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
  ),
  items: [
    for (final (i, (teacher, title)) in const [
      ('Gil Fronsdal', 'Equanimity in the Midst of Change'),
      ('Gil Fronsdal', 'The Practice of Letting Be'),
      ('Andrea Fella', 'Kindness Towards the Body'),
      ('Gil Fronsdal', 'Mindfulness of Intentions'),
      ('Gil Fronsdal', 'Three Ways of Knowing Suffering'),
      ('Ines Freedman', 'Generosity as a Path of Freedom'),
      ('Gil Fronsdal', 'Renunciation Without Rejection'),
      ('Gil Fronsdal', 'The Gradual Training'),
      ('Nikki Mirghafori', 'Joy and the Wholesome Mind'),
      ('Gil Fronsdal', 'Not Clinging to Views'),
      ('Gil Fronsdal', 'Peace Is Every Step We Take Together'),
      ('Gil Fronsdal', 'Seclusion and Simplicity'),
      ('Andrea Fella', 'Wise Speech in Difficult Conversations'),
      ('Gil Fronsdal', 'The Wisdom of Not Knowing'),
      ('Gil Fronsdal', 'Year-End Reflections on Practice'),
      ('Gil Fronsdal', 'Beginning Again'),
    ].indexed)
      PackItemsModel(
        type: 'track',
        id: 'lib-ad-$i',
        title: title,
        subtitle: teacher,
        path: '/tracks/lib-ad-$i',
        teacher: teacher,
        durationMs: (38 + (i * 7) % 24) * 60000,
        date: DateTime.utc(
          2024,
          9,
          1,
        ).add(Duration(days: 7 * i)).toIso8601String().substring(0, 10),
      ),
  ],
);

const _pinTracks = [
  Track(
    id: 'ds-talk-77',
    title: 'Wise Attention and the Practice of Loving-Kindness',
    subtitle: 'Talk · Ajahn Sucitto · 42 min',
    description: '',
    coverUrl: '',
    isPublished: true,
    hasBackgroundSound: false,
    voices: [],
  ),
  Track(
    id: 'yt-video-1',
    title: 'Meditating with John Vervaeke: Day 1 - Mindfulness',
    subtitle: 'John Vervaeke · 44 min',
    description: '',
    coverUrl: '',
    isPublished: true,
    hasBackgroundSound: false,
    voices: [],
  ),
];

/// What a user who favourited before #79 has saved: the third course, both
/// sessions, and a course they had pinned as well.
final _pinFavouritesJson = jsonEncode([
  {
    'id': _pinPacks[2].id,
    'title': _pinPacks[2].title,
    'type': 'pack',
    'timestamp': 1000,
  },
  {
    'id': _pinTracks[0].id,
    'title': _pinTracks[0].title,
    'subtitle': _pinTracks[0].subtitle,
    'type': 'track',
    'timestamp': 2000,
  },
  {
    'id': _pinPacks[1].id,
    'title': _pinPacks[1].title,
    'type': 'pack',
    'timestamp': 3000,
  },
  {
    'id': _pinTracks[1].id,
    'title': _pinTracks[1].title,
    'subtitle': _pinTracks[1].subtitle,
    'type': 'track',
    'timestamp': 4000,
  },
]);

/// Saves anything of one source, and says which are saved: the episode
/// pages' Library state (#84).
class _SavesAll extends FakeSavableSource {
  _SavesAll(this._prefix, {super.saved});
  final String _prefix;

  @override
  String get prefix => _prefix;

  @override
  bool canSave(String id) => true;
}

/// The Vervaeke series as YouTube titles it: the playlist's name in front
/// and the livestream's schedule behind every episode (#84).
final _vervaekeLive = _vervaeke.copyWith(
  id: 'yt-playlist-vervaeke-live',
  teacher: const PackTeacher(
    id: 'yt-channel-vervaeke',
    name: 'John Vervaeke',
    bio: '',
  ),
  items: [
    for (final (i, item) in _vervaeke.items.indexed)
      item.copyWith(
        id: 'yt-video-live$i',
        path: '/tracks/yt-video-live$i',
        title: '${item.title} | Livestream Mon-Fri 09:30 EST',
        teacherId: 'yt-channel-vervaeke',
      ),
  ],
);

const _ytDescription =
    'Day 7 of the series. Today we practise flow: what it is, why it '
    'matters for meaning, and how a sit can set it up.\n'
    '\n'
    '00:00 Welcome and check-in\n'
    '04:12 Settling the body\n'
    '09:30 Breath, then the field of attention\n'
    '21:45 Flow: challenge meets skill\n'
    '34:10 Questions from the chat\n'
    '41:02 Closing\n'
    '\n'
    'Join us live Monday to Friday at 09:30 EST.\n'
    'Support the work: https://www.patreon.com/johnvervaeke\n'
    'The Vervaeke Foundation: https://vervaekefoundation.org\n'
    '\n'
    '#meditation #flow #meaningcrisis';

/// Episode pages (#84): a YouTube episode of a saved series, a long retreat
/// talk whose retreat is not saved, a podcast episode with a guest, and a
/// talk no course holds.
final _episodes = <({String name, Track track, String? course})>[
  (
    name: 'youtube',
    course: _vervaekeLive.id,
    track: Track(
      id: 'yt-video-live6',
      title: _vervaekeLive.items[6].title,
      subtitle: 'John Vervaeke',
      description: _ytDescription,
      coverUrl: '',
      isPublished: true,
      hasBackgroundSound: true,
      attribution: const SourceAttribution(
        source: 'YouTube',
        creator: 'John Vervaeke',
        url: 'https://www.youtube.com/watch?v=live6',
        licenseName: '',
        licenseUrl: '',
      ),
      voices: const [
        TrackVoice(
          guideName: 'John Vervaeke',
          audioFiles: [
            TrackAudioFile(id: 'live6', path: 'live6', duration: 44 * 60000),
          ],
        ),
      ],
    ),
  ),
  (
    name: 'dharma-seed',
    course: _jhanas.id,
    track: Track(
      id: _jhanas.items[22].id,
      title: _jhanas.items[22].title,
      subtitle: 'Guided meditation · Rob Burbea · 68 min',
      description:
          'The last of the formless realms, approached gently from the '
          'nothingness of the day before: a guided practice in letting '
          'perception itself thin out, and in noticing what the mind makes '
          'of that.',
      coverUrl: '',
      isPublished: true,
      hasBackgroundSound: true,
      attribution: _jhanas.attribution,
      voices: const [
        TrackVoice(
          guideName: 'Rob Burbea',
          audioFiles: [
            TrackAudioFile(id: 'ds22', path: 'ds22', duration: 68 * 60000),
          ],
        ),
      ],
    ),
  ),
  (
    name: 'podcast',
    course: _podcast.id,
    track: Track(
      id: _podcast.items[8].id,
      title: _podcast.items[8].title,
      subtitle: 'Nikki Mirghafori',
      description:
          'Guest teacher Nikki Mirghafori on joy as a wholesome state the '
          'path cultivates, not a reward at its end: how gladness steadies '
          'the mind, and why the Buddha counted it among the factors of '
          'awakening. Recorded at the Insight Meditation Center, Redwood '
          'City, as part of the Sunday morning series. Audio Dharma is '
          'offered freely; donations support the centre.',
      coverUrl: '',
      isPublished: true,
      hasBackgroundSound: false,
      attribution: _podcast.attribution,
      voices: const [
        TrackVoice(
          guideName: 'Nikki Mirghafori',
          audioFiles: [
            TrackAudioFile(id: 'ad8', path: 'ad8', duration: 51 * 60000),
          ],
        ),
      ],
    ),
  ),
  (
    name: 'no-course',
    course: null,
    track: const Track(
      id: 'ds-talk-77',
      title: 'Wise Attention and the Practice of Loving-Kindness',
      subtitle: 'Talk · Ajahn Sucitto · 42 min',
      description: 'A talk given at Cittaviveka on steadying the mind.',
      coverUrl: '',
      isPublished: true,
      hasBackgroundSound: false,
      attribution: SourceAttribution(
        source: 'Dharma Seed',
        creator: 'Ajahn Sucitto',
        url: 'https://dharmaseed.org/talks/77/',
        licenseName: 'CC BY-NC-ND 4.0',
        licenseUrl: 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
      ),
      voices: [
        TrackVoice(
          guideName: 'Ajahn Sucitto',
          audioFiles: [
            TrackAudioFile(id: 'f77', path: 'f77', duration: 42 * 60000),
          ],
        ),
      ],
    ),
  ),
];

/// Everything an episode page reads, for every episode: one ProviderScope
/// is pumped repeatedly.
List<Override> get _episodeOverrides => [
  contentSourcesProvider.overrideWith(
    (ref) => [
      _SavesAll('yt-', saved: {_vervaekeLive.id}),
      _SavesAll('ds-'),
      _SavesAll('lib-', saved: {_podcast.id}),
    ],
  ),
  for (final p in [_vervaekeLive, _jhanas, _podcast])
    packProvider(packId: p.id).overrideWith(() => _PackOf(p)),
  for (final e in _episodes) ...[
    tracksProvider(
      trackId: e.track.id,
    ).overrideWith(() => _FakeTracks(e.track)),
    episodeCourseIdProvider(e.track.id).overrideWith((ref) async => e.course),
  ],
];

class _PackOf extends Pack {
  _PackOf(this.pack);
  final PackModel pack;
  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(pack);
}

List<Override> get _pinOverrides => [
  continueItemsProvider.overrideWith((ref) async => _items),
  for (final p in _pinPacks)
    packProvider(packId: p.id).overrideWith(() => _PackOf(p)),
  for (final t in _pinTracks)
    tracksProvider(trackId: t.id).overrideWith(() => _FakeTracks(t)),
];

/// Lets the generated art finish: its stills rasterise off the test's fake
/// clock, then land on the next frame.
Future<void> _settleArt(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  await _settleArt(tester);
  await tester.runAsync(() async {
    final render =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_out/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Everything on screen, including routes above the page (a bottom sheet).
Future<void> _captureView(WidgetTester tester, String name) async {
  await _settleArt(tester);
  await tester.runAsync(() async {
    var render = tester.element(find.byType(Navigator).first).renderObject!;
    while (!render.isRepaintBoundary) {
      render = render.parent!;
    }
    final layer = render.debugLayer! as OffsetLayer;
    // The render view's bounds are already in physical pixels.
    final image = await layer.toImage(render.paintBounds);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_out/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// [child] in [brightness], still (reduced motion), captured whole.
Widget _frame(Brightness brightness, Widget child) => RepaintBoundary(
  key: _boundary,
  child: Theme(
    data: meditejoTheme(brightness, _palette),
    child: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child,
      ),
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  // An S23+-shaped screen: 1080 × 2340 at 2.625.
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = const Size(1080, 2340);
  await tester.pump();
}

final _items = [
  ContinueItem(
    trackId: 't1',
    path: '/tracks/t1',
    title: 'Developing Piti, Developing Focus',
    group: LibraryGroup.practice,
    lastPlayed: DateTime(2026, 10, 25),
    courseId: 'lib-course-a',
    courseTitle: 'Practising the Jhānas',
    resume: const ResumePoint(positionMs: 1800000, durationMs: 5340000),
    sessionNumber: 4,
    sessionTotal: 32,
  ),
  ContinueItem(
    trackId: 't2',
    path: '/tracks/t2',
    title: 'Metta for a difficult person',
    group: LibraryGroup.practice,
    lastPlayed: DateTime(2026, 10, 24),
    courseId: 'lib-course-b',
    courseTitle: 'The Loving Kindness Retreat',
    sessionNumber: 3,
    sessionTotal: 10,
  ),
];

final _pack = PackModel(
  id: 'lib-course-c',
  title: 'The Art of Concentration',
  items: [
    for (var i = 0; i < 9; i++)
      PackItemsModel(
        type: 'track',
        id: 'c-$i',
        title: 'Talk',
        path: '/tracks/c',
        isCompleted: i < 3,
      ),
  ],
);

class _FakePack extends Pack {
  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(_pack);
}

/// A Dharma Seed catalogue that reads like the real one, for Explore.
Future<void> _seedRealisticCatalogue(DharmaSeedDatabase db) async {
  await db.upsertTeacherRecords({
    1: {'name': 'Rob Burbea', 'bio': '', 'photo': ''},
    2: {'name': 'Leigh Brasington', 'bio': '', 'photo': ''},
    3: {'name': 'Sharon Salzberg', 'bio': '', 'photo': ''},
    4: {'name': 'Gil Fronsdal', 'bio': '', 'photo': ''},
    5: {'name': 'Ajahn Sucitto', 'bio': '', 'photo': ''},
    6: {'name': 'Tara Brach', 'bio': '', 'photo': ''},
  });
  final retreats = <int, (String, String, int, String)>{
    4496: ('Practising the Jhānas', '2019-03-01', 1, 'Meditation'),
    1084: (
      'The Loving Kindness (Metta) Retreat',
      '2010-02-01',
      3,
      'Meditation',
    ),
    1183: ('The Art of Concentration', '2008-05-01', 2, 'Meditation'),
    1308: ('Samatha Meditation', '2007-09-01', 4, 'Talk'),
    2200: (
      'Forest Refuge: Dwelling in the Body',
      '2016-07-01',
      5,
      'Meditation',
    ),
  };
  final talks = <int, Map<String, Object?>>{};
  var id = 1;
  final retreatTalks = <int, List<int>>{};
  for (final MapEntry(key: r, value: (name, date, teacher, type))
      in retreats.entries) {
    for (var n = 1; n <= 6; n++) {
      retreatTalks.putIfAbsent(r, () => []).add(id);
      talks[id] = dsTalkRecord(
        n.isEven ? '$name: talk $n' : 'Guided practice, day $n',
        teacher: teacher,
        retreat: r,
        type: n.isEven ? 'Talk' : type,
        minutes: 20.0 + n * 7,
        date: '$date 0$n:00:00',
      );
      id++;
    }
  }
  for (final (title, teacher, minutes) in [
    ('Metta for a difficult person', 3, 32.0),
    ('Settling the body, settling the mind', 4, 24.0),
    ('Breath as a home', 6, 18.0),
    ('Opening to what is here', 5, 41.0),
  ]) {
    talks[id++] = dsTalkRecord(
      title,
      teacher: teacher,
      type: 'Guided Meditation',
      minutes: minutes,
      date: '2026-10-${10 + id % 9} 08:00:00',
    );
  }
  await db.upsertRetreatRecords({
    for (final MapEntry(key: r, value: (name, date, _, _)) in retreats.entries)
      r: {
        'name': name,
        'description': '',
        'start_date': date,
        'talks': retreatTalks[r]!,
      },
  });
  await db.upsertTalkRecords(talks);
}

class _Stats extends StatsNotifier {
  _Stats(this.stats);
  final LocalAllStats stats;
  @override
  Future<LocalAllStats> build() async => stats;
}

/// [page] on the fixed stats history and an update harness, in [brightness].
Future<void> _pumpYou(
  WidgetTester tester,
  Brightness brightness,
  Widget page,
) async {
  // The reminder row asks for the notification permission.
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(permissions, (call) async => 0);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, null),
  );
  final h = await UpdateHarness.create();
  // The real database would open under the fake clock and leave a drift
  // timer pending; an in-memory one stands in for it.
  final dsDb = memoryDharmaSeedDb();
  addTearDown(dsDb.close);
  final container = ProviderContainer(
    overrides: [
      ...h.overrides,
      dharmaSeedDatabaseProvider.overrideWithValue(dsDb),
      statsProvider.overrideWith(() => _Stats(richStats(fixtureNow))),
      practiceClockProvider.overrideWithValue(() => fixtureNow),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        // The You page is captured with the whole view, banner included.
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: meditejoTheme(brightness, _palette),
        home: _frame(brightness, page),
      ),
    ),
  );
  await _phone(tester);
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
}

/// The Customize sheet over a quiet page, opened as the player opens it.
Future<ProviderContainer> _pumpCustomize(
  WidgetTester tester,
  Brightness brightness, {
  required CueScope scope,
  required CueSettings settings,
  bool beforeStart = false,
  int positionMs = 0,
  Locale? locale,
  List<Override> overrides = const [],
  Widget Function()? sheet,
  double textScale = 1,
  bool narrow = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...soundscapeTestOverrides(FakeSoundscapeEngine()),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  await container
      .read(cueSettingsProvider(scope).notifier)
      .update(settings, courseOverride: scope.courseId != null);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigator,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: meditejoTheme(brightness, _palette),
        home: _frame(
          brightness,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: Text(
                  'Developing Piti, Developing Focus',
                  style: context.typography.emphasized.titleLarge,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _phone(tester);
  if (narrow) {
    // 1080 px wide at 3 = 360 dp, the narrowest phones.
    tester.view.devicePixelRatio = 3;
    await tester.pump();
  }
  unawaited(
    showModalBottomSheet<void>(
      context: navigator.currentContext!,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MediaQuery(
        data: MediaQuery.of(navigator.currentContext!).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child:
            sheet?.call() ??
            CustomizeSheet(
              scope: scope,
              isActive: !beforeStart,
              audioDurationMs: 45 * 60000,
              positionMs: positionMs,
              onStart: beforeStart ? () {} : null,
              clock: () => DateTime(2026, 10, 26, 7, 30),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return container;
}

/// A generated sound's editor (#71), opened from the Sounds tab over a mix
/// of all three generated sounds: noise and drone as the Stillness preset
/// has them (or noise with [customBands]), binaural beats as they start.
Future<void> _pumpSoundEditor(
  WidgetTester tester,
  Brightness brightness,
  String id, {
  List<double>? customBands,
  List<double>? droneRoots,
  Locale? locale,
  double textScale = 1,
  bool narrow = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...soundscapeTestOverrides(FakeSoundscapeEngine()),
    ],
  );
  addTearDown(container.dispose);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigator,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: meditejoTheme(brightness, _palette),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: _frame(brightness, const Scaffold(body: SoundsView())),
      ),
    ),
  );
  await _phone(tester);
  if (narrow) {
    // 1080 px wide at 3 = 360 dp, the narrowest phones.
    tester.view.devicePixelRatio = 3;
    await tester.pump();
  }
  final stillness = kStarterPresets.firstWhere(
    (p) => p.id == 'starter-stillness',
  );
  final mixer = container.read(soundscapeProvider.notifier)..clearMix();
  for (final synth in kSynthIds) {
    mixer.toggleSound(synth);
    final preset = stillness.mix.layer(synth);
    if (preset != null) mixer.setLayerParams(synth, preset.params);
  }
  if (customBands != null) {
    mixer.setLayerParams(
      kSynthNoiseId,
      NoiseParams(colour: NoiseColour.pink, bands: customBands).toJson(),
    );
  }
  if (droneRoots != null) {
    mixer.setLayerParams(
      kSynthDroneId,
      DroneParams.fromJson(
        stillness.mix.layer(kSynthDroneId)!.params,
      ).copyWith(rootsHz: droneRoots).toJson(),
    );
  }
  await tester.pump(const Duration(seconds: 1));
  unawaited(showSynthEditor(navigator.currentContext!, id));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
}

/// Opens a Customize slot's section by its tile ('sound', 'bells', 'rhythm',
/// 'length').
Future<void> _openSlot(WidgetTester tester, String slot) async {
  final tile = find.byKey(ValueKey('customize_slot_$slot'));
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

/// Opens a Customize row by its title.
Future<void> _openRow(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title).first);
  await tester.tap(find.text(title).first);
  await tester.pumpAndSettle();
}

const _vervaekeList = 'PLND1JCRq8Vuh3f0P5qjrSdb5eC1ZfZwWJ';
const _vervaekeCourse = 'yt-playlist-$_vervaekeList';
const _vervaekeChannel = 'UCpqDUjTsof-kTNpnyWper_Q';
const _vervaekeTeacher = 'yt-channel-$_vervaekeChannel';

/// A YouTube course imported through the (fake) extractor, its details
/// filled in, pinned beside a Dharma Seed retreat, in the grid layout.
/// Network pictures never load in a test (they shimmer forever), so the
/// pictures here are stand-in names: each shows its generated art, which
/// keeps the avatar's circle and place visible.
Future<YoutubeSource> _seedYoutubeTeacher(
  WidgetTester tester,
  LibraryTestApp app,
) async {
  const titles = [
    'Introduction',
    'Flow, Metaphor, and the Axial Revolution',
    'Continuous Cosmos and Modern World Grammar',
    'Socrates and the Quest for Wisdom',
    'Plato and the Cave',
    'Aristotle, Kant, and Evolution',
    'Aristotle\'s World View and Erich Fromm',
    'The Buddha and "Mindfulness"',
    'Insight',
    'Consciousness',
    'Higher States of Consciousness, Part 1',
    'Higher States of Consciousness, Part 2',
    'Buddhism and Parasitic Processing',
    'Epistemology and Relevance Realization',
    'Marcus Aurelius and Jesus',
    'Christianity and Agape',
    'Gnosis and Existential Inertia',
    'Augustine and Aquinas',
  ];
  final api = FakeYoutubeApi()
    ..playlists[_vervaekeList] = YoutubePlaylist(
      title: 'Awakening from the Meaning Crisis',
      uploader: 'John Vervaeke',
      thumbnail: '',
      description:
          'A series on the meaning crisis: where it came from, the '
          'cognitive science of meaning, wisdom and self-transcendence, '
          'and the ecology of practices that may help us respond to it.',
      channelUrl: 'https://www.youtube.com/channel/$_vervaekeChannel',
      channelAvatar: 'avatar-vervaeke-small',
      items: [
        for (var i = 0; i < titles.length; i++)
          YoutubePlaylistItem(
            videoId: 'vervaeke${i.toString().padLeft(3, '0')}',
            title:
                'Ep. ${i + 1} - Awakening from the Meaning Crisis - '
                '${titles[i]}',
            uploader: 'John Vervaeke',
            durationSeconds: 3300 + i * 60,
            thumbnail: '',
            channelUrl: 'https://www.youtube.com/channel/$_vervaekeChannel',
          ),
      ],
    )
    ..channels[_vervaekeChannel] = YoutubeChannel(
      url: 'https://www.youtube.com/channel/$_vervaekeChannel',
      name: 'John Vervaeke',
      avatar: 'avatar-vervaeke',
      description:
          'Cognitive scientist at the University of Toronto. Talks on '
          'wisdom, meaning, relevance realization and the meaning crisis.',
    );
  final source = YoutubeSource(
    db: app.harness.db,
    library: app.harness.store,
    api: api,
    detailsPause: () => Duration.zero,
  );
  await tester.runAsync(() async {
    final preview = await source.preview(
      Uri.parse('https://www.youtube.com/playlist?list=$_vervaekeList'),
    );
    await source.add(
      preview,
      const ImportChoice(kind: LibraryKind.course, group: LibraryGroup.talks),
    );
    await source.fillDetails(_vervaekeCourse);
    await app.harness.store.add(
      const LibraryDraft(
        sourceId: 'ds-retreat-1',
        kind: LibraryKind.course,
        title: 'Practising the Jhānas',
        subtitle: 'Rob Burbea',
        coverUrl: 'photo-rob-burbea',
        itemCount: 32,
      ),
    );
    await app.prefs.setStringList('pinned_course_ids', [
      _vervaekeCourse,
      'ds-retreat-1',
    ]);
    await app.prefs.setString('library_layout', 'grid');
  });
  return source;
}

void main() {
  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  const nav = [
    MeditoNavItem(icon: Symbols.home_rounded, label: 'Home'),
    MeditoNavItem(icon: Symbols.search_rounded, label: 'Explore'),
    MeditoNavItem(icon: Symbols.graphic_eq_rounded, label: 'Sounds'),
    MeditoNavItem(icon: Symbols.library_books_rounded, label: 'Library'),
    MeditoNavItem(icon: Symbols.settings_rounded, label: 'Settings'),
  ];

  for (final brightness in Brightness.values) {
    testWidgets('Home, ${brightness.name}', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.prefs.setStringList('pinned_course_ids', [_pack.id]);
      await app.pump(
        tester,
        _frame(
          brightness,
          Scaffold(
            body: const HomeView(),
            bottomNavigationBar: MeditoNavBar(
              items: nav,
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ),
        ),
        overrides: [
          continueItemsProvider.overrideWith((ref) async => _items),
          packProvider(packId: _pack.id).overrideWith(_FakePack.new),
        ],
      );
      await _phone(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'home-${brightness.name}');
      // The whole page, pinned courses included.
      tester.view.physicalSize = const Size(1080, 3150);
      await tester.pump(const Duration(seconds: 1));
      await _capture(tester, 'home-full-${brightness.name}');
    }, skip: !_enabled);

    // Two pinned courses and four favourites from before #79, one of them a
    // pinned course too: moved into pins, Home shows three and See all.
    testWidgets('Pinned and favourites, ${brightness.name}', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.prefs.setStringList('pinned_course_ids', [
        _pinPacks[0].id,
        _pinPacks[1].id,
      ]);
      await app.prefs.setString('favorites', _pinFavouritesJson);
      await migrateFavouritesToPins(app.prefs);
      await app.pump(
        tester,
        _frame(
          brightness,
          Scaffold(
            body: const HomeView(),
            bottomNavigationBar: MeditoNavBar(
              items: nav,
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ),
        ),
        overrides: _pinOverrides,
      );
      await _phone(tester);
      tester.view.physicalSize = const Size(1080, 3150);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'pinned-home-${brightness.name}');
      await app.pump(
        tester,
        _frame(brightness, const PinnedListView()),
        overrides: _pinOverrides,
      );
      await _phone(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'pinned-list-${brightness.name}');
    }, skip: !_enabled);

    // A course page: its Pin control and its bottom bar (#79).
    testWidgets('Course page pin, ${brightness.name}', (tester) async {
      WidgetsApp.debugAllowBannerOverride = false;
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        _frame(brightness, PackView(id: _pinPacks[0].id)),
        overrides: _pinOverrides,
      );
      await _phone(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _captureView(tester, 'course-page-${brightness.name}');
    }, skip: !_enabled);

    // The course page's header, actions and tabs at full length (#81, #92):
    // a long retreat in progress (top and scrolled) and a fresh series.
    testWidgets('Course page header, ${brightness.name}', (tester) async {
      WidgetsApp.debugAllowBannerOverride = false;
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      for (final (pack, name) in [
        (_jhanas, 'course-jhanas'),
        (_vervaeke, 'course-vervaeke'),
      ]) {
        final app = await LibraryTestApp.create(tester);
        await app.pump(
          tester,
          // Keyed: the second course is a page of its own, not the first
          // one's page (and scroll position) reused.
          _frame(brightness, PackView(key: ValueKey(pack.id), id: pack.id)),
          // Both, every time: one ProviderScope is pumped twice.
          overrides: [
            for (final p in [_jhanas, _vervaeke])
              packProvider(packId: p.id).overrideWith(() => _PackOf(p)),
          ],
        );
        await _phone(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await _captureView(tester, '$name-${brightness.name}');
        if (pack == _jhanas) {
          // Scrolled into the sessions: what stays in reach.
          await tester.drag(
            find.byType(CustomScrollView).first,
            const Offset(0, -900),
          );
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          await _captureView(tester, '$name-scrolled-${brightness.name}');
        }
      }
    }, skip: !_enabled);

    // The session rows (#82): a retreat's days, a teaching team, a
    // single-teacher retreat and a dated podcast, scrolled into the list;
    // the team retreat again at 360 dp and a larger text size.
    testWidgets('Course rows, ${brightness.name}', (tester) async {
      WidgetsApp.debugAllowBannerOverride = false;
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      final overrides = [
        for (final p in [_insight, _jhanas, _podcast])
          packProvider(packId: p.id).overrideWith(() => _PackOf(p)),
      ];
      for (final (pack, name, drags) in [
        (_insight, 'insight', const [900.0, 1500.0]),
        (_jhanas, 'jhanas', const [1400.0]),
        (_podcast, 'podcast', const [700.0]),
      ]) {
        final app = await LibraryTestApp.create(tester);
        await app.pump(
          tester,
          _frame(brightness, PackView(key: ValueKey(pack.id), id: pack.id)),
          overrides: overrides,
        );
        await _phone(tester);
        await tester.pump(const Duration(seconds: 1));
        for (final (i, drag) in drags.indexed) {
          await tester.drag(
            find.byType(CustomScrollView).first,
            Offset(0, -drag),
          );
          // Let the fling come to rest before the capture.
          for (var frame = 0; frame < 20; frame++) {
            await tester.pump(const Duration(milliseconds: 200));
          }
          expect(tester.takeException(), isNull);
          await _captureView(
            tester,
            'course-rows-$name-${i + 1}-${brightness.name}',
          );
        }
      }
      // The narrowest phones at a larger text size.
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        _frame(
          brightness,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: PackView(key: const ValueKey('narrow'), id: _insight.id),
            ),
          ),
        ),
        overrides: overrides,
      );
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1080, 2340);
      await tester.pump(const Duration(seconds: 1));
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -1100),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _captureView(
        tester,
        'course-rows-insight-360-x1.3-${brightness.name}',
      );
    }, skip: !_enabled);

    // The header's Play and toggles in long languages, on the narrowest
    // phones and at a larger text size (#81): no word may be cut.
    testWidgets('Course page fit, ${brightness.name}', (tester) async {
      WidgetsApp.debugAllowBannerOverride = false;
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      final finished = _jhanas.copyWith(
        id: 'ds-retreat-4497',
        items: [
          for (final item in _jhanas.items) item.copyWith(isCompleted: true),
        ],
      );
      // The same three every pump: one ProviderScope is pumped repeatedly.
      final overrides = [
        for (final p in [_jhanas, _vervaeke, finished])
          packProvider(packId: p.id).overrideWith(() => _PackOf(p)),
      ];
      for (final lang in const ['en', 'de', 'es']) {
        for (final width in const [360, 411]) {
          for (final scale in const [1.0, 1.3]) {
            final app = await LibraryTestApp.create(tester);
            await app.pump(
              tester,
              _frame(
                brightness,
                Builder(
                  builder: (context) => Localizations.override(
                    context: context,
                    locale: Locale(lang),
                    child: MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: PackView(
                        key: ValueKey('$lang-$width-$scale'),
                        id: _jhanas.id,
                      ),
                    ),
                  ),
                ),
              ),
              overrides: overrides,
            );
            // 1080 px wide at 3 = 360 dp; at 2.625 = 411 dp (S23+).
            tester.view.devicePixelRatio = width == 360 ? 3 : 2.625;
            tester.view.physicalSize = const Size(1080, 2340);
            await tester.pump(const Duration(seconds: 1));
            expect(tester.takeException(), isNull);
            await _captureView(
              tester,
              'course-fit-$lang-$width-x$scale-${brightness.name}',
            );
          }
        }
      }
      // Finished: a quiet "All 32 played" and Play again.
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        _frame(brightness, PackView(id: finished.id)),
        overrides: overrides,
      );
      await _phone(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _captureView(tester, 'course-finished-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Home menus, ${brightness.name}', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.prefs.setStringList('pinned_course_ids', [_pack.id]);
      await app.pump(
        tester,
        _frame(brightness, const Scaffold(body: HomeView())),
        overrides: [
          continueItemsProvider.overrideWith((ref) async => _items),
          packProvider(packId: _pack.id).overrideWith(_FakePack.new),
        ],
      );
      await _phone(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.longPress(find.byKey(const ValueKey('continue_t1')));
      await tester.pumpAndSettle();
      await _captureView(tester, 'home-menu-continue-${brightness.name}');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      final pinned = find.byKey(ValueKey('pinned_${_pack.id}'));
      await tester.ensureVisible(pinned);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: pinned,
          matching: find.byTooltip('More options for ${_pack.title}'),
        ),
      );
      await tester.pumpAndSettle();
      await _captureView(tester, 'home-menu-pinned-${brightness.name}');
      expect(tester.takeException(), isNull);
    }, skip: !_enabled);

    testWidgets('five tabs, ${brightness.name}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _frame(
            brightness,
            Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: MeditoNavBar(
                items: nav,
                selectedIndex: 2,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      // The narrowest common phone width.
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1080, 360);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _capture(tester, 'navbar-five-${brightness.name}');
    }, skip: !_enabled);

    // The longest translations, on the narrowest phone: each label stays on
    // one line, set smaller where it must.
    for (final lang in ['es', 'de']) {
      testWidgets('five tabs in $lang, ${brightness.name}', (tester) async {
        final l10n = lookupAppLocalizations(Locale(lang));
        await tester.pumpWidget(
          MaterialApp(
            home: _frame(
              brightness,
              Scaffold(
                body: const SizedBox.expand(),
                bottomNavigationBar: MeditoNavBar(
                  items: [
                    MeditoNavItem(icon: Symbols.home_rounded, label: l10n.home),
                    MeditoNavItem(
                      icon: Symbols.search_rounded,
                      label: l10n.explore,
                    ),
                    MeditoNavItem(
                      icon: Symbols.graphic_eq_rounded,
                      label: l10n.backgroundSoundsSection,
                    ),
                    MeditoNavItem(
                      icon: Symbols.library_books_rounded,
                      label: l10n.navLibrary,
                    ),
                    MeditoNavItem(
                      icon: Symbols.settings_rounded,
                      label: l10n.navSettings,
                    ),
                  ],
                  selectedIndex: 4,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        );
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(1080, 360);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await _capture(tester, 'navbar-five-$lang-${brightness.name}');
      }, skip: !_enabled);
    }

    // Library's header where it is tight: the title stays whole beside the
    // "+" and You (#62).
    for (final (name, lang, width, scale) in [
      ('library-header-360-large', 'en', 945.0, 1.3),
      ('library-header-de', 'de', 1080.0, 1.0),
    ]) {
      testWidgets('$name, ${brightness.name}', (tester) async {
        final app = await LibraryTestApp.create(tester);
        await app.pump(
          tester,
          _frame(
            brightness,
            Builder(
              builder: (context) => Localizations.override(
                context: context,
                locale: Locale(lang),
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: const LibraryView(),
                ),
              ),
            ),
          ),
        );
        tester.view.devicePixelRatio = 2.625;
        tester.view.physicalSize = Size(width, 600);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await _capture(tester, '$name-${brightness.name}');
      }, skip: !_enabled);
    }

    testWidgets('You and Settings, ${brightness.name}', (tester) async {
      // The Settings tab: its header with the You button, then all of it.
      await _pumpYou(tester, brightness, const SettingsScreen());
      await _capture(tester, 'settings-top-${brightness.name}');
      tester.view.physicalSize = const Size(1080, 6200);
      await tester.pump(const Duration(seconds: 1));
      await _capture(tester, 'settings-${brightness.name}');
      // The You page, as its button opens it over Settings.
      await _phone(tester);
      await tester.tap(find.byKey(const ValueKey('you_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _captureView(tester, 'you-${brightness.name}');
    }, skip: !_enabled);

    // First launch (#87): one quiet page over Home, Start to begin.
    testWidgets('Intro, ${brightness.name}', (tester) async {
      await _pumpYou(tester, brightness, const IntroView(firstRun: true));
      await _capture(tester, 'intro-${brightness.name}');
    }, skip: !_enabled);

    // The longest copy (de), on a 360 dp phone with larger text.
    testWidgets('Intro in de, 360 dp, large text, ${brightness.name}', (
      tester,
    ) async {
      await _pumpYou(
        tester,
        brightness,
        Builder(
          builder: (context) => Localizations.override(
            context: context,
            locale: const Locale('de'),
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: const IntroView(firstRun: true),
            ),
          ),
        ),
      );
      tester.view.physicalSize = const Size(945, 2048);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'intro-360-de-large-${brightness.name}');
    }, skip: !_enabled);

    for (final days in [7, 30]) {
      testWidgets('Stats, $days days, ${brightness.name}', (tester) async {
        await _pumpYou(tester, brightness, const StatsScreen());
        if (days == 30) {
          await tester.tap(find.text('30 days'));
          await tester.pump(const Duration(seconds: 1));
        }
        await _capture(tester, 'stats-top-$days-${brightness.name}');
        tester.view.physicalSize = const Size(1080, 4950);
        await tester.pump(const Duration(seconds: 1));
        await _capture(tester, 'stats-$days-${brightness.name}');
      }, skip: !_enabled);
    }

    // The Sounds tab: the starter mix (three layers) docked under the
    // presets and the library; the same mix open; an empty mix (which stays
    // docked); and a wide window with the panel beside the library.
    for (final (name, empty, open, wide) in [
      ('sounds', false, false, false),
      ('sounds-mix', false, true, false),
      ('sounds-cleared', false, true, false),
      ('sounds-empty', true, false, false),
      ('sounds-wide', false, false, true),
    ]) {
      testWidgets('$name, ${brightness.name}', (tester) async {
        final app = await LibraryTestApp.create(tester);
        await app.pump(
          tester,
          _frame(
            brightness,
            Scaffold(
              body: const SoundsView(),
              bottomNavigationBar: wide
                  ? null
                  : MeditoNavBar(
                      items: nav,
                      selectedIndex: 2,
                      onSelected: (_) {},
                    ),
            ),
          ),
          overrides: soundscapeTestOverrides(FakeSoundscapeEngine()),
        );
        if (wide) {
          // A tablet in landscape.
          tester.view.devicePixelRatio = 2;
          tester.view.physicalSize = const Size(2560, 1600);
          await tester.pump();
        } else {
          await _phone(tester);
        }
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SoundsView)),
        );
        final mixer = container.read(soundscapeProvider.notifier);
        if (empty) {
          mixer.clearMix();
        } else {
          mixer.togglePlay();
        }
        await tester.pump(const Duration(seconds: 1));
        if (open) {
          await tester.tap(find.byKey(const ValueKey('sounds_mix_toggle')));
          await tester.pump(const Duration(seconds: 1));
        }
        if (name == 'sounds-cleared') {
          // Clear, with its Undo snackbar showing.
          await tester.tap(find.byKey(const ValueKey('sounds_clear')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(tester.takeException(), isNull);
        await _capture(tester, '$name-${brightness.name}');
      }, skip: !_enabled);
    }

    // Every generated sound's editor (#71): the same parts throughout.
    for (final (name, id, bands) in [
      ('sound-editor-noise', kSynthNoiseId, null),
      (
        'sound-editor-noise-custom',
        kSynthNoiseId,
        const [0.2, 0.5, 1.0, 0.8, 0.3, 0.6, 1.0, 0.4, 0.1, 0.0],
      ),
      ('sound-editor-drone', kSynthDroneId, null),
      ('sound-editor-binaural', kSynthBinauralId, null),
    ]) {
      testWidgets('$name, ${brightness.name}', (tester) async {
        await _pumpSoundEditor(tester, brightness, id, customBands: bands);
        await _captureView(tester, '$name-${brightness.name}');
      }, skip: !_enabled);
      // The narrowest phone, larger text, the longer German words.
      if (brightness == Brightness.light) {
        testWidgets('$name-360-de-x1.3', (tester) async {
          await _pumpSoundEditor(
            tester,
            brightness,
            id,
            customBands: bands,
            locale: const Locale('de'),
            textScale: 1.3,
            narrow: true,
          );
          await _captureView(tester, '$name-360-de-x1.3');
        }, skip: !_enabled);
      }
    }

    // The drone as a chord (#69): three roots chosen, the rest dimmed.
    testWidgets('sound-editor-drone-chord, ${brightness.name}', (tester) async {
      await _pumpSoundEditor(
        tester,
        brightness,
        kSynthDroneId,
        droneRoots: const [55, 82.41, 110],
      );
      await _captureView(tester, 'sound-editor-drone-chord-${brightness.name}');
    }, skip: !_enabled);

    // Sound credits: long titles ("Summer Rain on Terrace") wrap to a second
    // line, where the licence and source chips used to overlap it.
    testWidgets('sound-credits, ${brightness.name}', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        _frame(brightness, const SoundCreditsView()),
        overrides: soundscapeTestOverrides(FakeSoundscapeEngine()),
      );
      await _phone(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'sound-credits-${brightness.name}');
    }, skip: !_enabled);

    // The same screen at a larger system text size, where titles wrap more.
    testWidgets('sound-credits-large-text, ${brightness.name}', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        _frame(
          brightness,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: const SoundCreditsView(),
            ),
          ),
        ),
        overrides: soundscapeTestOverrides(FakeSoundscapeEngine()),
      );
      await _phone(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'sound-credits-large-text-${brightness.name}');
    }, skip: !_enabled);

    // Decision 18: what the user makes is a Playlist, what a source gives is
    // a Course. The Library lists both; the add-to sheet offers playlists.
    Future<(MyCourseSource, String)> seedPlaylists(
      WidgetTester tester,
      LibraryTestApp app,
    ) async {
      final upstream = FakeSessionSource();
      final source = MyCourseSource(
        db: app.harness.db,
        library: app.harness.store,
        sources: () => [upstream],
      );
      addTearDown(source.dispose);
      MyItemDraft session(String id) => MyItemDraft(
        id: id,
        title: 'Session $id',
        subtitle: 'Teacher of $id',
        durationMs: 600000,
      );
      late String morning;
      await tester.runAsync(() async {
        final store = app.harness.store;
        for (final (id, title, author) in [
          ('ds-retreat-1', 'Jhāna Retreat', 'Rob Burbea'),
          ('lib-course-a', 'Metta, week by week', 'Sharon Salzberg'),
          (
            'yt-playlist-a',
            'Vervaeke: Awakening from the Meaning Crisis',
            'YouTube',
          ),
        ]) {
          await store.add(
            LibraryDraft(
              sourceId: id,
              kind: LibraryKind.course,
              title: title,
              subtitle: author,
            ),
          );
        }
        morning = (await source.create(
          title: 'Morning sits',
          lines: [
            for (final n in [1, 2, 3, 4, 5])
              MyCourseLine.session(session('x-$n')),
          ],
        ));
        await source.create(
          title: 'Evening wind-down',
          lines: [MyCourseLine.session(session('x-6'))],
        );
        await source.create(title: 'For hard days', lines: const []);
      });
      return (source, morning);
    }

    testWidgets('Library with courses and playlists, ${brightness.name}', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      final (source, morning) = await seedPlaylists(tester, app);
      await app.pump(
        tester,
        _frame(brightness, const LibraryView()),
        played: const ['x-1', 'x-2'],
        overrides: [
          myCourseSourceProvider.overrideWithValue(source),
          packTrackIdsProvider.overrideWith(
            (ref) async => {
              morning: ['x-1', 'x-2', 'x-3', 'x-4', 'x-5'],
              'ds-retreat-1': ['d-1', 'd-2', 'd-3'],
            },
          ),
        ],
      );
      await _phone(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'library-playlists-${brightness.name}');
    }, skip: !_enabled);

    // A track with one guide and one length: no pickers (#84).
    testWidgets('Track page, one option, ${brightness.name}', (tester) async {
      WidgetsApp.debugAllowBannerOverride = false;
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      const track = Track(
        id: 'ds-talk-1',
        title: 'Wise Attention and the Practice of Loving-Kindness',
        subtitle: 'Talk · Ajahn Sucitto · 42 min',
        description: 'A talk given on retreat about steadying the mind.',
        coverUrl: '',
        isPublished: true,
        hasBackgroundSound: false,
        voices: [
          TrackVoice(
            guideName: 'Ajahn Sucitto',
            audioFiles: [
              TrackAudioFile(id: 'f1', path: 'f1.mp3', duration: 42 * 60000),
            ],
          ),
        ],
      );
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        _frame(brightness, const TrackView(trackId: 'ds-talk-1')),
        overrides: [
          tracksProvider(
            trackId: 'ds-talk-1',
          ).overrideWith(() => _FakeTracks(track)),
        ],
      );
      await _phone(tester);
      expect(tester.takeException(), isNull);
      await _captureView(tester, 'track-one-option-${brightness.name}');
    }, skip: !_enabled);

    // A YouTube-style track: a channel name as its subtitle, no guide, so the
    // length is only on Play (#84).
    testWidgets('Track page, youtube style, ${brightness.name}', (
      tester,
    ) async {
      WidgetsApp.debugAllowBannerOverride = false;
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      const track = Track(
        id: 'yt-video-1',
        title: 'Meditating with John Vervaeke: Day 1 - Mindfulness',
        subtitle: 'John Vervaeke',
        description: '',
        coverUrl: '',
        isPublished: true,
        hasBackgroundSound: false,
        voices: [
          TrackVoice(
            audioFiles: [
              TrackAudioFile(id: 'yt1', path: 'yt1', duration: 44 * 60000),
            ],
          ),
        ],
      );
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        _frame(brightness, const TrackView(trackId: 'yt-video-1')),
        overrides: [
          tracksProvider(
            trackId: 'yt-video-1',
          ).overrideWith(() => _FakeTracks(track)),
        ],
      );
      await _phone(tester);
      expect(tester.takeException(), isNull);
      await _captureView(tester, 'track-youtube-style-${brightness.name}');
    }, skip: !_enabled);

    // Episode pages (#84): each at the top, the YouTube one scrolled to its
    // description and credit too.
    testWidgets('Episode page, ${brightness.name}', (tester) async {
      WidgetsApp.debugAllowBannerOverride = false;
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      for (final episode in _episodes) {
        final app = await LibraryTestApp.create(tester);
        await app.pump(
          tester,
          _frame(
            brightness,
            TrackView(
              key: ValueKey(episode.track.id),
              trackId: episode.track.id,
            ),
          ),
          overrides: _episodeOverrides,
        );
        await _phone(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await _captureView(
          tester,
          'episode-${episode.name}-${brightness.name}',
        );
        if (episode.name == 'youtube') {
          // Show more, then down to the credit.
          await tester.tap(
            find.byKey(const ValueKey('track_description_more')),
          );
          await tester.pump(const Duration(seconds: 1));
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -1600),
          );
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          await _captureView(
            tester,
            'episode-${episode.name}-end-${brightness.name}',
          );
        }
      }
    }, skip: !_enabled);

    // The narrowest phones at a larger text size, in English and German.
    testWidgets('Episode page fit, ${brightness.name}', (tester) async {
      WidgetsApp.debugAllowBannerOverride = false;
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      for (final episode in _episodes.take(2)) {
        for (final lang in const ['en', 'de']) {
          final app = await LibraryTestApp.create(tester);
          await app.pump(
            tester,
            _frame(
              brightness,
              Builder(
                builder: (context) => Localizations.override(
                  context: context,
                  locale: Locale(lang),
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.3)),
                    child: TrackView(
                      key: ValueKey('${episode.track.id}-$lang'),
                      trackId: episode.track.id,
                    ),
                  ),
                ),
              ),
            ),
            overrides: _episodeOverrides,
          );
          // 1080 px wide at 3 = 360 dp.
          tester.view.devicePixelRatio = 3;
          tester.view.physicalSize = const Size(1080, 2340);
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          await _captureView(
            tester,
            'episode-fit-${episode.name}-$lang-360-x1.3-${brightness.name}',
          );
        }
      }
    }, skip: !_enabled);

    // The course header's ⋮ on a course not yet saved: no Add to library,
    // which sits beside it as a button (#84 integration).
    testWidgets('Course header menu, ${brightness.name}', (tester) async {
      WidgetsApp.debugAllowBannerOverride = false;
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        _frame(brightness, PackView(id: _jhanas.id)),
        overrides: _episodeOverrides,
      );
      await _phone(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('pack_actions')));
      await DharmaSeedTestApp.settle(tester);
      expect(tester.takeException(), isNull);
      await _captureView(tester, 'course-header-menu-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Add to playlist sheet, ${brightness.name}', (tester) async {
      final app = await LibraryTestApp.create(tester);
      final (source, _) = await seedPlaylists(tester, app);
      // No debug ribbon in the corner of the capture.
      WidgetsApp.debugAllowBannerOverride = false;
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      late Future<void> Function() open;
      await app.pump(
        tester,
        _frame(
          brightness,
          Consumer(
            builder: (context, ref, _) {
              open = () => showAddToCourse(
                context,
                ref,
                id: 'x-6',
                fallback: const MyItemDraft(
                  id: 'x-6',
                  title: 'Session x-6',
                  subtitle: 'Teacher of x-6',
                  durationMs: 600000,
                ),
              );
              return const LibraryView();
            },
          ),
        ),
        overrides: [myCourseSourceProvider.overrideWithValue(source)],
      );
      await _phone(tester);
      unawaited(open());
      await DharmaSeedTestApp.settle(tester);
      expect(tester.takeException(), isNull);
      await _captureView(tester, 'add-to-playlist-${brightness.name}');
    }, skip: !_enabled);

    // A playlist's ⋮ in the Library: the longest menu (before #83 a popup).
    testWidgets('Playlist row menu, ${brightness.name}', (tester) async {
      final app = await LibraryTestApp.create(tester);
      final (source, morning) = await seedPlaylists(tester, app);
      WidgetsApp.debugAllowBannerOverride = false;
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      await app.pump(
        tester,
        _frame(brightness, const LibraryView()),
        overrides: [myCourseSourceProvider.overrideWithValue(source)],
      );
      await _phone(tester);
      await tester.tap(find.byKey(ValueKey('library_menu_$morning')));
      await DharmaSeedTestApp.settle(tester);
      expect(tester.takeException(), isNull);
      await _captureView(tester, 'playlist-menu-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Episode actions sheet, ${brightness.name}', (tester) async {
      final app = await LibraryTestApp.create(tester);
      final (source, _) = await seedPlaylists(tester, app);
      WidgetsApp.debugAllowBannerOverride = false;
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      late Future<void> Function() open;
      await app.pump(
        tester,
        _frame(
          brightness,
          Consumer(
            builder: (context, ref, _) {
              open = () => showItemActions(
                context,
                ref,
                ItemActionsSpec(
                  id: 'ds-talk-99944',
                  title:
                      'Developing Piti, Developing Focus, Developing Wellbeing',
                  teacherId: 'ds-teacher-210',
                  isComplete: false,
                  onSetComplete: (_) async => true,
                ),
              );
              return const LibraryView();
            },
          ),
        ),
        overrides: [myCourseSourceProvider.overrideWithValue(source)],
      );
      await _phone(tester);
      unawaited(open());
      await DharmaSeedTestApp.settle(tester);
      expect(tester.takeException(), isNull);
      await _captureView(tester, 'episode-actions-${brightness.name}');
    }, skip: !_enabled);

    // The Customize sheet (design PR 5, regrouped in #72): it opens on the
    // 2×2 slot tiles; each tile opens its section. Before a Practice
    // session, during a course's session, each section open, a wheel in use,
    // and the Timer with its length open.
    const practiceCues = CueSettings(
      startSound: 'assets/audio/bell_bowl_medium.wav',
      endSound: 'assets/audio/bell_bowl_deep.wav',
      intervalHalfway: true,
      intervalMinutes: 15,
      extendMinutes: 5,
      countdownSeconds: 5,
    );
    final courseCues = practiceCues.copyWith(
      intervalHalfway: false,
      randomWindowMinutes: 3,
      pulseSound: 'assets/audio/pulse_heartbeat.wav',
      pulseBpm: 60,
      pulseEndBpm: 48,
      pulseRampMinutes: 10,
      soundscape: 'preset:starter-night',
    );
    const course = CueScope(CueKind.practice, courseId: 'lib-course-a');
    testWidgets('Customize before a session, ${brightness.name}', (
      tester,
    ) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: const CueScope(CueKind.practice),
        settings: practiceCues,
        beforeStart: true,
      );
      await _captureView(tester, 'customize-before-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Customize bells open, ${brightness.name}', (tester) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: const CueScope(CueKind.practice),
        settings: practiceCues,
        beforeStart: true,
      );
      await _openSlot(tester, 'bells');
      await _captureView(tester, 'customize-bells-open-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Customize bell picker, ${brightness.name}', (tester) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: const CueScope(CueKind.practice),
        settings: practiceCues,
        beforeStart: true,
      );
      // The starting bell open: its countdown, then every bell with its
      // icon.
      await _openSlot(tester, 'bells');
      await _openRow(tester, 'Starting bell');
      await tester.ensureVisible(find.text('Starting bell'));
      await tester.pumpAndSettle();
      await _captureView(tester, 'customize-bells-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Customize ending bell, ${brightness.name}', (tester) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: const CueScope(CueKind.practice),
        settings: practiceCues,
        beforeStart: true,
      );
      // The ending bell open: the silence after the audio, then the bells.
      await _openSlot(tester, 'bells');
      await _openRow(tester, 'Ending bell');
      await tester.ensureVisible(find.text('Ending bell'));
      await tester.pumpAndSettle();
      await _captureView(tester, 'customize-ending-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Customize rhythm open, ${brightness.name}', (tester) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: course,
        settings: courseCues,
        beforeStart: true,
      );
      await _openSlot(tester, 'rhythm');
      await _captureView(tester, 'customize-rhythm-${brightness.name}');
    }, skip: !_enabled);

    // The rhythm's wheels in one row (#73), with the ramp off (Ends at
    // dimmed), and on the narrowest phone in German at a larger text size.
    testWidgets('Customize rhythm ramp off, ${brightness.name}', (
      tester,
    ) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: course,
        settings: courseCues.copyWith(pulseRampMinutes: 0),
        beforeStart: true,
      );
      await _openSlot(tester, 'rhythm');
      await _captureView(tester, 'customize-rhythm-off-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Customize rhythm narrow German, ${brightness.name}', (
      tester,
    ) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: course,
        settings: courseCues,
        beforeStart: true,
        locale: const Locale('de'),
        textScale: 1.3,
        narrow: true,
      );
      await _openSlot(tester, 'rhythm');
      // The wheels in view, the tiles above them.
      await tester.ensureVisible(find.byType(WheelPicker<double>).first);
      await tester.pumpAndSettle();
      await _captureView(
        tester,
        'customize-rhythm-360-x1.3-de-${brightness.name}',
      );
    }, skip: !_enabled);

    // #91: a wheel's change brings up its Undo bar.
    testWidgets('Customize undo after a wheel, ${brightness.name}', (
      tester,
    ) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: course,
        settings: courseCues,
        beforeStart: true,
      );
      await _openSlot(tester, 'rhythm');
      final over = find.byKey(const ValueKey('wheel_Slow down over'));
      final wheel = tester.state<WheelPickerState<int>>(over);
      wheel.moveTo(wheel.selectedIndex - 1);
      await tester.pumpAndSettle();
      await _captureView(tester, 'customize-undo-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Customize sound open, ${brightness.name}', (tester) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: course,
        settings: courseCues,
        beforeStart: true,
      );
      await _openSlot(tester, 'sound');
      await _captureView(tester, 'customize-sound-${brightness.name}');
    }, skip: !_enabled);
    // The bell maker: five vertical controls under the live figure; once at
    // the S23+'s size, once on a 320 dp screen with text at 200%.
    for (final narrow in [false, true]) {
      testWidgets(
        'Bell maker${narrow ? ' (narrow, large text)' : ''}, ${brightness.name}',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              ...soundscapeTestOverrides(FakeSoundscapeEngine()),
            ],
          );
          addTearDown(container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: meditejoTheme(brightness, _palette),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(narrow ? 2 : 1),
                  ),
                  child: child!,
                ),
                home: _frame(
                  brightness,
                  const BellMakerView(from: 'assets/audio/bell_temple.wav'),
                ),
              ),
            ),
          );
          if (narrow) {
            tester.view.devicePixelRatio = 2;
            tester.view.physicalSize = const Size(640, 3000);
            await tester.pump();
          } else {
            await _phone(tester);
          }
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          await _captureView(
            tester,
            'bell-maker${narrow ? '-narrow-large-text' : ''}-${brightness.name}',
          );
        },
        skip: !_enabled,
      );
    }

    testWidgets('Customize during a session, ${brightness.name}', (
      tester,
    ) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: course,
        settings: courseCues,
        positionMs: 12 * 60000,
      );
      await _captureView(tester, 'customize-during-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Customize wheel in use, ${brightness.name}', (tester) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: const CueScope(CueKind.practice),
        settings: practiceCues.copyWith(
          intervalHalfway: false,
          randomWindowMinutes: 3,
        ),
        beforeStart: true,
      );
      await _openSlot(tester, 'bells');
      await _openRow(tester, 'Interval bell');
      // The row's header at the top, its wheels and list under it.
      await tester.ensureVisible(find.text('Interval bell'));
      await tester.pumpAndSettle();
      await _captureView(tester, 'customize-wheel-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Customize in German, ${brightness.name}', (tester) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: course,
        settings: courseCues.copyWith(soundscape: 'mix'),
        beforeStart: true,
        locale: const Locale('de'),
      );
      await _captureView(tester, 'customize-de-${brightness.name}');
    }, skip: !_enabled);

    // Autoplay moved from Customize's Flow section to the player (#72).
    testWidgets('Autoplay sheet, ${brightness.name}', (tester) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: course,
        settings: courseCues.copyWith(autoplay: true, interludeSeconds: 10),
        overrides: [
          packDataProvider(packId: course.courseId!).overrideWith(
            (ref) async => PackModel(
              id: course.courseId!,
              title: 'Practising the Jhānas',
              items: [
                for (final (i, title) in [
                  'Settling the body and the breath',
                  'Piti, and letting it build',
                  'Sukha: the second jhāna',
                ].indexed)
                  PackItemsModel(
                    type: 'track',
                    id: 't$i',
                    title: 'Day ${i + 1}: $title',
                    path: '/tracks/t$i',
                  ),
              ],
            ),
          ),
        ],
        sheet: () => AutoplaySheet(scope: course, trackId: 't0'),
      );
      await _captureView(tester, 'autoplay-sheet-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Timer setup with its duration open, ${brightness.name}', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        _frame(brightness, const TimerView()),
        overrides: soundscapeTestOverrides(FakeSoundscapeEngine()),
      );
      await _phone(tester);
      await tester.pump(const Duration(seconds: 1));
      await _openSlot(tester, 'length');
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'timer-duration-${brightness.name}');
    }, skip: !_enabled);

    // Design pass PR 4: the Library with a realistic mix (two courses
    // started, two playlists, three singles, a saved teacher), in the list
    // and the grid.
    for (final grid in [false, true]) {
      testWidgets('Library mix${grid ? ' grid' : ''}, ${brightness.name}', (
        tester,
      ) async {
        final app = await LibraryTestApp.create(tester);
        final (source, morning) = await seedPlaylists(tester, app);
        await tester.runAsync(() async {
          final store = app.harness.store;
          for (final (id, title, subtitle, group) in [
            (
              'ds-talk-60864',
              'Developing Piti, Developing Focus, Developing Wellbeing',
              'Guided Meditation · Rob Burbea · 89 min',
              LibraryGroup.practice,
            ),
            (
              'lib-track-body',
              'Body scan, 20 minutes',
              'My recording',
              LibraryGroup.practice,
            ),
            (
              'ds-talk-2',
              'Emptiness and the middle way',
              'Talk · Rob Burbea · 52 min',
              LibraryGroup.talks,
            ),
          ]) {
            await store.add(
              LibraryDraft(
                sourceId: id,
                kind: LibraryKind.single,
                title: title,
                subtitle: subtitle,
                group: group,
              ),
            );
          }
          await store.add(
            const LibraryDraft(
              sourceId: 'ds-teacher-210',
              kind: LibraryKind.teacher,
              title: 'Rob Burbea',
              subtitle: '1,200 talks',
            ),
          );
          if (grid) await app.prefs.setString('library_layout', 'grid');
        });
        await app.pump(
          tester,
          _frame(brightness, const LibraryView()),
          played: const ['x-1', 'x-2', 'd-1', 'd-2', 'd-3', 'y-1'],
          overrides: [
            myCourseSourceProvider.overrideWithValue(source),
            packTrackIdsProvider.overrideWith(
              (ref) async => {
                morning: ['x-1', 'x-2', 'x-3', 'x-4', 'x-5'],
                'ds-retreat-1': ['d-1', 'd-2', 'd-3', 'd-4', 'd-5', 'd-6'],
                'yt-playlist-a': ['y-1', 'y-2', 'y-3', 'y-4'],
              },
            ),
          ],
        );
        await _phone(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        final name = 'library-mix${grid ? '-grid' : ''}-${brightness.name}';
        await _capture(tester, name);
        // The whole page.
        tester.view.physicalSize = Size(1080, grid ? 5600 : 5000);
        await tester.pump(const Duration(seconds: 1));
        await _capture(
          tester,
          name.replaceFirst('library-mix', 'library-mix-full'),
        );
      }, skip: !_enabled);
    }

    // #85: a YouTube channel as the teacher. On a Library card its picture
    // sits at the lower left of the art and the pin disc at the lower right
    // (a Dharma Seed course beside it for comparison); then the course page,
    // its Teacher tab, and the channel's own page.
    testWidgets('YouTube channel as teacher, ${brightness.name}', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      final source = await _seedYoutubeTeacher(tester, app);
      // The same overrides throughout: a scope keeps its count.
      final page = [
        youtubeSourceProvider.overrideWithValue(source),
        contentSourcesProvider.overrideWith(
          (ref) => [ref.watch(youtubeSourceProvider)],
        ),
      ];
      await app.pump(
        tester,
        _frame(brightness, const LibraryView()),
        overrides: page,
      );
      await _phone(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'yt-teacher-library-${brightness.name}');

      await app.pump(
        tester,
        _frame(brightness, const PackView(id: _vervaekeCourse)),
        overrides: page,
      );
      await _phone(tester);
      await DharmaSeedTestApp.settle(tester);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'yt-teacher-course-${brightness.name}');
      await tester.tap(find.text('Teacher'));
      await DharmaSeedTestApp.settle(tester);
      await _capture(tester, 'yt-teacher-tab-${brightness.name}');

      await app.pump(
        tester,
        _frame(brightness, const TeacherView(teacherId: _vervaekeTeacher)),
        overrides: page,
      );
      await _phone(tester);
      await DharmaSeedTestApp.settle(tester);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'yt-teacher-channel-${brightness.name}');
    }, skip: !_enabled);

    // Explore: browse with nothing typed, and grouped search results.
    for (final query in [null, 'jhāna']) {
      testWidgets('Explore ${query == null ? 'browse' : 'search'}, '
          '${brightness.name}', (tester) async {
        final app = await DharmaSeedTestApp.create(tester, seed: false);
        await tester.runAsync(() async {
          await _seedRealisticCatalogue(app.db);
          await app.source.setSaved('ds-retreat-1084', saved: true);
          await app.source.setSaved('ds-teacher-1', saved: true);
          await app.library.add(
            const LibraryDraft(
              sourceId: 'yt-playlist-a',
              kind: LibraryKind.course,
              title: 'Qualia Mastery',
              subtitle: 'Qualia Research Institute',
            ),
          );
        });
        await app.pump(tester, _frame(brightness, const ExploreView()));
        await _phone(tester);
        if (query != null) {
          await tester.enterText(find.byType(TextField), query);
          await tester.pump(const Duration(milliseconds: 450));
        }
        await DharmaSeedTestApp.settle(tester);
        expect(tester.takeException(), isNull);
        final name =
            'explore-${query == null ? 'browse' : 'search'}-${brightness.name}';
        await _capture(tester, name);
        tester.view.physicalSize = const Size(1080, 4400);
        await DharmaSeedTestApp.settle(tester);
        await _capture(
          tester,
          name
              .replaceFirst('-browse', '-browse-full')
              .replaceFirst('-search', '-search-full'),
        );
      }, skip: !_enabled);
    }

    for (final (name, page) in [
      ('timer', const TimerView()),
      ('library-empty', const LibraryView()),
    ]) {
      testWidgets('$name (inherits the theme), ${brightness.name}', (
        tester,
      ) async {
        final app = await LibraryTestApp.create(tester);
        await app.pump(tester, _frame(brightness, page));
        await _phone(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await _capture(tester, '$name-${brightness.name}');
      }, skip: !_enabled);
    }
  }

  testWidgets('the mark, frame by frame', (tester) async {
    // Today's mark (2026-10-26) drawing in, then one breath (10 s): 40
    // frames for the GIF, every fifth also for a strip.
    const frames = 40;
    final mark = MarkGenerator.build(
      DailyMark.forDay(DateTime(2026, 10, 26)).seed,
    );
    for (final brightness in Brightness.values) {
      final theme = meditejoTheme(brightness, _palette);
      final scheme = theme.colorScheme;
      final colors = theme.extension<MeditejoPalette>()!.markColors(scheme);
      for (var i = 0; i < frames; i++) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: _boundary,
            child: ColoredBox(
              color: scheme.surface,
              child: Center(
                child: CustomPaint(
                  size: const Size.square(240),
                  painter: MarkPainter(
                    mark: mark,
                    colors: colors,
                    time: ValueNotifier(
                      i < 10 ? i * 0.35 : 3.5 + (i - 10) / 30 * 10,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(280, 280);
        await tester.pump();
        await _capture(
          tester,
          'mark-frames/${brightness.name}-${i.toString().padLeft(3, '0')}',
        );
      }
    }
  }, skip: !_enabled);
}
