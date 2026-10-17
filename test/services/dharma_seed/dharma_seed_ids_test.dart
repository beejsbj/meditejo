import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';

void main() {
  test('IDs round-trip', () {
    expect(parseDsTalkId(dsTalkId(16)), 16);
    expect(parseDsRetreatId(dsRetreatId(6689)), 6689);
    expect(parseDsTeacherId(dsTeacherId(210)), 210);
  });

  test('only canonical digits parse, and only for their own kind', () {
    for (final bad in [
      'ds-talk-0x10',
      'ds-talk-+16',
      'ds-talk--16',
      'ds-talk- 16',
      'ds-talk-16 ',
      'ds-talk-16\n',
      'ds-talk-',
      'ds-talk-1_6',
      'ds-retreat-16',
      'lib-16',
    ]) {
      expect(parseDsTalkId(bad), isNull, reason: bad);
    }
  });
}
