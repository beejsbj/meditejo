import 'package:flutter/material.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/widgets/cards/card_tokens.dart';

/// A section's heading: Expressive's emphasized title, marked as a heading
/// for screen readers. [trailing] (a "See all", a count) sits at the end.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Semantics(
      header: true,
      child: Text(title, style: context.typography.emphasized.titleLarge),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(kCardGutter + 4, 0, kCardGutter, 12),
      child: trailing == null
          ? text
          : Row(
              children: [
                Expanded(child: text),
                trailing!,
              ],
            ),
    );
  }
}
