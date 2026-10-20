import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/views/background_sound/background_sound_view.dart';
import 'package:medito/views/library/import_view.dart';
import 'package:medito/views/timer/timer_view.dart';
import 'package:medito/widgets/medito_icon.dart';
import 'package:medito/widgets/section_header.dart';

/// One-tap starts: the timer, background sounds, and adding something.
class QuickLinksSection extends ConsumerWidget {
  const QuickLinksSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.homeQuickLinksTitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: padding16),
          child: Row(
            children: [
              Expanded(
                child: QuickLinkTile(
                  key: const ValueKey('quick_timer'),
                  icon: MeditoIcon(assetName: MeditoIcons.timer, color: onSurface, size: 28),
                  label: l10n.timerTitle,
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const TimerView()),
                  ),
                ),
              ),
              const SizedBox(width: padding12),
              Expanded(
                child: QuickLinkTile(
                  key: const ValueKey('quick_sounds'),
                  icon: MeditoIcon(assetName: MeditoIcons.musicNote, color: onSurface, size: 28),
                  label: l10n.backgroundSoundsSection,
                  onTap: () => showBackgroundSoundSheet(context),
                ),
              ),
              const SizedBox(width: padding12),
              Expanded(
                child: QuickLinkTile(
                  key: const ValueKey('quick_add'),
                  icon: Icon(Icons.add_rounded, color: onSurface, size: 28),
                  label: l10n.homeQuickAdd,
                  onTap: () => openImport(context, ref),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class QuickLinkTile extends StatelessWidget {
  const QuickLinkTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: padding16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: padding8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
