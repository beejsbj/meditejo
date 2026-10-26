import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Calm stand-in artwork for anything without a picture: a soft two-tone
/// gradient with a few quiet rings, chosen from a small muted palette by
/// [seed]. The same seed always draws the same tile, so a course keeps its
/// colour everywhere it appears, and the palette keeps the set consistent.
class GeneratedArtwork extends StatelessWidget {
  const GeneratedArtwork({super.key, required this.seed, this.colors});

  /// What the tile stands for, usually the title or ID.
  final String seed;

  /// A (light, deep) pair to draw with instead of the one [seed] picks, so a
  /// family of tiles (one shelf of sounds) can share a colour.
  final (Color, Color)? colors;

  /// Muted, low-contrast pairs (light, deep) that sit well on the dark and
  /// light themes alike.
  static const palette = <(Color, Color)>[
    (Color(0xFF6F8A7D), Color(0xFF3C5149)), // sage
    (Color(0xFF6D7C99), Color(0xFF3B465F)), // dusk
    (Color(0xFF9A7B6D), Color(0xFF5B433B)), // clay
    (Color(0xFF857693), Color(0xFF4A405C)), // lilac
    (Color(0xFF9C9172), Color(0xFF5E563F)), // sand
    (Color(0xFF788A5E), Color(0xFF414B32)), // moss
    (Color(0xFF63909A), Color(0xFF30505A)), // lagoon
    (Color(0xFF99707B), Color(0xFF5C3E47)), // dust rose
  ];

  /// FNV-1a over UTF-16 units: stable across runs and platforms, unlike
  /// [String.hashCode], which makes the colours stable between launches.
  static int hash(String text) {
    var h = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  /// The palette entry [seed] draws with.
  static (Color, Color) colorsFor(String seed) =>
      palette[hash(seed) % palette.length];

  @override
  Widget build(BuildContext context) {
    final h = hash(seed);
    final (light, deep) = colors ?? colorsFor(seed);
    return ExcludeSemantics(
      child: CustomPaint(
        painter: _ArtworkPainter(
          light: light,
          deep: deep,
          // Ring centre and size vary a little by seed, never to the point
          // of looking busy.
          dx: 0.25 + ((h >> 8) % 50) / 100,
          dy: 0.2 + ((h >> 16) % 40) / 100,
          scale: 0.55 + ((h >> 24) % 30) / 100,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ArtworkPainter extends CustomPainter {
  const _ArtworkPainter({
    required this.light,
    required this.deep,
    required this.dx,
    required this.dy,
    required this.scale,
  });

  final Color light;
  final Color deep;
  final double dx;
  final double dy;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, deep],
        ).createShader(rect),
    );

    final centre = Offset(size.width * dx, size.height * dy);
    final radius = size.shortestSide * scale;
    canvas.drawCircle(
      centre,
      radius,
      Paint()..color = Colors.white.withValues(alpha: 0.07),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, size.shortestSide / 90)
      ..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawCircle(centre, radius * 0.72, ring);
    canvas.drawCircle(centre, radius * 1.35, ring);
  }

  @override
  bool shouldRepaint(_ArtworkPainter old) =>
      old.light != light ||
      old.deep != deep ||
      old.dx != dx ||
      old.dy != dy ||
      old.scale != scale;
}
