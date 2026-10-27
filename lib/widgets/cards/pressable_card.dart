import 'package:flutter/material.dart';
import 'package:medito/constants/theme/tokens.dart';

/// A tappable surface that settles back with Expressive's spring when
/// pressed: it dips to 96% under the finger. Still with reduced motion.
/// Home's cards and tiles, and the Library's and Explore's cards, are all
/// drawn on it.
class PressableCard extends StatefulWidget {
  const PressableCard({
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
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
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
