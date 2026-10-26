import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:medito/services/identity/palettes.dart';

/// Meditejo's design tokens, Material 3 Expressive, in one place. The theme
/// (`app_theme.dart`) and new screens read these; change a value here and
/// everything built on it follows. Where Flutter has the token natively it is
/// used as is; the rest are thin local equivalents, noted on each.
///
/// See docs/fork/DECISIONS.md (2026-10-26, design pass PR 1) for why each
/// value was chosen.
abstract final class MeditejoColorTokens {
  /// The palette the app starts with (decision 21: Tidewater). Every colour
  /// role grows from the active identity palette
  /// (`services/identity/palettes.dart`), which the user can change in
  /// Settings › Appearance, or let the date choose. See `palette_theme.dart`
  /// for how a palette maps onto the scheme.
  static const defaultPalette = IdentityPalettes.defaultId;

  /// The scheme variant the palette's form colour grows its ramps with:
  /// Material's neutral variant, low chroma. The palettes are already
  /// tuned (Tidewater's fog, Sumi's paper); tonal spot lifts every seed to
  /// the same chroma, which turned Sumi gold and Tidewater cyan. With
  /// neutral, the containers are quiet tints of the palette and the mark
  /// stays the most colourful thing on screen. See DECISIONS.md, identity
  /// PR 1, for the comparison.
  static const variant = DynamicSchemeVariant.neutral;

  /// The tertiary roles grow from the palette's accent with tonal spot, so
  /// the palette's one float of colour (Tidewater's coral) stays alive.
  static const accentVariant = DynamicSchemeVariant.tonalSpot;

  /// Dynamic colour (Material You, the wallpaper's palette) is off: the mark
  /// and the art are tuned against the identity palettes, and it needs the
  /// `dynamic_color` plugin.
  static const dynamicColor = false;
}

/// M3 Expressive's corner scale (m3.material.io, shape › corner radius
/// scale). Flutter has no shape-scale token type, so these are local.
abstract final class MeditejoShapes {
  static const none = 0.0;
  static const extraSmall = 4.0;
  static const small = 8.0;
  static const medium = 12.0;
  static const large = 16.0;
  static const largeIncreased = 20.0;
  static const extraLarge = 28.0;
  static const extraLargeIncreased = 32.0;
  static const extraExtraLarge = 48.0;

  /// Fully rounded (pills, circles).
  static const full = 1000.0;

  static BorderRadius radius(double r) => BorderRadius.circular(r);

  static RoundedRectangleBorder rounded(double r) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

  static const stadium = StadiumBorder();
}

/// One motion token: a spring, plus a duration and curve that approximate it
/// for widgets that take `Duration` + `Curve` (implicit animations, route
/// transitions).
class MotionToken {
  const MotionToken._(this.dampingRatio, this.stiffness);

  final double dampingRatio;
  final double stiffness;

  /// The spring itself, for physics-driven animations
  /// (`AnimationController.animateWith(SpringSimulation(...))`). Native.
  SpringDescription get spring => SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: stiffness,
    ratio: dampingRatio,
  );

  /// How long the spring takes to settle within 0.1% of its travel.
  Duration get duration {
    final sim = SpringSimulation(spring, 0, 1, 0);
    var t = 0.0;
    var settledSince = 0.0;
    const step = 1 / 240;
    while (t < 3) {
      t += step;
      final done = (sim.x(t) - 1).abs() < 0.001 && sim.dx(t).abs() < 0.01;
      if (!done) settledSince = t;
      if (t - settledSince > 0.05) break;
    }
    return Duration(milliseconds: (settledSince * 1000).ceil());
  }

  /// The spring as a curve over [duration]. Local: Flutter has no curve that
  /// follows a spring, and this one overshoots where the spring does.
  Curve get curve => _SpringCurve(spring, duration.inMicroseconds / 1e6);
}

class _SpringCurve extends Curve {
  const _SpringCurve(this.spring, this.seconds);

  final SpringDescription spring;
  final double seconds;

  @override
  double transformInternal(double t) =>
      SpringSimulation(spring, 0, 1, 0).x(t * seconds);
}

