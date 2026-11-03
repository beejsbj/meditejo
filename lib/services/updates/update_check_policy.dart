/// The launch check runs at most once a day; "Check for updates" is always
/// allowed.
const kAutoCheckInterval = Duration(hours: 24);

/// Whether a check on launch is due. A last check that lies in the future (the
/// clock was set back) counts as due, so a bad clock cannot silence updates.
bool isAutoCheckDue({
  required DateTime? lastCheckedAt,
  required DateTime now,
  Duration interval = kAutoCheckInterval,
}) {
  if (lastCheckedAt == null) return true;
  if (lastCheckedAt.isAfter(now)) return true;
  return now.difference(lastCheckedAt) >= interval;
}

/// Whether the app may ask GitHub for a release on launch. Off by the
/// "Check for updates automatically" switch: nothing is requested, whatever
/// the interval or a new build says. "Check for updates" stays a manual path.
bool shouldCheckOnLaunch({
  required bool autoCheckEnabled,
  required bool buildChanged,
  required DateTime? lastCheckedAt,
  required DateTime now,
  Duration interval = kAutoCheckInterval,
}) {
  if (!autoCheckEnabled) return false;
  return buildChanged ||
      isAutoCheckDue(
        lastCheckedAt: lastCheckedAt,
        now: now,
        interval: interval,
      );
}
