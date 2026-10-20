import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/utils/utils.dart';

/// Who recorded each bundled sound, under which licence, and what was
/// changed. Built from `assets/sounds/sounds.json`, the same data as
/// `assets/sounds/NOTICE`. CC BY sounds are marked as requiring attribution;
/// CC0 and public-domain credits are given as thanks.
class SoundCreditsView extends ConsumerWidget {
  const SoundCreditsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final library = ref.watch(soundLibraryProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.soundsCredits)),
      body: library == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + padding24,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(padding16),
                  child: Text(
                    l10n.soundCreditsIntro,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                for (final sound in library.sounds) _CreditTile(sound: sound),
              ],
            ),
    );
  }
}

class _CreditTile extends StatelessWidget {
  const _CreditTile({required this.sound});

  final SoundEntry sound;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final license = sound.license;
    return Padding(
      key: ValueKey('credit_${sound.id}'),
      padding: const EdgeInsets.fromLTRB(
        padding16,
        padding8,
        padding16,
        padding8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sound.title,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.soundCreditsBy(
              sound.originalTitle.isEmpty ? sound.title : sound.originalTitle,
              sound.author,
            ),
            style: theme.textTheme.bodyMedium,
          ),
          Wrap(
            spacing: padding8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Link(label: license.label, url: license.url),
              if (sound.sourceUrl.isNotEmpty)
                _Link(
                  label: Uri.parse(sound.sourceUrl).host,
                  url: sound.sourceUrl,
                ),
              if (license.requiresAttribution)
                Text(
                  l10n.soundCreditsAttributionRequired,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
          if (sound.modifications.isNotEmpty)
            Text(
              l10n.soundCreditsChanges(sound.modifications),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Text(label, style: Theme.of(context).textTheme.bodySmall);
    }
    return TextButton(
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => launchURLInBrowser(url),
      child: Text(label),
    );
  }
}
