import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/views/home/widgets/bottom_sheet/row_item_widget.dart';
import 'package:medito/widgets/medito_icon.dart';

/// Asks the phone whether Meditejo is still held back
/// ([shouldShowBatteryOptimizationScreen]). Tests stand in for it.
final batteryGuidanceCheckProvider = Provider<Future<bool> Function()>(
  (_) => shouldShowBatteryOptimizationScreen,
);

/// Whether this phone is one known to stop apps in the background and
/// Meditejo is still held back by it.
///
/// Read again every time the app comes back to the foreground, while anything
/// watches it: the change is made in the phone's settings, outside the app,
/// and Settings stays alive underneath, so nothing else would re-read it.
final batteryGuidanceNeededProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final listener = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(listener.dispose);
  try {
    return await ref.read(batteryGuidanceCheckProvider)();
  } catch (_) {
    // Device-specific guidance is optional.
    return false;
  }
});

/// Asks to let Meditejo run in the background, on phones known to stop apps
/// (Samsung and others) and only while it is still held back. Lived in
/// Medito's onboarding until #87; it is now a Settings row under Reminders
/// ([BatteryGuidanceTile]) and nothing else: the app never opens it by
/// itself (it was once offered after the first reminder was turned on).
///
/// It closes itself once the phone lets Meditejo run. Coming back without
/// that change (or from the plugin's own dialog, which also pauses and
/// resumes the app) leaves it open, with Done instead of Not now.
class BatteryOptimizationScreen extends ConsumerStatefulWidget {
  const BatteryOptimizationScreen({super.key});

  @override
  ConsumerState<BatteryOptimizationScreen> createState() =>
      _BatteryOptimizationScreenState();
}

class _BatteryOptimizationScreenState
    extends ConsumerState<BatteryOptimizationScreen> {
  bool _isProcessing = false;
  bool _openedSettings = false;

  Future<void> _handleOptimize() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isProcessing = true;
      _openedSettings = true;
    });

    try {
      // The plugin shows its own dialogs before the phone's settings.
      await DisableBatteryOptimization.showDisableAllOptimizationsSettings(
        l10n.batteryAutoStartTitle,
        l10n.batteryAutoStartBody,
        l10n.batteryManufacturerTitle,
        l10n.batteryManufacturerBody,
      );
    } catch (_) {
      // No settings to open on this phone: nothing more this page can do.
      if (mounted) Navigator.of(context).maybePop();
    }

    if (mounted) setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    // Done once the phone lets Meditejo run: re-read on every return to
    // the app (see [batteryGuidanceNeededProvider]).
    ref.listen(batteryGuidanceNeededProvider, (_, next) {
      // Once only, and only this page: a second answer during the exit
      // animation must not pop the page underneath.
      if (_openedSettings &&
          next.value == false &&
          ModalRoute.of(context)?.isCurrent == true) {
        _openedSettings = false;
        Navigator.of(context).maybePop();
      }
    });

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MeditoIcon(
                          assetName: MeditoIcons.alert,
                          size: 40,
                          color: scheme.onSurface,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          l10n.batteryGuidanceTitle,
                          style: type.emphasized.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.batteryGuidanceBody,
                          style: type.baseline.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        key: const ValueKey('battery_open'),
                        onPressed: _isProcessing ? null : _handleOptimize,
                        child: Text(l10n.batteryGuidanceOpen),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const ValueKey('battery_not_now'),
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: Text(
                          _openedSettings ? l10n.endScreenDone : l10n.notNow,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Settings row for [BatteryOptimizationScreen]. Shows only on phones
/// that need it, and goes once Meditejo is let run.
class BatteryGuidanceTile extends ConsumerWidget {
  const BatteryGuidanceTile({super.key, this.hasUnderline = false});

  final bool hasUnderline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return RowItemWidget(
      key: const ValueKey('settings_battery'),
      icon: MeditoIcon(
        assetName: MeditoIcons.alert,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      title: l10n.batteryGuidanceTitle,
      subTitle: l10n.batteryGuidanceRow,
      hasUnderline: hasUnderline,
      onTap: () async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const BatteryOptimizationScreen()),
        );
        if (context.mounted) ref.invalidate(batteryGuidanceNeededProvider);
      },
    );
  }
}

// OEMs known for aggressive battery optimization.
const _affectedManufacturers = {
  'huawei',
  'xiaomi',
  'oneplus',
  'samsung',
  'meizu',
  'asus',
  'wiko',
  'lenovo',
  'oppo',
  'vivo',
  'realme',
  'motorola',
  'blackview',
  'tecno',
  'sony',
  'unihertz',
};

// Specific models to exclude even when their manufacturer is in the list above.
const _excludedModels = {
  'nexus 6p', // Huawei-built but stock Android
};

/// Returns true on devices from OEMs known for aggressive battery optimization
/// where optimization is NOT already disabled. Excludes known stock-Android
/// models (e.g. Nexus 6P) and Xiaomi Android One devices.
Future<bool> shouldShowBatteryOptimizationScreen() async {
  if (kIsWeb || !Platform.isAndroid) return false;

  final info = await DeviceInfoPlugin().androidInfo;
  final manufacturer = info.manufacturer.toLowerCase();

  if (!_affectedManufacturers.any((m) => manufacturer.contains(m))) {
    return false;
  }

  // Xiaomi Android One devices run stock Android — skip them.
  if (manufacturer.contains('xiaomi') &&
      info.brand.toLowerCase().contains('android one')) {
    return false;
  }

  final model = info.model.toLowerCase();
  if (_excludedModels.any((m) => model.contains(m))) {
    return false;
  }

  final alreadyDisabled =
      await DisableBatteryOptimization.isAllBatteryOptimizationDisabled;
  return alreadyDisabled != true;
}
