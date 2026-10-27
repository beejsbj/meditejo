import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/updates/update_providers.dart';
import 'package:medito/providers/updates/update_state.dart';
import 'package:medito/src/audio_pigeon.g.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/views/debug/debug_info_screen.dart';
import 'package:medito/views/downloads/downloads_view.dart';
import 'package:medito/views/favorites/favorites_view.dart';
import 'package:medito/views/home/customise_home_layout_screen.dart';
import 'package:medito/views/home/widgets/bottom_sheet/row_item_widget.dart';
import 'package:medito/views/library/import_view.dart';
import 'package:medito/views/onboarding/onboarding_pager_screen.dart';
import 'package:medito/views/settings/health_sync_tile.dart';
import 'package:medito/views/settings/widgets/add_widget_sheet.dart';
import 'package:medito/views/settings/widgets/app_icon_tile.dart';
import 'package:medito/views/settings/widgets/dharma_seed_sync_tile.dart';
import 'package:medito/views/settings/widgets/dnd_setting_tile.dart';
import 'package:medito/views/settings/widgets/identity_tiles.dart';
import 'package:medito/views/settings/widgets/practice_default_tiles.dart';
import 'package:medito/views/settings/widgets/reminder_tile.dart';
import 'package:medito/views/settings/widgets/sound_pack_tiles.dart';
import 'package:medito/views/settings/widgets/theme_tile.dart';
import 'package:medito/views/settings/widgets/update_section.dart';
import 'package:medito/views/settings/widgets/widget_option_tile.dart';
import 'package:medito/views/settings/widgets/zen_mode_tile.dart';
import 'package:medito/views/soundscape/sound_credits_view.dart';
import 'package:medito/views/stats/stats_screen.dart';
import 'package:medito/widgets/medito_icon.dart';

/// Where a row in a settings group is built: told whether it is the last, so
/// it can drop its underline.
typedef SettingsRow = Widget Function(bool last);

/// Every setting, grouped by what a person is trying to do: Practice, Sounds
/// & cues, Library & downloads, Appearance, Notifications & reminders, and
/// About, which holds the version and Check for updates.
///
/// Not a screen: [SettingsScreen] and the You tab put it in their own scroll
/// views. When an update is waiting, About moves to the top.
class SettingsSections extends ConsumerWidget {
  const SettingsSections({super.key, this.isMobile, this.isAndroid});

  /// Which platform's rows to show; null reads the platform. Set by tests,
  /// which run on the desktop.
  final bool? isMobile, isAndroid;

  // `kIsWeb` guards let the sections render in the web-based widget previewer
  // (see previews/settings_previews.dart) where dart:io Platform throws.
  bool get _isMobile =>
      isMobile ?? (!kIsWeb && (Platform.isIOS || Platform.isAndroid));
  bool get _isDndSupported => isAndroid ?? (!kIsWeb && Platform.isAndroid);

