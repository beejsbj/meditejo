import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/utils/youtube_error_message.dart';

/// Only mounted while an opened playlist has no stored sessions. Retrying
/// here keeps Home's local reads free of timers and network dependencies.
class YoutubePlaylistEmpty extends ConsumerStatefulWidget {
  const YoutubePlaylistEmpty({super.key, required this.packId});

  final String packId;

  @override
  ConsumerState<YoutubePlaylistEmpty> createState() =>
      _YoutubePlaylistEmptyState();
}

class _YoutubePlaylistEmptyState extends ConsumerState<YoutubePlaylistEmpty>
    with WidgetsBindingObserver {
  static const _maxBackoffTicks = 16; // 16 x 30 s = 8 minutes

  Timer? _retryTimer;
  bool _refreshing = false;
  int _rateLimitedStreak = 0;
  int _skipTicks = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // No connectivity plugin is needed: only an empty, visible course polls,
    // and attempts share the source's single in-flight refresh.
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_skipTicks > 0) {
        _skipTicks--;
        return;
      }
      if ((ModalRoute.of(context)?.isCurrent ?? true) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_retry(automatic: true));
      }
    });
  }

  /// Only an offline failure is worth asking about again on a timer: it is
  /// cheap and ends the moment connectivity returns. A rate limit backs off
  /// (30 s, 1, 2, 4 and at most 8 minutes) so YouTube is not poked while it
  /// asks the app to slow down, and a private, age-restricted or removed
  /// playlist will not change on its own, so only the Retry button asks.
  bool get _mayRetryAutomatically {
    final reason = ref
        .read(youtubeSourceProvider)
        .refreshError(widget.packId)
        ?.reason;
    return switch (reason) {
      null || YoutubeFailureReason.offline => true,
      YoutubeFailureReason.rateLimited => _skipTicks == 0,
      YoutubeFailureReason.unavailable ||
      YoutubeFailureReason.ageRestricted ||
      YoutubeFailureReason.private => false,
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      unawaited(_retry(automatic: true));
    }
  }

  Future<void> _retry({bool automatic = false}) async {
    if (_refreshing || (automatic && !_mayRetryAutomatically)) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(youtubeSourceProvider).refresh(widget.packId);
    } on YoutubeUnavailableError {
      // A concurrent pull-to-refresh can throw; the source records its state.
    } finally {
      _scheduleBackoff();
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _scheduleBackoff() {
    final reason = ref
        .read(youtubeSourceProvider)
        .refreshError(widget.packId)
        ?.reason;
    if (reason == YoutubeFailureReason.rateLimited) {
      _rateLimitedStreak++;
      _skipTicks =
          math.min(1 << (_rateLimitedStreak - 1), _maxBackoffTicks) - 1;
    } else {
      _rateLimitedStreak = 0;
      _skipTicks = 0;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final error = ref.watch(youtubeRefreshErrorProvider(widget.packId));
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            error == null
                ? l10n.youtubePlaylistEmpty
                : youtubeErrorMessage(l10n, error, playlist: true),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _refreshing ? null : _retry,
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }
}
