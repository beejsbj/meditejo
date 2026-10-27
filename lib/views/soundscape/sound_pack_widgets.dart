import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/providers/soundscape/sound_missing_notice.dart';
import 'package:medito/providers/soundscape/sound_pack_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/scaffold_messenger_key.dart';
import 'package:medito/services/soundscape/sound_pack_service.dart';

/// "0.6 MB": a download's size the way a person reads it.
String soundSizeLabel(BuildContext context, int bytes) {
  final locale = Localizations.localeOf(context).toString();
  final mb = bytes / 1000000;
  return '${NumberFormat(mb < 10 ? '0.0' : '0', locale).format(mb)} MB';
}

String soundFailureLabel(
  AppLocalizations l10n,
  SoundDownloadFailure? failure,
) => switch (failure) {
  SoundDownloadFailure.server => l10n.soundPackFailureServer,
  SoundDownloadFailure.integrity => l10n.soundPackFailureIntegrity,
  SoundDownloadFailure.storage => l10n.soundPackFailureStorage,
  SoundDownloadFailure.network || null => l10n.soundPackFailureNetwork,
};

/// What a sound that is not on the phone offers: to be fetched, or how that
/// is going.
enum SoundOfferPhase { download, queued, downloading, failed }

@immutable
class SoundOffer {
  const SoundOffer(this.phase, this.sound, {this.progress, this.failure});

  final SoundOfferPhase phase;
  final SoundEntry sound;
  final double? progress;
  final SoundDownloadFailure? failure;

  /// The offer for [sound], or null when it can play already.
  static SoundOffer? of(SoundEntry? sound, SoundPackState pack) {
    if (sound == null || pack.isAvailable(sound)) return null;
    final download = pack.downloadOf(sound.id);
    if (download == null) return SoundOffer(SoundOfferPhase.download, sound);
    return switch (download.phase) {
      SoundDownloadPhase.queued => SoundOffer(SoundOfferPhase.queued, sound),
      SoundDownloadPhase.downloading => SoundOffer(
        SoundOfferPhase.downloading,
        sound,
        progress: download.progress,
      ),
      SoundDownloadPhase.failed => SoundOffer(
        SoundOfferPhase.failed,
        sound,
        failure: download.failure,
      ),
    };
  }

  /// What a tap does: fetch it, stop fetching it, or try again.
  void act(WidgetRef ref) {
    final pack = ref.read(soundPackProvider.notifier);
    switch (phase) {
      case SoundOfferPhase.download:
        pack.download([sound.id]);
      case SoundOfferPhase.queued:
      case SoundOfferPhase.downloading:
        pack.cancel(sound.id);
      case SoundOfferPhase.failed:
        pack.retry(ids: [sound.id]);
    }
  }

  String semanticsLabel(BuildContext context, String title) {
    final l10n = AppLocalizations.of(context)!;
    return switch (phase) {
      SoundOfferPhase.download => l10n.soundPackDownloadSound(
        title,
        soundSizeLabel(context, sound.bytes),
      ),
      SoundOfferPhase.queued ||
      SoundOfferPhase.downloading => l10n.soundPackCancelDownload(title),
      SoundOfferPhase.failed => l10n.soundPackRetryDownload(title),
    };
  }
}

/// The corner of a sound card that is not on the phone: its size and a
/// download arrow, a ring while it arrives, or a retry when it did not.
class SoundOfferBadge extends StatelessWidget {
  const SoundOfferBadge(this.offer, {super.key});

  final SoundOffer offer;

  @override
  Widget build(BuildContext context) {
    const onArt = Colors.white;
    final scheme = Theme.of(context).colorScheme;
    final disc = Colors.black.withValues(alpha: 0.32);
    return switch (offer.phase) {
      SoundOfferPhase.download => DecoratedBox(
        decoration: BoxDecoration(
          color: disc,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: onArt.withValues(alpha: 0.7)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 7, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Symbols.download_rounded, size: 16, color: onArt),
              const SizedBox(width: 2),
              Text(
                soundSizeLabel(context, offer.sound.bytes),
                style: context.typography.baseline.labelSmall?.copyWith(
                  color: onArt,
                ),
              ),
            ],
          ),
        ),
      ),
      SoundOfferPhase.queued || SoundOfferPhase.downloading => DecoratedBox(
        decoration: BoxDecoration(color: disc, shape: BoxShape.circle),
        child: SizedBox.square(
          dimension: 26,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  // A queued sound has not started: a still, empty ring.
                  value: offer.phase == SoundOfferPhase.queued
                      ? 0
                      : offer.progress,
                  strokeWidth: 2.5,
                  color: onArt,
                  backgroundColor: onArt.withValues(alpha: 0.3),
                ),
              ),
              const Icon(Symbols.close_rounded, size: 11, color: onArt),
            ],
          ),
        ),
      ),
      SoundOfferPhase.failed => DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            Symbols.refresh_rounded,
            size: 18,
            weight: 600,
            color: scheme.onErrorContainer,
          ),
        ),
      ),
    };
  }
}

