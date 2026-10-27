import 'package:flutter/material.dart';
import 'package:medito/widgets/cards/card_tokens.dart';

/// One choice in a [FilterChipBar].
@immutable
class FilterOption<T> {
  const FilterOption(this.value, this.label, {this.key});

  final T value;
  final String label;
  final Key? key;
}

/// A row of single-choice chips that scrolls sideways when it does not fit:
/// the Library's kinds, Explore's Practice and Talks, search's talk lengths.
/// With [allowDeselect], tapping the chosen chip again clears the choice
/// (null).
class FilterChipBar<T> extends StatelessWidget {
  const FilterChipBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.allowDeselect = false,
    this.semanticsLabel,
    this.padding = const EdgeInsets.symmetric(horizontal: kCardGutter),
  });

  final List<FilterOption<T>> options;
  final T? selected;
  final ValueChanged<T?> onSelected;
  final bool allowDeselect;
  final String? semanticsLabel;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (final (i, option) in options.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              ChoiceChip(
                key: option.key,
                label: Text(option.label),
                selected: option.value == selected,
                onSelected: (_) => onSelected(
                  option.value == selected && allowDeselect
                      ? null
                      : option.value,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