/// M3 Expressive's two motion schemes (the `MotionScheme` tokens of
/// Material's Compose library: spatial springs move things, effects springs
/// change colour and opacity and never overshoot). Local: Flutter has the
/// spring physics, not the tokens.
abstract final class MeditejoMotion {
  /// Standard: functional, barely-there overshoot. For utilitarian moves.
  static const standardFastSpatial = MotionToken._(0.9, 1400);
  static const standardSpatial = MotionToken._(0.9, 700);
  static const standardSlowSpatial = MotionToken._(0.9, 300);

  /// Expressive: a visible, soft bounce. For hero moments (Home's tiles).
  static const expressiveFastSpatial = MotionToken._(0.6, 800);
  static const expressiveSpatial = MotionToken._(0.8, 380);
  static const expressiveSlowSpatial = MotionToken._(0.8, 200);

  /// Effects (both schemes): critically damped, no overshoot.
  static const fastEffects = MotionToken._(1, 3800);
  static const effects = MotionToken._(1, 1600);
  static const slowEffects = MotionToken._(1, 800);

  /// M3's emphasized easing, for duration-based transitions. Native.
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1);
  static const Curve emphasizedAccelerate = Cubic(0.3, 0, 0.8, 0.15);

  static const short = Duration(milliseconds: 200);
  static const medium = Duration(milliseconds: 400);
  static const long = Duration(milliseconds: 500);

  /// One breath of the logo mark: six a minute, a resting pace. Its round
  /// shapes ease from their organic form to a true circle and back. See
  /// `services/identity/seeded_random.dart` (`breathAt`).
  static const markBreath = Duration(seconds: 10);
}

/// The M3 type scale (baseline and Expressive's emphasized styles) in
/// Google Sans, which the app bundles. Flutter's `Typography` has the
/// baseline sizes but not the emphasized set, so both are spelled out here.
abstract final class MeditejoType {
  static const family = 'Google Sans';

  static TextStyle _s(
    double size,
    double height,
    FontWeight weight, [
    double tracking = 0,
  ]) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: height / size,
    fontWeight: weight,
    letterSpacing: tracking,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static const _regular = FontWeight.w400;
  static const _medium = FontWeight.w500;
  static const _semiBold = FontWeight.w600;
  static const _bold = FontWeight.w700;

  /// The baseline scale, no colour (the theme applies it).
  static TextTheme baseline() => TextTheme(
    displayLarge: _s(57, 64, _regular, -0.25),
    displayMedium: _s(45, 52, _regular),
    displaySmall: _s(36, 44, _regular),
    headlineLarge: _s(32, 40, _regular),
    headlineMedium: _s(28, 36, _regular),
    headlineSmall: _s(24, 32, _regular),
    titleLarge: _s(22, 28, _regular),
    titleMedium: _s(16, 24, _medium, 0.15),
    titleSmall: _s(14, 20, _medium, 0.1),
    bodyLarge: _s(16, 24, _regular, 0.5),
    bodyMedium: _s(14, 20, _regular, 0.25),
    bodySmall: _s(12, 16, _regular, 0.4),
    labelLarge: _s(14, 20, _medium, 0.1),
    labelMedium: _s(12, 16, _medium, 0.5),
    labelSmall: _s(11, 16, _medium, 0.5),
  );

  /// Expressive's emphasized styles: the same sizes, one step heavier, for
  /// headlines, the selected state and anything that should lead the eye.
  static TextTheme emphasized() => TextTheme(
    displayLarge: _s(57, 64, _medium, -0.25),
    displayMedium: _s(45, 52, _medium),
    displaySmall: _s(36, 44, _medium),
    headlineLarge: _s(32, 40, _medium),
    headlineMedium: _s(28, 36, _medium),
    headlineSmall: _s(24, 32, _medium),
    titleLarge: _s(22, 28, _medium),
    titleMedium: _s(16, 24, _bold, 0.15),
    titleSmall: _s(14, 20, _bold, 0.1),
    bodyLarge: _s(16, 24, _medium, 0.5),
    bodyMedium: _s(14, 20, _medium, 0.25),
    bodySmall: _s(12, 16, _medium, 0.4),
    labelLarge: _s(14, 20, _semiBold, 0.1),
    labelMedium: _s(12, 16, _semiBold, 0.5),
    labelSmall: _s(11, 16, _semiBold, 0.5),
  );
}
