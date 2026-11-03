import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/views/player/start_session.dart';
import 'package:medito/views/track/track_view.dart';

import '../../helpers/library_app.dart';

class _FakeTracks extends Tracks {
  _FakeTracks(this.track);
  final Track track;

  @override
  Future<Track> build({required String trackId}) async => track;
}

TrackAudioFile _file(String id, int minutes) =>
    TrackAudioFile(id: id, path: '$id.mp3', duration: minutes * 60000);

Track _track(List<TrackVoice> voices) => Track(
  id: 'tr',
  title: 'Metta',
  description: '',
  coverUrl: '',
  isPublished: true,
  hasBackgroundSound: false,
  voices: voices,
);

final _single = _track([
  TrackVoice(guideName: 'Ajahn Sucitto', audioFiles: [_file('only', 42)]),
]);

// Its own file: the player screen it opens leaves global state behind that
// would break a later test in the same isolate.
void main() {
  group('starting with a single option', () {
    testWidgets('startSession plays it at once, with no remembered choice', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      late WidgetRef captured;
      late BuildContext ctx;
      await app.pump(
        tester,
        Consumer(
          builder: (context, ref, _) {
            captured = ref;
            ctx = context;
            return const SizedBox();
          },
        ),
        overrides: [
          tracksProvider(
            trackId: 'tr',
          ).overrideWith(() => _FakeTracks(_single)),
        ],
      );
      unawaited(startSession(ctx, captured, trackId: 'tr', path: '/tracks/tr'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(captured.read(playerProvider)?.fileId, 'only');
      expect(find.byType(TrackView), findsNothing);
    });
  });
}
