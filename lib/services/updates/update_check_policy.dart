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
