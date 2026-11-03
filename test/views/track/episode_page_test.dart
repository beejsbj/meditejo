import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/episode_course_provider.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/views/library/item_actions.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/player/widgets/bottom_actions/single_back_action_bar.dart';
import 'package:medito/views/track/track_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/fake_savable_source.dart';
import '../../helpers/library_app.dart';

class _FakeTracks extends Tracks {
  _FakeTracks(this.track);
  final Track track;

  @override
  Future<Track> build({required String trackId}) async => track;
}

/// What the course lists right now: a test takes a session out of it.
PackModel _listed = _course;

class _FakePack extends Pack {
  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(_listed);
}

/// Saves anything YouTube, as the real source does.
class _YoutubeSaves extends FakeSavableSource {
  _YoutubeSaves({super.saved});

  @override
  String get prefix => 'yt-';

  @override
  bool canSave(String id) => true;
}

const _courseId = 'yt-playlist-vervaeke';
const _trackId = 'yt-video-v6';

final _course = PackModel(
  id: _courseId,
  title: 'Meditating with John Vervaeke',
  subtitle: 'John Vervaeke',
  teacher: const PackTeacher(
    id: 'yt-channel-vervaeke',
    name: 'John Vervaeke',
    bio: '',
  ),
  items: [
    for (var i = 0; i < 18; i++)
      PackItemsModel(
        type: 'track',
        id: 'yt-video-v$i',
        title: 'Meditating with John Vervaeke: Day ${i + 1} - Topic ${i + 1}',
        path: '/tracks/yt-video-v$i',
        teacher: 'John Vervaeke',
        teacherId: 'yt-channel-vervaeke',
      ),
  ],
);

Track _track({String description = '', String? subtitle = 'John Vervaeke'}) =>
    Track(
      id: _trackId,
      title: 'Meditating with John Vervaeke: Day 7 - Topic 7',
      subtitle: subtitle,
      description: description,
      coverUrl: '',
      isPublished: true,
      hasBackgroundSound: false,
      voices: const [
        TrackVoice(
          guideName: 'John Vervaeke',
          audioFiles: [
            TrackAudioFile(id: 'f', path: 'f', duration: 44 * 60000),
          ],
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  Track? track,
  String? courseId = _courseId,
  Set<String> saved = const {},
  Widget page = const TrackView(trackId: _trackId),
  bool asRoute = false,
}) async {
  _listed = _course;
  final app = await LibraryTestApp.create(tester);
  await app.pump(
    tester,
    page,
    asRoute: asRoute,
    overrides: [
      contentSourcesProvider.overrideWith(
        (ref) => [_YoutubeSaves(saved: saved)],
      ),
      tracksProvider(
        trackId: _trackId,
      ).overrideWith(() => _FakeTracks(track ?? _track())),
      episodeCourseIdProvider(_trackId).overrideWith((ref) async => courseId),
      packProvider(packId: _courseId).overrideWith(_FakePack.new),
    ],
  );
  await DharmaSeedTestApp.settle(tester);
}

final _saveToggle = find.byKey(const ValueKey('course_library'));

Future<Set<String>> _sheetActions(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('track_actions')));
  await DharmaSeedTestApp.settle(tester);
  final keys = {
    for (final tile in tester.widgetList<ListTile>(
      find.descendant(
        of: find.byKey(const ValueKey('item_actions_sheet')),
        matching: find.byType(ListTile),
      ),
    ))
      (tile.key! as ValueKey<String>).value.replaceFirst('item_action_', ''),
  };
  await tester.tapAt(const Offset(20, 20));
  await DharmaSeedTestApp.settle(tester);
  return keys;
}

