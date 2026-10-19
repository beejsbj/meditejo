import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
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
  Timer? _retryTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // No connectivity plugin is needed: only an empty, visible course polls,
    // and attempts share the source's single in-flight refresh.
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if ((ModalRoute.of(context)?.isCurrent ?? true) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_retry());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      unawaited(_retry());
    }
  }

  Future<void> _retry() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(youtubeSourceProvider).refresh(widget.packId);
    } finally {
      if (mounted) setState(() => _refreshing = false);
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
