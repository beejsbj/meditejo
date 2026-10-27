import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/updates/update_check_policy.dart';

void main() {
  final now = DateTime.utc(2026, 10, 17, 12);

  test('the first launch checks', () {
    expect(isAutoCheckDue(lastCheckedAt: null, now: now), isTrue);
  });

  test('a check less than a day ago is not repeated', () {
    expect(
      isAutoCheckDue(
        lastCheckedAt: now.subtract(const Duration(hours: 23, minutes: 59)),
        now: now,
      ),
      isFalse,
    );
    expect(isAutoCheckDue(lastCheckedAt: now, now: now), isFalse);
  });

  test('a day later it is due again', () {
    expect(
      isAutoCheckDue(
        lastCheckedAt: now.subtract(const Duration(hours: 24)),
        now: now,
      ),
      isTrue,
    );
    expect(
      isAutoCheckDue(
        lastCheckedAt: now.subtract(const Duration(days: 9)),
        now: now,
      ),
      isTrue,
    );
  });

  test('a last check in the future (clock set back) counts as due', () {
    expect(
      isAutoCheckDue(lastCheckedAt: now.add(const Duration(days: 3)), now: now),
      isTrue,
    );
  });

  test('the interval can be changed', () {
    expect(
      isAutoCheckDue(
        lastCheckedAt: now.subtract(const Duration(hours: 2)),
        now: now,
        interval: const Duration(hours: 1),
      ),
      isTrue,
    );
  });
}
