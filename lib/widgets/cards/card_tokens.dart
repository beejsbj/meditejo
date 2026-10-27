import 'package:medito/constants/theme/tokens.dart';

/// Radii and spacing of the shared cards, rows and strips, from the theme's
/// tokens. Home, the Library and Explore draw with these, so they read as one
/// surface.
const kCardRadius = MeditejoShapes.extraLarge;

/// Art inset in a card: the card's radius less the inset, so the corners are
/// concentric.
const kCardArtInset = 8.0;
const kCardInsetArtRadius = kCardRadius - kCardArtInset;

/// Art beside text (a row, a pinned card).
const kCardArtRadius = MeditejoShapes.large;
const kCardGutter = 16.0;
const kCardGap = 12.0;
