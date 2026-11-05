import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/views/you/you_view.dart';

/// The person button at the top right of Home, Library and Settings. It opens
/// the You page (stats, session history, pins) over the tabs.
///
/// The same 48 dp button in the same place on all three: the rightmost
/// control of the header, 4 dp in from the edge and 4 dp down from the top of
/// the safe area, as an app bar's last action sits.
class YouButton extends StatelessWidget {
  const YouButton({super.key});

  /// From the right edge and from the top of the safe area.
  static const inset = 4.0;

  static void open(BuildContext context) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const YouView()));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The label is the button's own, so a screen reader says it once; the
    // tooltip is only for sight.
    return Tooltip(
      message: l10n.youButton,
      excludeFromSemantics: true,
      child: IconButton(
        key: const ValueKey('you_button'),
        icon: Icon(
          Symbols.account_circle_rounded,
          semanticLabel: l10n.youButton,
        ),
        onPressed: () => open(context),
      ),
    );
  }
}
