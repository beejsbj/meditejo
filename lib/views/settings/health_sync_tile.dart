import 'dart:io';

import 'package:flutter/material.dart';
import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/utils/health_kit_manager.dart';

import '../../widgets/snackbar_widget.dart';
import '../../l10n/app_localizations.dart';
import '../home/widgets/bottom_sheet/row_item_widget.dart';
import '../../widgets/medito_icon.dart';

class HealthSyncTile extends StatefulWidget {
  const HealthSyncTile({super.key, this.hasUnderline = true, this.manager});

  final bool hasUnderline;

  final HealthKitManager? manager;

  @override
  State<HealthSyncTile> createState() => _HealthSyncTileState();
}

class _HealthSyncTileState extends State<HealthSyncTile> {
  late final HealthKitManager _manager = widget.manager ?? HealthKitManager();
  bool _enabled = false;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _manager.isSyncEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _busy = false;
    });
  }

  Future<void> _handleHealthSync(bool enabled) async {
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;

    if (enabled &&
        Platform.isAndroid &&
        !await _manager.isHealthConnectAvailable()) {
      await _manager.installHealthConnect();
      await _manager.setSyncEnabled(false);
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _busy = false;
      });
      showSnackBar(context, l10n.healthConnectNotInstalled);
      return;
    }

    final granted = await _manager.setSyncEnabled(enabled);
    if (!mounted) return;
    setState(() {
      _enabled = granted;
      _busy = false;
    });
    if (enabled && !granted) {
      showSnackBar(context, l10n.healthSyncPermissionDenied);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = Platform.isAndroid
        ? l10n.syncWithHealthConnect
        : l10n.syncWithHealth;
    return RowItemWidget(
      icon: MeditoIcon(
        assetName: MeditoIcons.health,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      title: title,
      hasUnderline: widget.hasUnderline,
      isSwitch: true,
      switchValue: _enabled,
      onSwitchChanged: _busy ? null : _handleHealthSync,
      onTap: _busy ? null : () => _handleHealthSync(!_enabled),
    );
  }
}
