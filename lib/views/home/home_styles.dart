import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/pressable_card.dart';
import 'package:medito/widgets/cards/section_title.dart';

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

/// A section's heading on Home: the shared [SectionTitle].
typedef HomeSectionTitle = SectionTitle;

/// Home's cards and tiles are the shared [PressableCard].
typedef HomePressable = PressableCard;
