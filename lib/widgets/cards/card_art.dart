import 'package:flutter/material.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/widgets/generated_artwork.dart';
import 'package:medito/widgets/network_image_widget.dart';

/// Whether [id]'s cover is a teacher's portrait rather than art made for it.
/// Dharma Seed has no cover art: its courses and talks carry the lead
/// teacher's photo.
bool hasPortraitCover(String id) => id.startsWith(dharmaSeedPrefix);

/// A course's or session's art. Its own picture when it has one; otherwise
/// generated art seeded by [seed], the same tile everywhere it appears.
///
/// A [portrait] cover (a teacher's photo, see [hasPortraitCover]) crops badly
/// as a wide card's art, so it is drawn as generated art with the photo as a
/// small avatar in the corner.
class CardArt extends StatelessWidget {
  const CardArt({
    super.key,
    required this.seed,
    this.url = '',
    this.portrait = false,
    this.avatarSize = 40,
  });

  final String seed;
  final String url;
  final bool portrait;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    if (!portrait) {
      return NetworkImageWidget(
        url: url,
        seed: seed,
        shouldCache: true,
        alignment: Alignment.topCenter,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        GeneratedArtwork(seed: seed),
        if (url.isNotEmpty)
          Positioned(
            left: 10,
            bottom: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 2),
              ),
              child: ClipOval(
                child: SizedBox.square(
                  dimension: avatarSize,
                  child: NetworkImageWidget(
                    url: url,
                    seed: url,
                    shouldCache: true,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
