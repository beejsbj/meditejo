import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/views/home/widgets/bottom_sheet/row_item_widget.dart';
import 'package:medito/views/settings/palette_picker_view.dart';
import 'package:medito/widgets/branding/home_mark_sheet.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';

/// Settings › Appearance › Palette: the chosen palette (or "Daily", with
/// today's), opening [PalettePickerView].
class PaletteTile extends ConsumerWidget {
  const PaletteTile({super.key, this.hasUnderline = true});

  final bool hasUnderline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final active = ref.watch(activePaletteProvider);
    final choice = ref.watch(paletteChoiceProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return RowItemWidget(
      key: const ValueKey('settings_palette'),
      icon: Icon(Icons.palette_outlined, color: onSurface),
      title: l10n.paletteTitle,
      subTitle: switch (choice) {
        DailyPalette() => l10n.paletteDailyToday(active.name),
        FixedPalette() => active.name,
      },
      hasUnderline: hasUnderline,
      trailing: _Dots(palette: active),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PalettePickerView()),
      ),
    );
  }
}

/// Settings › Appearance › Home mark: today's or pinned, opening the pin
/// sheet.
class HomeMarkTile extends ConsumerWidget {
  const HomeMarkTile({super.key, this.hasUnderline = true});

  final bool hasUnderline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pinned = ref.watch(pinnedMarkProvider) != null;
    return RowItemWidget(
      key: const ValueKey('settings_home_mark'),
      icon: MeditejoMark(
        mark: ref.watch(homeMarkProvider),
        size: 28,
        still: true,
      ),
      title: l10n.homeMarkTitle,
      subTitle: pinned ? l10n.homeMarkPinned : l10n.homeMarkToday,
      hasUnderline: hasUnderline,
      onTap: () => showHomeMarkSheet(context),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.palette});

  final IdentityPalette palette;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final c in [palette.form, palette.stroke, palette.accent])
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(left: 3),
          decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle),
        ),
    ],
  );
}
