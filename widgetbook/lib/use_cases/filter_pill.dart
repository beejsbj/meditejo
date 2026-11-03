import 'package:flutter/material.dart';
import 'package:medito/widgets/filter_pill.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart';

@UseCase(name: 'Default', type: FilterPill)
Widget defaultFilterPill(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.all(24),
    child: Align(
      alignment: Alignment.centerLeft,
      child: FilterPill(
        label: context.knobs.string(label: 'Label', initialValue: 'Sleep'),
        selected: context.knobs.boolean(label: 'Selected', initialValue: false),
        onTap: () {},
      ),
    ),
  );
}

@UseCase(name: 'Wrapping row', type: FilterPill)
Widget rowOfFilterPills(BuildContext context) {
  const labels = ['Sleep', 'Stress', 'Breathing', 'Body scan', 'Focus'];
  return Padding(
    padding: const EdgeInsets.all(24),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final label in labels)
          FilterPill(label: label, selected: label == 'Sleep', onTap: () {}),
      ],
    ),
  );
}