void main() {
  group('an episode page (#84)', () {
    testWidgets('of a saved course: its own title, "In <course>" in place of '
        'Add to library, its channel', (tester) async {
      await _pump(tester, saved: {_courseId});

      expect(find.text('Day 7 - Topic 7'), findsOneWidget);
      expect(
        find.text('Meditating with John Vervaeke: Day 7 - Topic 7'),
        findsNothing,
      );
      expect(
        find.textContaining('In Meditating with John Vervaeke'),
        findsOneWidget,
      );
      expect(find.textContaining('Part of'), findsNothing);
      expect(_saveToggle, findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('track_teacher')),
          matching: find.text('John Vervaeke'),
        ),
        findsOneWidget,
      );
      // Said once, as the teacher; the subtitle is not repeated.
      expect(find.text('John Vervaeke'), findsOneWidget);
      expect(find.text('Play · 44 min'), findsOneWidget);
      for (final key in const [
        'track_add_to_course',
        'course_pin',
        'course_share',
        'track_actions',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
    });

    testWidgets('of a course not in the library: "Part of", and the '
        'episode\'s own Add to library', (tester) async {
      await _pump(tester);
      expect(
        find.textContaining('Part of Meditating with John Vervaeke'),
        findsOneWidget,
      );
      expect(_saveToggle, findsOneWidget);
      expect(find.byTooltip('Add to library'), findsOneWidget);
    });

    testWidgets('saved on its own inside a saved course: keeps its toggle, to '
        'take it out', (tester) async {
      await _pump(tester, saved: {_courseId, _trackId});
      expect(
        find.textContaining('In Meditating with John Vervaeke'),
        findsOneWidget,
      );
      expect(find.byTooltip('In library'), findsOneWidget);
    });

    testWidgets('the course line opens the course', (tester) async {
      await _pump(tester, saved: {_courseId});
      await tester.tap(find.byKey(const ValueKey('track_course')));
      await DharmaSeedTestApp.settle(tester);
      expect(find.byType(PackView), findsOneWidget);
    });

    testWidgets('in no course: the title whole, the subtitle, no course line', (
      tester,
    ) async {
      await _pump(tester, courseId: null);
      expect(
        find.text('Meditating with John Vervaeke: Day 7 - Topic 7'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('track_course')), findsNothing);
      expect(find.byKey(const ValueKey('track_teacher')), findsNothing);
      expect(find.text('John Vervaeke'), findsOneWidget);
      expect(_saveToggle, findsOneWidget);
    });

    testWidgets('the bottom bar is Back only', (tester) async {
      await _pump(tester, saved: {_courseId});
      final bar = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(bar.bottomNavigationBar, isA<SingleBackButtonActionBar>());
      // Share, Add to playlist and Pin are on the page, once each.
      expect(find.byIcon(Icons.playlist_add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    });

    testWidgets('its ⋮ leaves out what the page shows as buttons', (
      tester,
    ) async {
      await _pump(tester);
      final actions = await _sheetActions(tester);
      expect(actions, contains(ItemAction.markPlayed.name));
      for (final shown in TrackView.shownAsButtons) {
        expect(actions, isNot(contains(shown.name)), reason: shown.name);
      }
    });

    testWidgets('opened over its course\'s page, the course line goes back '
        'to it (through the router)', (tester) async {
      await _pump(
        tester,
        saved: {_courseId},
        page: Builder(
          builder: (context) => TextButton(
            onPressed: () => handleNavigation(TypeConstants.pack, [
              _courseId,
              '/packs/$_courseId',
            ], context),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await DharmaSeedTestApp.settle(tester);
      expect(find.byType(PackView), findsOneWidget);
      // The course page opens one of its sessions.
      unawaited(
        handleNavigation(
          TypeConstants.track,
          [_trackId, '/tracks/$_trackId'],
          tester.element(find.byType(PackView)),
          courseId: _courseId,
        ),
      );
      await DharmaSeedTestApp.settle(tester);
      final page = tester.widget<TrackView>(find.byType(TrackView));
      expect(page.openedOver, coursePageRouteName(_courseId));

      await tester.tap(find.byKey(const ValueKey('track_course')));
      await DharmaSeedTestApp.settle(tester);
      expect(find.byType(TrackView), findsNothing);
      // Back on the page it came from, not a second copy of it.
      expect(find.byType(PackView), findsOneWidget);
    });

    testWidgets('opened from elsewhere, the course line opens the course', (
      tester,
    ) async {
      await _pump(
        tester,
        saved: {_courseId},
        asRoute: true,
        page: const TrackView(trackId: _trackId, openedOver: '/packs/other'),
      );
      await tester.tap(find.byKey(const ValueKey('track_course')));
      await DharmaSeedTestApp.settle(tester);
      expect(find.byType(PackView), findsOneWidget);
      expect(find.byType(TrackView, skipOffstage: false), findsOneWidget);
    });

    testWidgets('with its Add to library hidden (course saved), its ⋮ '
        'keeps Add to library', (tester) async {
      await _pump(tester, saved: {_courseId});
      expect(_saveToggle, findsNothing);
      final actions = await _sheetActions(tester);
      expect(actions, contains(ItemAction.save.name));
    });

    testWidgets('taken out of its playlist: no course line, Add to library '
        'back, nothing to remove', (tester) async {
      await _pump(tester, saved: {_courseId});
      expect(find.byKey(const ValueKey('track_course')), findsOneWidget);
      // The course no longer lists it (its revision moved on).
      _listed = _course.copyWith(
        items: [
          for (final i in _course.items)
            if (i.id != _trackId) i,
        ],
      );
      ProviderScope.containerOf(
        tester.element(find.byType(TrackView)),
      ).invalidate(packProvider(packId: _courseId));
      await DharmaSeedTestApp.settle(tester);
      expect(find.byKey(const ValueKey('track_course')), findsNothing);
      expect(_saveToggle, findsOneWidget);
      expect(
        await _sheetActions(tester),
        isNot(contains(ItemAction.removeFromCourse.name)),
      );
    });

    testWidgets('an imported file has no Share', (tester) async {
      const imported = 'lib-track-metta';
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        const TrackView(trackId: imported),
        overrides: [
          tracksProvider(
            trackId: imported,
          ).overrideWith(() => _FakeTracks(_track().copyWith(id: imported))),
          episodeCourseIdProvider(imported).overrideWith((ref) async => null),
        ],
      );
      await DharmaSeedTestApp.settle(tester);
      expect(find.byKey(const ValueKey('track_actions')), findsOneWidget);
      expect(find.byKey(const ValueKey('course_share')), findsNothing);
    });

    testWidgets('the course line is a full tap target; its chevron never '
        'starts a line of its own', (tester) async {
      await _pump(
        tester,
        saved: {_courseId},
        page: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: const TrackView(trackId: _trackId),
          ),
        ),
      );
      tester.view.physicalSize = const Size(360, 1200);
      await DharmaSeedTestApp.settle(tester);
      final line = find.byKey(const ValueKey('track_course'));
      expect(tester.getSize(line).height, greaterThanOrEqualTo(48));
      RenderParagraph paragraph() => tester.renderObject<RenderParagraph>(
        find.descendant(of: line, matching: find.byType(RichText)).last,
      );
      // The test font's letters are all one width: a course name that fills
      // the first line exactly ("In IIIIIII Day"), so a breakable chevron
      // would fall to the next line alone.
      final letter = paragraph()
          .getOffsetForCaret(const TextPosition(offset: 1), Rect.zero)
          .dx;
      final perLine = (paragraph().size.width / letter).floor();
      final title = '${'I' * (perLine - 7)} Day';
      _listed = _course.copyWith(title: title);
      ProviderScope.containerOf(
        tester.element(find.byType(TrackView)),
      ).invalidate(packProvider(packId: _courseId));
      await DharmaSeedTestApp.settle(tester);
      final text = paragraph().text.toPlainText();
      expect(text, 'In $title$courseChevron');
      expect(text.length - courseChevron.length, perLine);
      final chevron = paragraph().getOffsetForCaret(
        TextPosition(offset: text.length - 1),
        Rect.zero,
      );
      // On the second line, after "Day": not at the start of a line.
      expect(chevron.dy, greaterThan(0));
      expect(chevron.dx, greaterThan(letter * 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long description opens folded, with Show more', (
      tester,
    ) async {
      final long = List.generate(
        30,
        (i) => 'Line ${i + 1} of a long YouTube description, with links.',
      ).join('\n');
      await _pump(tester, track: _track(description: long));
      expect(find.text('Show more'), findsOneWidget);
      final folded = tester
          .getSize(find.byKey(const ValueKey('track_description')))
          .height;

      await tester.ensureVisible(find.text('Show more'));
      await tester.tap(find.text('Show more'));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('Show less'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('track_description'))).height,
        greaterThan(folded * 2),
      );
    });

    testWidgets('the fold grows with the text size', (tester) async {
      final long = List.generate(
        30,
        (i) => 'Line ${i + 1} of a long YouTube description, with links.',
      ).join('\n');
      Future<double> folded(double scale) async {
        await _pump(
          tester,
          track: _track(description: long),
          page: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: TrackView(key: ValueKey(scale), trackId: _trackId),
            ),
          ),
        );
        return tester
            .getSize(find.byKey(const ValueKey('track_description')))
            .height;
      }

      final normal = await folded(1);
      final large = await folded(1.6);
      expect(large, greaterThan(normal * 1.3));
    });

    testWidgets('a short description shows whole', (tester) async {
      await _pump(
        tester,
        track: _track(description: 'Where the meaning crisis comes from.'),
      );
      expect(
        find.textContaining('Where the meaning crisis comes from.'),
        findsOneWidget,
      );
      expect(find.text('Show more'), findsNothing);
    });
  });
}
