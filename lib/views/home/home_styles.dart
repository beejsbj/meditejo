import 'package:flutter/material.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
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

/// A section's heading on Home: Expressive's emphasized title.
class HomeSectionTitle extends StatelessWidget {
  const HomeSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kHomeGutter + 4, 0, kHomeGutter, 12),
        child: Text(title, style: context.typography.emphasized.titleLarge),
      ),
    );
  }
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
