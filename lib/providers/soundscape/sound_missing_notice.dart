import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The mixer left sounds out of what it is playing because they are not
/// downloaded (the sound pack). The app shows it once, with a way to fetch
/// them, so a mix is never silently thinner than the user expects.
@immutable
class SoundMissingNotice {
  const SoundMissingNotice(this.ids, {required this.nothingPlays});

  /// The sounds in the mix that are not on this phone.
  final Set<String> ids;

  /// None of the mix could play: it is silent until something downloads.
  final bool nothingPlays;
}

final soundMissingNoticeProvider =
    NotifierProvider<SoundMissingNoticeNotifier, SoundMissingNotice?>(
      SoundMissingNoticeNotifier.new,
    );

class SoundMissingNoticeNotifier extends Notifier<SoundMissingNotice?> {
  @override
  SoundMissingNotice? build() => null;

  void announce(Set<String> ids, {required bool nothingPlays}) =>
      state = SoundMissingNotice(ids, nothingPlays: nothingPlays);

  /// Shown (or no longer wanted): forget it, so the same sounds go
  /// unannounced until the next time they are left out.
  void clear() => state = null;
}
