import 'package:flutter/material.dart';
import 'package:medito/l10n/app_localizations.dart';

/// One thing a card's menu offers.
class CardAction {
  const CardAction({
    required this.key,
    required this.icon,
    required this.label,
    required this.onSelected,
  });

  final Key key;
  final IconData icon;
  final String label;
  final VoidCallback onSelected;
}

/// Opens [actions] in a bottom sheet, headed by [title]. Holding a card and
/// its ⋮ both open this, so the two always agree. The sheet closes before
/// the action runs, so an action may navigate or show a snackbar.
Future<void> showCardActions(
  BuildContext context, {
  required String title,
  required List<CardAction> actions,
}) async {
  final chosen = await showModalBottomSheet<CardAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(sheet).textTheme.titleMedium,
            ),
          ),
          for (final action in actions)
            ListTile(
              key: action.key,
              leading: Icon(action.icon),
              title: Text(action.label),
              onTap: () => Navigator.of(sheet).pop(action),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  chosen?.onSelected();
}

/// The ⋮ on a card: the same actions as holding it, for those who do not
/// know to hold, and for screen readers.
class CardMenuButton extends StatelessWidget {
  const CardMenuButton({
    super.key,
    required this.title,
    required this.actions,
    this.color,
  });

  final String title;
  final List<CardAction> actions;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: AppLocalizations.of(context)!.homeCardMenu,
      visualDensity: VisualDensity.compact,
      color: color,
      onPressed: () => showCardActions(context, title: title, actions: actions),
      icon: const Icon(Icons.more_vert_rounded),
    );
  }
}