/// On the Sounds screen: what is left to download, with Download all, then
/// progress with Cancel, what is waiting for Wi-Fi with Download anyway, and
/// what failed with Retry. Hidden when every sound is on the phone.
class SoundPackBanner extends ConsumerWidget {
  const SoundPackBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final library = ref.watch(soundLibraryProvider).value;
    final pack = ref.watch(soundPackProvider);
    if (library == null || !pack.scanned) return const SizedBox.shrink();
    final remaining = [
      for (final s in library.packSounds)
        if (!pack.downloaded.contains(s.id)) s,
    ];
    if (remaining.isEmpty && pack.downloads.isEmpty) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(soundPackProvider.notifier);
    final inFlight = pack.downloads.values.where((d) => d.inFlight).length;
    final failedOnes = pack.downloads.values.where((d) => !d.inFlight).length;

    final String title;
    final String body;
    final IconData icon;
    final List<Widget> actions;
    double? progress;
    if (pack.waitingForWifi && inFlight > 0) {
      title = l10n.soundPackWaitingForWifi;
      body = l10n.soundPackWifiOnlyHint;
      icon = Symbols.wifi_rounded;
      actions = [
        TextButton(
          key: const ValueKey('pack_cancel'),
          onPressed: controller.cancelAll,
          child: Text(l10n.soundPackCancel),
        ),
        FilledButton.tonal(
          key: const ValueKey('pack_anyway'),
          onPressed: () => controller.download([
            for (final e in pack.downloads.entries)
              if (e.value.inFlight) e.key,
          ], anyNetwork: true),
          child: Text(l10n.soundPackDownloadAnyway),
        ),
      ];
    } else if (inFlight > 0) {
      final done = pack.batchDone;
      final total = pack.batchTotal;
      title = l10n.soundPackDownloading(
        (done + 1).clamp(1, total < 1 ? 1 : total),
        total < 1 ? 1 : total,
      );
      body = remaining.isEmpty
          ? ''
          : l10n.soundPackMoreBody(
              remaining.length,
              soundSizeLabel(
                context,
                remaining.fold<int>(0, (n, s) => n + s.bytes),
              ),
            );
      icon = Symbols.cloud_download_rounded;
      final current = pack.downloads.values
          .where((d) => d.phase == SoundDownloadPhase.downloading)
          .firstOrNull;
      progress = total < 1 ? null : (done + (current?.progress ?? 0)) / total;
      actions = [
        TextButton(
          key: const ValueKey('pack_cancel'),
          onPressed: controller.cancelAll,
          child: Text(l10n.soundPackCancel),
        ),
      ];
    } else if (failedOnes > 0) {
      title = l10n.soundPackFailedCount(failedOnes);
      body = soundFailureLabel(
        l10n,
        pack.downloads.values.firstWhere((d) => !d.inFlight).failure,
      );
      icon = Symbols.error_rounded;
      actions = [
        TextButton(
          key: const ValueKey('pack_cancel'),
          onPressed: controller.cancelAll,
          child: Text(l10n.soundPackCancel),
        ),
        FilledButton.tonal(
          key: const ValueKey('pack_retry'),
          onPressed: () => controller.retry(),
          child: Text(l10n.soundPackRetry),
        ),
      ];
    } else {
      title = l10n.soundPackMoreTitle;
      body = l10n.soundPackMoreBody(
        remaining.length,
        soundSizeLabel(context, remaining.fold<int>(0, (n, s) => n + s.bytes)),
      );
      icon = Symbols.cloud_download_rounded;
      actions = [
        FilledButton.tonal(
          key: const ValueKey('pack_download_all'),
          onPressed: () => controller.downloadAll(),
          child: Text(l10n.soundPackDownloadAll),
        ),
      ];
    }

