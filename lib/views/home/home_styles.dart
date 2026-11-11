import 'package:flutter/material.dart';
import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/pressable_card.dart';

/// Radii and spacing shared by Home's sections: the cards' own (see
/// `card_tokens.dart`), so Home, the Library and Explore read as one surface.
const kHomeCardRadius = kCardRadius;
const kHomeTileRadius = kCardRadius;
const kHomeArtRadius = kCardArtRadius;

/// Home is roomier than the lists it borrows its cards from: wider gutters,
/// and more air between cards, tiles and sections.
const kHomeGutter = 20.0;
const kHomeGap = 14.0;

/// Between two cards of one section (Continue, Pinned).
const kHomeRowGap = 10.0;
const kHomeSectionGap = 40.0;

/// The mark's block at the top of Home, as shares of the screen's height:
/// up to [kHomeMarkMaxShare] when little is below it, and never under
/// [kHomeMarkMinShare]. Within it the mark is a square, as large as fits.
const kHomeMarkMaxShare = 0.46;
const kHomeMarkMinShare = 0.28;

/// Above the mark, and the largest the mark is drawn (a tablet).
const kHomeMarkTop = 12.0;
const kHomeMarkMaxSize = 440.0;

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
