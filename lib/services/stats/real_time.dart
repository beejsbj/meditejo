/// When the stats mention the audio covered beside the time spent.
///
/// Time practised is real time: a 60-minute talk heard at 2x is 30 minutes of
/// it. The audio covered (recording lengths) is shown as a quiet second line
/// only when the two differ enough to be worth reading: by at least
/// [audioLineMinDifference] AND by at least [audioLineMinFraction] of the time
/// spent. One rule, so the You card and the stats page agree; change the two
/// constants to change where it shows.
library;

/// The smallest gap worth a line: the figures are shown to the minute, so a
/// smaller one would read "20 min of audio · 20 min of your time".
const audioLineMinDifference = Duration(minutes: 1);

/// The smallest gap, as a share of the time spent, worth a line: an hour of
/// practice with one talk nudged to 1.25x for a few minutes stays quiet.
const audioLineMinFraction = 0.05;

/// Whether [audio] covered and [real] time spent differ enough to show both.
bool audioDiffersFromRealTime({
  required Duration audio,
  required Duration real,
}) {
  final gap = (audio - real).abs();
  if (gap < audioLineMinDifference) return false;
  if (real <= Duration.zero) return true;
  return gap.inMilliseconds >= real.inMilliseconds * audioLineMinFraction;
}
