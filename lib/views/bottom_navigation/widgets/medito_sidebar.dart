import 'package:flutter/material.dart';
import 'medito_nav_bar.dart';

/// The same destinations as the phone bar, as Material's navigation rail,
/// extended with labels beside the icons on the widest windows. It scrolls
/// when large text makes it taller than the window.
class MeditoSidebar extends StatelessWidget {
  const MeditoSidebar({
    super.key,
    required this.extended,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final bool extended;
  final List<MeditoNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rail = NavigationRail(
      extended: extended,
      minExtendedWidth: 200,
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      groupAlignment: -0.9,
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      destinations: [
        for (final item in items)
          NavigationRailDestination(
            icon: item.iconFor(scheme.onSurfaceVariant, selected: false),
            selectedIcon: item.iconFor(
              scheme.onSecondaryContainer,
              selected: true,
            ),
            label: Text(item.label),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: rail),
        ),
      ),
    );
  }
}