    return Padding(
      key: const ValueKey('sound_pack_banner'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: MeditejoShapes.rounded(MeditejoShapes.extraLarge),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    color: failedOnes > 0 && inFlight == 0
                        ? scheme.error
                        : scheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: type.emphasized.titleMedium),
                        if (body.isNotEmpty)
                          Text(
                            body,
                            style: type.baseline.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (inFlight > 0 && !pack.waitingForWifi) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: LinearProgressIndicator(
                    key: const ValueKey('pack_progress'),
                    value: progress,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 8, children: actions),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A mix layer whose sound is not on the phone says so, and offers it. Null
/// when the sound can play.
class MissingSoundLine extends ConsumerWidget {
  const MissingSoundLine({
    super.key,
    required this.soundId,
    required this.title,
  });

  final String soundId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(soundLibraryProvider).value;
    final pack = ref.watch(soundPackProvider);
    final offer = SoundOffer.of(library?[soundId], pack);
    if (offer == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final failed = offer.phase == SoundOfferPhase.failed;
    final working =
        offer.phase == SoundOfferPhase.queued ||
        offer.phase == SoundOfferPhase.downloading;
    final action = switch (offer.phase) {
      SoundOfferPhase.download => l10n.soundPackDownload,
      SoundOfferPhase.queued ||
      SoundOfferPhase.downloading => l10n.soundPackCancel,
      SoundOfferPhase.failed => l10n.soundPackRetry,
    };
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              failed
                  ? soundFailureLabel(l10n, offer.failure)
                  : l10n.soundPackNeedsDownload(
                      soundSizeLabel(context, offer.sound.bytes),
                    ),
              style: type.baseline.bodySmall?.copyWith(
                color: failed ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (working)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  value: offer.phase == SoundOfferPhase.queued
                      ? 0
                      : offer.progress,
                  strokeWidth: 2,
                ),
              ),
            ),
          TextButton(
            key: ValueKey('layer_download_$soundId'),
            onPressed: () => offer.act(ref),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

/// Mounted once above the app's pages: when the mixer leaves sounds out of
/// what it plays because they are not downloaded, says which, and offers to
/// fetch them. Silence is never unexplained.
class SoundMissingListener extends ConsumerWidget {
  const SoundMissingListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(soundMissingNoticeProvider, (_, notice) {
      if (notice == null) return;
      final messenger = scaffoldMessengerKey.currentState;
      final localizations = _localizations();
      if (messenger == null || localizations == null) return;
      ref.read(soundMissingNoticeProvider.notifier).clear();
      final library = ref.read(soundLibraryProvider).value;
      final names = [
        for (final id in notice.ids) library?[id]?.title ?? id,
      ].join(', ');
      final l10n = localizations;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          key: const ValueKey('sound_missing_snackbar'),
          duration: const Duration(seconds: 8),
          content: Text(
            notice.nothingPlays
                ? l10n.soundPackMissingAll(names, notice.ids.length)
                : l10n.soundPackMissingPartial(names, notice.ids.length),
          ),
          action: SnackBarAction(
            label: l10n.soundPackDownload,
            onPressed: () => _download(ref, notice.ids),
          ),
        ),
      );
    });
    return child;
  }

  /// Fetches [ids]; if the phone is on mobile data and downloads wait for
  /// Wi-Fi, says so rather than leave the tap looking ignored.
  Future<void> _download(WidgetRef ref, Set<String> ids) async {
    final pack = ref.read(soundPackProvider.notifier);
    await pack.download(ids);
    // Give the queue a moment to find out which network it is on.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final messenger = scaffoldMessengerKey.currentState;
    final l10n = _localizations();
    if (messenger == null || l10n == null) return;
    if (!ref.read(soundPackProvider).waitingForWifi) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.soundPackWaitingForWifi),
        action: SnackBarAction(
          label: l10n.soundPackDownloadAnyway,
          onPressed: () => pack.download(ids, anyNetwork: true),
        ),
      ),
    );
  }

  /// The app's strings, from the messenger's own context (this widget sits
  /// above the Navigator, where a Localizations ancestor may not be).
  AppLocalizations? _localizations() {
    final context = scaffoldMessengerKey.currentContext;
    return context == null ? null : AppLocalizations.of(context);
  }
}
