import 'package:flutter/material.dart';
import 'package:medito/constants/theme/tokens.dart';

/// Radii and spacing shared by Home's sections, from the theme's tokens, so
/// the cards, tiles and pins read as one surface.
const kHomeCardRadius = MeditejoShapes.extraLarge;
const kHomeTileRadius = MeditejoShapes.extraLarge;
const kHomeArtRadius = MeditejoShapes.large;
const kHomeGutter = 16.0;
const kHomeGap = 12.0;
const kHomeSectionGap = 28.0;

/// The logo mark's size at the top of Home.
const kHomeMarkSize = 168.0;

/// A section's heading on Home, for screen readers only: nothing is drawn.
/// Sections are told apart by spacing and grouping alone (Waking Up's tiles
/// sit straight under its hero), but TalkBack still announces each group and
/// lets the user jump heading to heading.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    label: title,
    child: const SizedBox(width: double.infinity),
  );
}

/// A tappable surface that settles back with Expressive's spring when
/// pressed: it dips to 96% under the finger. Still with reduced motion.
class HomePressable extends StatefulWidget {
  const HomePressable({
    super.key,
    required this.color,
    required this.radius,
    required this.onTap,
    required this.child,
  });

  final Color color;
  final double radius;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<HomePressable> createState() => _HomePressableState();
}

class _HomePressableState extends State<HomePressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    const motion = MeditejoMotion.expressiveFastSpatial;
    final shape = MeditejoShapes.rounded(widget.radius);
    return AnimatedScale(
      scale: _pressed && !still ? 0.96 : 1,
      duration: still ? Duration.zero : motion.duration,
      curve: motion.curve,
      child: Material(
        color: widget.color,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: shape,
          onTap: widget.onTap,
          onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
          child: widget.child,
        ),
      ),
    );
  }
}
