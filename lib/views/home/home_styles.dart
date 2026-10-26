import 'package:flutter/material.dart';
import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/pressable_card.dart';

/// Radii and spacing shared by Home's sections: the cards' own (see
/// `card_tokens.dart`), so Home, the Library and Explore read as one surface.
const kHomeCardRadius = kCardRadius;
const kHomeTileRadius = kCardRadius;
const kHomeArtRadius = kCardArtRadius;
const kHomeGutter = kCardGutter;
const kHomeGap = kCardGap;
const kHomeSectionGap = 28.0;

/// The logo mark's size at the top of Home.
const kHomeMarkSize = 168.0;

/// A section's heading on Home, for screen readers only: nothing is drawn.
/// Sections are told apart by spacing and grouping alone (Waking Up's tiles
/// sit straight under its hero), but TalkBack still announces each group and
/// lets the user jump heading to heading. Android sets a node's heading flag
/// only for a positive [Semantics.headingLevel], and screen readers tend to
/// skip a node with no area, so the label has a level and a 1 dp strip.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    headingLevel: 2,
    label: title,
    child: const SizedBox(width: double.infinity, height: 1),
  );
}

/// Home's cards and tiles are the shared [PressableCard].
typedef HomePressable = PressableCard;
