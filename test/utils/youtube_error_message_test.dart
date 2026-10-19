import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/utils/youtube_error_message.dart';

void main() {
  for (final locale in ['en', 'de', 'es']) {
    test('$locale preserves each error reason and playlist wording', () async {
      final l10n = await AppLocalizations.delegate.load(Locale(locale));
      final videos = <String>{};
      final playlists = <String>{};
      for (final reason in YoutubeFailureReason.values) {
        final error = YoutubeUnavailableError(reason: reason);
        final video = youtubeErrorMessage(l10n, error);
        final playlist = youtubeErrorMessage(l10n, error, playlist: true);
        expect(video, isNotEmpty);
        expect(playlist, isNotEmpty);
        if (reason != YoutubeFailureReason.rateLimited) {
          expect(video, isNot(playlist));
        }
        videos.add(video);
        playlists.add(playlist);
      }
      expect(videos, hasLength(YoutubeFailureReason.values.length));
      expect(playlists, hasLength(YoutubeFailureReason.values.length));
      expect(
        youtubeErrorMessage(
          l10n,
          const YoutubeUnavailableError(),
          playlist: true,
        ),
        contains(
          locale == 'es'
              ? 'lista de reproducción'
              : locale == 'de'
              ? 'Playlist'
              : 'playlist',
        ),
      );
    });
  }
}
