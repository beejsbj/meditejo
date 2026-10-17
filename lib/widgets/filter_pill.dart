import 'package:flutter/material.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/utils/utils.dart';

/// A rounded toggle for filters (content kind, talk length): quiet when off,
/// the brand accent when on. Like [TagChip], but it keeps a selected state.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? context.brandAccent : theme.cardColor,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? context.brandAccent
                : theme.colorScheme.outline.withOpacityValue(0.3),
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: selected ? context.onBrandAccent : onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