  static void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));

  bool get _isAndroid => _isDndSupported;

  Future<void> _addWidget(BuildContext context) async {
    if (!_isAndroid) {
      await showAddWidgetSheet(context);
      return;
    }
    try {
      await MeditoWidgetManager().pinWidget('consistency');
    } catch (e) {
      // Silently fail - Android system dialog handles user interaction
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final update = ref.watch(updateControllerProvider);
    final updateWaiting =
        ref.watch(updatesSupportedProvider) &&
        update.release != null &&
        update.phase != UpdatePhase.idle &&
        update.phase != UpdatePhase.upToDate &&
        update.phase != UpdatePhase.checking;

    final about = SettingsGroup(
      key: const ValueKey('settings_about'),
      title: l10n.settingsSectionAbout,
      children: const [_AboutHeader(), UpdateSection(), _AboutLinks()],
    );

    final groups = <Widget>[
      if (updateWaiting) about,
      SettingsGroup.rows(
        key: const ValueKey('settings_practice'),
        title: l10n.settingsSectionPractice,
        rows: [
          (last) => DefaultGuideTile(hasUnderline: !last),
          (last) => DefaultLengthTile(hasUnderline: !last),
          (last) => DayStartTile(hasUnderline: !last),
          if (_isDndSupported)
            (last) => DndSettingTile(
              icon: MeditoIcon(assetName: MeditoIcons.moon, color: onSurface),
              title: l10n.enableDndDuringMeditation,
              hasUnderline: !last,
            ),
          (last) => ZenModeTile(
            icon: MeditoIcon(assetName: MeditoIcons.sun, color: onSurface),
            title: l10n.zenMode,
            hasUnderline: !last,
          ),
          if (_isMobile) (last) => HealthSyncTile(hasUnderline: !last),
          (last) => RowItemWidget(
            key: const ValueKey('settings_edit_stats'),
            icon: MeditoIcon(assetName: MeditoIcons.graphUp, color: onSurface),
            title: l10n.editStatsTitle,
            hasUnderline: !last,
            onTap: () => _push(context, const StatsScreen(initialTabIndex: 1)),
          ),
        ],
      ),
      SettingsGroup.rows(
        key: const ValueKey('settings_sounds'),
        title: l10n.settingsSectionSounds,
        rows: [
          (last) =>
              CueDefaultsTile(kind: CueKind.practice, hasUnderline: !last),
          (last) => CueDefaultsTile(kind: CueKind.talks, hasUnderline: !last),
        ],
      ),
      SettingsGroup.rows(
        key: const ValueKey('settings_library'),
        title: l10n.settingsSectionLibrary,
        rows: [
          (last) => RowItemWidget(
            key: const ValueKey('settings_import'),
            icon: Icon(Icons.add_link_rounded, color: onSurface),
            title: l10n.importTitle,
            hasUnderline: !last,
            onTap: () => _push(context, const ImportView()),
          ),
          (last) => RowItemWidget(
            icon: MeditoIcon(assetName: MeditoIcons.heart, color: onSurface),
            title: l10n.favorites,
            hasUnderline: !last,
            onTap: () => _push(context, const FavoritesView()),
          ),
          (last) => RowItemWidget(
            icon: MeditoIcon(
              assetName: MeditoIcons.downloadCircle,
              color: onSurface,
            ),
            title: l10n.downloads,
            hasUnderline: !last,
            onTap: () => _push(context, const DownloadsView()),
          ),
          (last) => DharmaSeedSyncTile(hasUnderline: !last),
          (last) => SoundPackTile(hasUnderline: !last),
          (last) => SoundPackWifiTile(hasUnderline: !last),
        ],
      ),
      SettingsGroup.rows(
        key: const ValueKey('settings_appearance'),
        title: l10n.settingsSectionAppearance,
        rows: [
          (last) => ThemeTile(
            icon: MeditoIcon(assetName: MeditoIcons.settings, color: onSurface),
            title: l10n.themeTitle,
            hasUnderline: !last,
          ),
          (last) => PaletteTile(hasUnderline: !last),
          (last) => HomeMarkTile(hasUnderline: !last),
          (last) => AppIconTile(
            icon: _AppIconGlyph(color: onSurface),
            title: l10n.appIconTitle,
            hasUnderline: !last,
          ),
          (last) => RowItemWidget(
            icon: MeditoIcon(assetName: MeditoIcons.pencil, color: onSurface),
            title: l10n.customiseHomeLayout,
            hasUnderline: !last,
            onTap: () => _push(context, const CustomiseHomeLayoutScreen()),
          ),
          if (_isMobile)
            (last) => WidgetOptionTile(
              icon: MeditoIcon(assetName: MeditoIcons.home, color: onSurface),
              title: l10n.addHomeScreenWidget,
              hasUnderline: !last,
              onTap: () => _addWidget(context),
            ),
        ],
      ),
      SettingsGroup.rows(
        key: const ValueKey('settings_reminders'),
        title: l10n.settingsSectionReminders,
        rows: [(last) => ReminderTile(hasUnderline: !last)],
      ),
      if (!updateWaiting) about,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, group) in groups.indexed) ...[
          if (i > 0) const SizedBox(height: 24),
          group,
        ],
      ],
    );
  }
}

