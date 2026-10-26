import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medito/widgets/medito_icon.dart';

class MeditoNavItem {
  const MeditoNavItem({required this.icon, required this.label});

  /// SVG asset name, see [MeditoIcons].
  final String icon;
  final String label;
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
            icon: MeditoIcon(
              assetName: item.icon,
              color: scheme.onSurfaceVariant,
              size: 24,
            ),
            selectedIcon: MeditoIcon(
              assetName: item.icon,
              color: scheme.onSecondaryContainer,
              size: 24,
            ),
            label: item.label,
          ),
      ],
    );
  }
}
