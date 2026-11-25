import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/providers/providers.dart';
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

// Its own file: opening the player leaves Riverpod state behind that would
// break a later test in the same file.
void main() {
  testWidgets('choosing a length is saved, and Play uses that file', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await app.pump(
      tester,
      const TrackView(trackId: 'tr'),
      overrides: [
        tracksProvider(trackId: 'tr').overrideWith(
          () => _FakeTracks(
            _track([
              TrackVoice(
                guideName: 'Ajahn Sucitto',
                audioFiles: [_file('a10', 10), _file('a20', 20)],
              ),
            ]),
          ),
        ),
      ],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TrackView)),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '20 min'));
    await tester.pump();
    expect(app.prefs.getInt('meditation_duration_preference'), 20 * 60000);

    await tester.tap(find.byKey(const ValueKey('track_play')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.read(playerProvider)?.fileId, 'a20');
  });
}