/// A settings group: its name in the primary colour, and its rows on one
/// tonal 28 dp surface.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children});

  SettingsGroup.rows({
    super.key,
    required this.title,
    required List<SettingsRow> rows,
  }) : children = [
         for (final (i, row) in rows.indexed) row(i == rows.length - 1),
       ];

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
            child: Text(
              title,
              style: context.typography.emphasized.titleSmall?.copyWith(
                color: scheme.primary,
              ),
            ),
          ),
        ),
        Material(
          color: scheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          shape: MeditejoShapes.rounded(MeditejoShapes.extraLarge),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _AppIconGlyph extends StatelessWidget {
  const _AppIconGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      border: Border.all(color: color, width: 1.5),
      borderRadius: BorderRadius.circular(6),
    ),
    padding: const EdgeInsets.all(3),
    child: SvgPicture.asset(
      AssetConstants.icLogo,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    ),
  );
}

/// The app and the build installed. Check for updates sits directly under it.
class _AboutHeader extends ConsumerWidget {
  const _AboutHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final type = context.typography;
    final scheme = Theme.of(context).colorScheme;
    final installed = ref.watch(installedBuildProvider).value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(MeditejoShapes.medium),
            child: Image.asset(
              'assets/images/app_icons/meditejo.png',
              width: 48,
              height: 48,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Meditejo', style: type.emphasized.titleMedium),
                if (installed != null)
                  Text(
                    l10n.aboutVersion(
                      installed.versionName,
                      '${installed.versionCode}',
                    ),
                    key: const ValueKey('about_version'),
                    style: type.baseline.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Source, credits, licences and the AGPL notice.
class _AboutLinks extends StatelessWidget {
  const _AboutLinks();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final onSurface = scheme.onSurface;
    return Column(
      children: [
        Divider(
          height: 1,
          indent: 16,
          endIndent: 16,
          color: scheme.outlineVariant,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            '${l10n.settingsAgplNotice}\n\n${l10n.forkCredit}',
            key: const ValueKey('about_agpl'),
            style: type.baseline.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        RowItemWidget(
          key: const ValueKey('about_source'),
          icon: Icon(Icons.code_rounded, color: onSurface),
          title: l10n.sourceCode,
          subTitle: 'github.com/beejsbj/meditejo',
          isTrailingIcon: false,
          trailing: Icon(Icons.open_in_new_rounded, size: 20, color: onSurface),
          onTap: () =>
              launchURLInBrowser('https://github.com/beejsbj/meditejo'),
        ),
        RowItemWidget(
          key: const ValueKey('about_upstream'),
          icon: Icon(Icons.favorite_border_rounded, color: onSurface),
          title: l10n.upstreamProject,
          subTitle: 'Medito Foundation',
          isTrailingIcon: false,
          trailing: Icon(Icons.open_in_new_rounded, size: 20, color: onSurface),
          onTap: () => launchURLInBrowser('https://meditofoundation.org'),
        ),
        RowItemWidget(
          key: const ValueKey('about_sound_credits'),
          icon: Icon(Icons.graphic_eq_rounded, color: onSurface),
          title: l10n.settingsSoundCredits,
          onTap: () =>
              SettingsSections._push(context, const SoundCreditsView()),
        ),
        RowItemWidget(
          key: const ValueKey('about_licenses'),
          icon: Icon(Icons.description_outlined, color: onSurface),
          title: l10n.settingsLicenses,
          onTap: () =>
              showLicensePage(context: context, applicationName: 'Meditejo'),
        ),
        RowItemWidget(
          key: const ValueKey('about_debug'),
          icon: Icon(Icons.bug_report_outlined, color: onSurface),
          title: l10n.debugInfo,
          // Setup replay is a development aid.
          hasUnderline: kDebugMode,
          onTap: () => SettingsSections._push(context, const DebugInfoScreen()),
        ),
        if (kDebugMode)
          RowItemWidget(
            icon: MeditoIcon(
              assetName: MeditoIcons.arrowRight,
              color: onSurface,
            ),
            title: l10n.onboarding,
            hasUnderline: false,
            onTap: () =>
                SettingsSections._push(context, const OnboardingPagerScreen()),
          ),
      ],
    );
  }
}
