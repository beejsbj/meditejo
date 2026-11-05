import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/views/library/item_actions.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/views/pack/widgets/pack_path_button.dart';
import 'package:medito/views/player/widgets/bottom_actions/pin_action.dart';
import 'package:medito/widgets/add_to_siri_util.dart';
import 'package:medito/widgets/medito_icon.dart';
import 'package:medito/widgets/save_button.dart';
import 'package:share_plus/share_plus.dart';

/// The course page's actions (#81): a full-width filled Play / Resume that
/// names the next session, over a row of the toggles that keep the course
/// (Library, Pin), Share and ⋮. What used to sit in the bottom bar lives
/// here, with the course.
class CourseActionRow extends StatelessWidget {
  const CourseActionRow({super.key, required this.pack, this.playKey});

  final PackModel pack;

  /// Lets the page tell when the header's Play has scrolled away.
  final GlobalKey? playKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final playable = PackPlayButton.isPlayable(pack);
    final toggles = [
      // A playlist the user made lives in the library; it is edited (and
      // deleted from its editor), not unsaved.
      if (isMyCourseId(pack.id))
        RoundIconButton(
          key: const ValueKey('my_course_edit'),
          tooltip: l10n.myCourseEditAction,
          icon: Icons.edit_outlined,
          onPressed: () => openMyCourseEditor(context, pack.id),
        )
      else
        SaveIconButton(
          id: pack.id,
          label: l10n.courseSave,
          savedLabel: l10n.courseSaved,
        ),
      PinIconButton(id: pack.id),
      CourseShareButton(packId: pack.id, title: pack.title),
      CourseMoreButton(packId: pack.id, title: pack.title),
    ];
    // Play gets the full width, so the session's name has room; the
    // toggles sit in a row under it.
    final icons = Row(
      children: [
        for (final (i, toggle) in toggles.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          toggle,
        ],
      ],
    );
    if (!playable) return icons;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PackPlayButton(key: playKey, pack: pack),
        const SizedBox(height: 12),
        icons,
      ],
    );
  }
}

/// Shares a link to the course. On iOS it opens a small sheet that also
/// offers Add to Siri, as the bottom bar's Share did.
class CourseShareButton extends StatelessWidget {
  const CourseShareButton({
    super.key,
    required this.packId,
    required this.title,
  }) : _session = false;

  /// An episode page's Share (#84): the same button, for one session.
  const CourseShareButton.session({
    super.key,
    required String trackId,
    required this.title,
  }) : packId = trackId,
       _session = true;

  /// The course's ID, or the session's for [CourseShareButton.session].
  final String packId;
  final String title;
  final bool _session;

  String get _link =>
      'meditejo://meditejo/${_session ? 'tracks' : 'packs'}/$packId';

  void _share(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = _session
        ? l10n.shareTrackText(_link, title)
        : l10n.sharePackText(_link, title);
    SharePlus.instance.share(ShareParams(text: text));
  }

  void _showIosSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    showModalBottomSheet<void>(
      showDragHandle: true,
      context: context,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: MeditoIcon(
                assetName: MeditoIcons.siri,
                color: onSurface,
                size: 20,
              ),
              title: Text(l10n.addToSiri),
              onTap: () {
                addToSiri(title: '${l10n.open} $title', id: packId, url: _link);
                Navigator.pop(sheet);
              },
            ),
            ListTile(
              leading: MeditoIcon(
                assetName: MeditoIcons.shareIos,
                color: onSurface,
                size: 20,
              ),
              title: Text(l10n.share),
              onTap: () {
                _share(context);
                Navigator.pop(sheet);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ios = Platform.isIOS;
    return RoundIconButton(
      key: const ValueKey('course_share'),
      tooltip: AppLocalizations.of(context)!.share,
      iconWidget: MeditoIcon(
        assetName: ios ? MeditoIcons.shareIos : MeditoIcons.shareAndroid,
        color: Theme.of(context).colorScheme.onSurface,
        size: 20,
      ),
      onPressed: ios ? () => _showIosSheet(context) : () => _share(context),
    );
  }
}

/// ⋮: the one item-actions sheet (#83), the same a course row's ⋮ and
/// long-press open, less what the header already shows as buttons
/// ([shownAsButtons]). Rows, long-press and the Library keep them.
class CourseMoreButton extends ConsumerWidget {
  const CourseMoreButton({
    super.key,
    required this.packId,
    required this.title,
  });

  final String packId;
  final String title;

  /// The header's own buttons, not repeated in its ⋮: Play, Add to
  /// library (or, for a playlist the user made, Edit), Pin and Share.
  static const shownAsButtons = {
    ItemAction.play,
    ItemAction.save,
    ItemAction.edit,
    ItemAction.pin,
    ItemAction.share,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RoundIconButton(
      key: const ValueKey('pack_actions'),
      tooltip: AppLocalizations.of(context)!.myCourseMore,
      icon: Icons.more_vert_rounded,
      onPressed: () => showContentActionsSheet(
        context,
        ref,
        id: packId,
        title: title,
        hide: shownAsButtons,
      ),
    );
  }
}

/// A 44dp outlined round button, the shape [PinIconButton] and
/// [SaveIconButton] share, so a header's row reads as one set. The course
/// header and an episode's page (#84) use it.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.icon,
    this.iconWidget,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData? icon;
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return IconButton.outlined(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        side: BorderSide(color: onSurface.withValues(alpha: 0.3)),
      ),
      icon: iconWidget ?? Icon(icon, color: onSurface),
    );
  }
}
