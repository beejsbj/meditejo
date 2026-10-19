import 'package:medito/exceptions/app_error.dart';
import 'package:medito/l10n/app_localizations.dart';

/// One mapping for playback, imports and playlist refresh. Native messages
/// never become user-facing text.
String youtubeErrorMessage(
  AppLocalizations l10n,
  YoutubeUnavailableError error, {
  bool playlist = false,
}) => switch (error.reason) {
  YoutubeFailureReason.offline =>
    playlist ? l10n.youtubePlaylistOffline : l10n.youtubeOffline,
  YoutubeFailureReason.unavailable =>
    playlist ? l10n.youtubePlaylistUnavailable : l10n.youtubeUnavailable,
  YoutubeFailureReason.ageRestricted =>
    playlist ? l10n.youtubePlaylistAgeRestricted : l10n.youtubeAgeRestricted,
  YoutubeFailureReason.private =>
    playlist ? l10n.youtubePlaylistPrivate : l10n.youtubePrivate,
  YoutubeFailureReason.rateLimited => l10n.youtubeRateLimited,
};
