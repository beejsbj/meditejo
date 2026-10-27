import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/soundscape/sound_pack_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/views/home/widgets/bottom_sheet/row_item_widget.dart';
import 'package:medito/views/soundscape/sound_pack_widgets.dart';

/// Settings › Library & downloads: how much of the sound pack is on the
/// phone, and Delete to free it. The sounds stay in the library, and the
/// mixer says which of a mix's sounds need downloading again.
class SoundPackTile extends ConsumerWidget {
  const SoundPackTile({super.key, this.hasUnderline = true});

  final bool hasUnderline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final library = ref.watch(soundLibraryProvider).value;
    final pack = ref.watch(soundPackProvider);
    final sounds = library?.packSounds ?? const [];
    // A library with nothing to download has nothing to manage.
    if (sounds.isEmpty) return const SizedBox.shrink();
    final total = sounds.fold<int>(0, (n, s) => n + s.bytes);
    final have = pack.downloaded.length;
    return RowItemWidget(
      key: const ValueKey('settings_sound_pack'),
      icon: Icon(
        Symbols.cloud_download_rounded,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      title: l10n.settingsSoundPackTitle,
      subTitle: have == 0
          ? l10n.settingsSoundPackNone(soundSizeLabel(context, total))
          : l10n.settingsSoundPackSummary(
              have,
              sounds.length,
              soundSizeLabel(context, pack.usedBytes),
            ),
      hasUnderline: hasUnderline,
      isTrailingIcon: false,
      trailing: have == 0 && !pack.busy
          ? null
          : TextButton(
              key: const ValueKey('settings_sound_pack_delete'),
              onPressed: () => _confirmDelete(context, ref),
              child: Text(l10n.settingsSoundPackDelete),
            ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final size = soundSizeLabel(context, ref.read(soundPackProvider).usedBytes);
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsSoundPackDeleteTitle),
        content: Text(l10n.settingsSoundPackDeleteBody(size)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.soundsCancel),
          ),
          TextButton(
            key: const ValueKey('settings_sound_pack_delete_confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.settingsSoundPackDelete),
          ),
        ],
      ),
    );
    if (delete == true) {
      await ref.read(soundPackProvider.notifier).deleteAll();
    }
  }
}

/// Settings › Library & downloads: sound downloads wait for Wi-Fi (on by
/// default). "Download anyway" on the Sounds screen overrides it once.
class SoundPackWifiTile extends ConsumerWidget {
  const SoundPackWifiTile({super.key, this.hasUnderline = true});

  final bool hasUnderline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final library = ref.watch(soundLibraryProvider).value;
    if (library == null || library.packSounds.isEmpty) {
      return const SizedBox.shrink();
    }
    final wifiOnly = ref.watch(soundPackProvider.select((s) => s.wifiOnly));
    return RowItemWidget(
      key: const ValueKey('settings_sound_pack_wifi'),
      icon: Icon(
        Symbols.wifi_rounded,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      title: l10n.settingsSoundPackWifiOnly,
      // Only true while the setting is on.
      subTitle: wifiOnly ? l10n.settingsSoundPackWifiOnlyHint : null,
      hasUnderline: hasUnderline,
      isSwitch: true,
      switchValue: wifiOnly,
      onSwitchChanged: (value) =>
          ref.read(soundPackProvider.notifier).setWifiOnly(value),
      onTap: () => ref.read(soundPackProvider.notifier).setWifiOnly(!wifiOnly),
    );
  }
}
