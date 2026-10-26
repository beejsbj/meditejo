import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/services/stats/session_label.dart';

void main() {
  setUp(SessionLabelRegistry.clear);

  test('a timer is Practice with no course', () async {
    final label = await labelSessionCompletion('timer-600');
    expect(label.kind, LocalAudioCompleted.kindPractice);
    expect(label.courseId, isNull);
  });

  test('without a running app it uses what the player registered', () async {
    SessionLabelRegistry.remember(
      'ds-talk-1',
      kind: 'talks',
      courseId: 'ds-retreat-1',
    );
    final label = await labelSessionCompletion('ds-talk-1');
    expect(label.kind, 'talks');
    expect(label.courseId, 'ds-retreat-1');
  });

  test('and is unknown for a session it was never told about', () async {
    expect(await labelSessionCompletion('ds-talk-2'), SessionLabel.unknown);
  });

  test('the registry keeps only the latest sessions', () {
    for (var i = 0; i < 40; i++) {
      SessionLabelRegistry.remember('t$i', kind: 'practice');
    }
    expect(SessionLabelRegistry.recall('t0'), isNull);
    expect(SessionLabelRegistry.recall('t39')?.kind, 'practice');
  });
}
