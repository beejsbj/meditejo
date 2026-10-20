import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/soundscape/soundscape_engine.dart';

void main() {
  test('rapid timbre changes hold at most two sets of voices', () {
    // A drone alternating warm (6 voices) and bright (8), each change
    // within the 1.5 s crossfade of the last: the layer's voices plus the
    // set fading out never pass 16, and every overtaken set is released.
    final outgoing = OutgoingVoices<String>();
    var playing = [for (var i = 0; i < 6; i++) 'warm0-$i'];
    final released = <List<String>>[];
    for (var change = 1; change <= 20; change++) {
      final count = change.isOdd ? 8 : 6;
      final replaced = playing;
      playing = [for (var i = 0; i < count; i++) 'set$change-$i'];
      final overtaken = outgoing.begin(replaced);
      if (overtaken.isNotEmpty) released.add(overtaken);
      expect(
        playing.length + outgoing.current.length,
        lessThanOrEqualTo(16),
        reason: 'change $change',
      );
    }
    expect(released.length, 19, reason: 'all but the last set fading out');
    // The set the last change replaced (bright) fades out on its own.
    expect(outgoing.take(), hasLength(8));
    expect(outgoing.current, isEmpty);
  });

  test('a stop or a finished crossfade takes the set once', () {
    final outgoing = OutgoingVoices<int>();
    expect(outgoing.begin([1, 2]), isEmpty);
    expect(outgoing.take(), [1, 2]);
    expect(outgoing.take(), isEmpty, reason: 'never released twice');
  });
}
