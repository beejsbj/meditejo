import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import 'package:share_plus/share_plus.dart';

import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../models/pack/pack_model.dart';
import '../../../../widgets/add_to_siri_util.dart';
import '../../../../widgets/medito_icon.dart';
import 'bottom_action_bar.dart';
import 'pin_action.dart';

class PackViewBottomBar extends ConsumerStatefulWidget {
  final String packId;
  final String packName;
  final VoidCallback onBackPressed;

  const PackViewBottomBar({
    super.key,
    required this.packId,
    required this.packName,
    required this.onBackPressed,
  });

  @override
  ConsumerState<PackViewBottomBar> createState() => _PackViewBottomBarState();
}

class _PackViewBottomBarState extends ConsumerState<PackViewBottomBar> {
  void _sharePack(BuildContext context) {
    final deepLink = 'meditejo://meditejo/packs/${widget.packId}';
    final shareText = AppLocalizations.of(
      context,
    )!.sharePackText(deepLink, widget.packName);
    SharePlus.instance.share(ShareParams(text: shareText));
  }

  void _showBottomSheet(BuildContext context) {
    showModalBottomSheet(
      showDragHandle: true,
      context: context,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (Platform.isIOS)
              _buildBottomSheetTile(
                context,
                iconAsset: MeditoIcons.siri,
                title: AppLocalizations.of(context)!.addToSiri,
                onTap: () {
                  addToSiri(
                    title:
                        '${AppLocalizations.of(context)!.open} ${widget.packName}',
                    id: widget.packId,
                    url: 'meditejo://meditejo/packs/${widget.packId}',
                  );
                  Navigator.pop(context);
                },
              ),
            _buildBottomSheetTile(
              context,
              iconAsset: Platform.isIOS
                  ? MeditoIcons.shareIos
                  : MeditoIcons.shareAndroid,
              title: AppLocalizations.of(context)!.share,
              onTap: () {
                _sharePack(context);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  ListTile _buildBottomSheetTile(
    BuildContext context, {
    required String iconAsset,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: MeditoIcon(
        assetName: iconAsset,
        color: Theme.of(context).colorScheme.onSurface,
        size: 20,
      ),
      title: Text(
        title,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final packData = ref.watch(packProvider(packId: widget.packId));

    return packData.when(
      data: (pack) => _buildBottomBar(context, pack),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildBottomBar(BuildContext context, PackModel pack) {
    final l10n = AppLocalizations.of(context)!;

    return BottomActionBar(
      layout: BottomActionBarLayout.compactRight,
      leftItem: BottomActionBarItem(
        child: MeditoIcon(
          assetName: MeditoIcons.arrowLeft,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        onTap: widget.onBackPressed,
        semanticLabel: l10n.goBack,
      ),
      rightCenterItem: BottomActionBarItem(
        child: MeditoIcon(
          assetName: Platform.isIOS
              ? MeditoIcons.shareIos
              : MeditoIcons.shareAndroid,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        onTap: Platform.isIOS
            ? () => _showBottomSheet(context)
            : () => _sharePack(context),
        semanticLabel: l10n.share,
      ),
      // Add to course…, Make my own copy; Edit and Delete for the user's own.
      leftCenterItem: BottomActionBarItem(
        child: Icon(
          Icons.more_vert_rounded,
          key: const ValueKey('pack_actions'),
          color: Theme.of(context).colorScheme.onSurface,
        ),
        onTap: () => showContentActionsSheet(
          context,
          ref,
          id: widget.packId,
          title: widget.packName,
        ),
        semanticLabel: l10n.myCourseMore,
      ),
      rightItem: pinActionItem(context, ref, widget.packId),
    );
  }
}
