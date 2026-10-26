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
          NavigationDestination(
            icon: item.iconFor(scheme.onSurfaceVariant, selected: false),
            selectedIcon: item.iconFor(
              scheme.onSecondaryContainer,
              selected: true,
            ),
            label: item.label,
          ),
      ],
    );
  }
}
