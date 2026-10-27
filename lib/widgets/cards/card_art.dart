import 'package:flutter/material.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/network_image_widget.dart';

/// A course's or session's art: curated art when it ships, else its own
/// picture when it has one (a YouTube thumbnail, a feed's artwork), else art
/// generated from its id, the same card everywhere it appears. See
/// `shownCoverUrl` for the rule.
///
/// A Dharma Seed course or talk's [url] is its lead teacher's photo, not a
/// cover (`dsHasPortraitCover`): the art fills the card and the photo sits
/// on it as a small avatar in the corner.
class CardArt extends StatelessWidget {
  const CardArt({
    super.key,
    required this.art,
    this.url = '',
    this.avatarSize = 40,
  });

  final ArtSubject art;
  final String url;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final subject = art;
    if (subject is! CoverArt || !dsHasPortraitCover(subject.id)) {
      return NetworkImageWidget(
        url: url,
        art: art,
        shouldCache: true,
        alignment: Alignment.topCenter,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    // A small row's art is small: keep the avatar close to its corner.
    final inset = avatarSize >= 28 ? 10.0 : 4.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        ArtCover(subject: art),
        if (url.isNotEmpty)
          Positioned(
            left: inset,
            bottom: inset,
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
                    art: ArtSubject.cover(ArtCoverKind.teacher, url),
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
