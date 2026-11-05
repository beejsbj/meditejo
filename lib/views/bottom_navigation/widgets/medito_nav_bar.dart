import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MeditoNavItem {
  const MeditoNavItem({required this.icon, required this.label});

  /// A Material Symbols glyph (`Symbols.*_rounded`). It is drawn outlined,
  /// and filled when its tab is selected, as Material 3 asks.
  final IconData icon;
  final String label;

  Widget iconFor(Color color, {required bool selected, double size = 24}) =>
      Icon(icon, color: color, size: size, fill: selected ? 1 : 0);
}

/// The phone's tab bar: Material's navigation bar, styled by the theme
/// (`navigationBarTheme`): a tonal bar, a pill behind the selected icon and
/// labels always shown.
class MeditoNavBar extends StatelessWidget {
  const MeditoNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<MeditoNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) {
        HapticFeedback.selectionClick();
        onSelected(i);
      },
      destinations: [
        for (final item in items)
          _OneLineLabel(
            label: item.label,
            child: NavigationDestination(
              icon: item.iconFor(scheme.onSurfaceVariant, selected: false),
              selectedIcon: item.iconFor(
                scheme.onSecondaryContainer,
                selected: true,
              ),
              label: item.label,
            ),
          ),
      ],
    );
  }
}

/// Keeps a tab's label on one line: a label wider than its slot (a long
/// translation, a narrow phone, large text) is set smaller instead of
/// breaking mid-word. The bar draws the label itself, so this shrinks the
/// text scale under it rather than wrapping the text.
class _OneLineLabel extends StatelessWidget {
  const _OneLineLabel({required this.label, required this.child});

  final String label;
  final Widget child;

  /// Breathing room either side of the label inside its slot.
  static const _margin = 4.0;

  /// The bar caps its labels' text scale at this (Material's own limit).
  static const _maxScale = 1.3;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final room = constraints.maxWidth - 2 * _margin;
      final scaler = MediaQuery.textScalerOf(
        context,
      ).clamp(maxScaleFactor: _maxScale);
      final styles = NavigationBarTheme.of(context).labelTextStyle;
      final fallback = Theme.of(context).textTheme.labelMedium;
      // Selected labels may be bolder: fit the wider of the two.
      var widest = 0.0;
      for (final states in [
        <WidgetState>{},
        {WidgetState.selected},
      ]) {
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: styles?.resolve(states) ?? fallback,
          ),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        if (painter.width > widest) widest = painter.width;
        painter.dispose();
      }
      final fitted = DefaultTextStyle.merge(
        maxLines: 1,
        softWrap: false,
        child: child,
      );
      if (!room.isFinite || widest <= room) return fitted;
      final scale = scaler.scale(1) * room / widest;
      return MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: fitted,
      );
    },
  );
}
