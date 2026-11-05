import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/library/library_providers.dart';
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
/// on it as a small avatar in the corner. A YouTube course or video keeps
/// its thumbnail and carries its channel's picture in the same corner, once
/// the channel's page has given one (#85).
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
    if (subject is CoverArt &&
        subject.kind != ArtCoverKind.teacher &&
        (subject.id.startsWith('yt-video-') ||
            subject.id.startsWith('yt-playlist-'))) {
      final cover = _cover();
      if (NoChannelAvatars.of(context)) return cover;
      return Consumer(
        builder: (context, ref, _) {
          final avatar =
              ref.watch(youtubeAvatarProvider(subject.id)).value ?? '';
          return avatar.isEmpty ? cover : _withAvatar(context, cover, avatar);
        },
      );
    }
    if (subject is! CoverArt || !dsHasPortraitCover(subject.id)) {
      return _cover();
    }
    final cover = ArtCover(subject: art);
    return url.isEmpty ? cover : _withAvatar(context, cover, url);
  }

  Widget _cover() => NetworkImageWidget(
    url: url,
    art: art,
    shouldCache: true,
    alignment: Alignment.topCenter,
  );

  /// [cover] with [avatar] in a ringed circle at its lower left.
  Widget _withAvatar(BuildContext context, Widget cover, String avatar) {
    final scheme = Theme.of(context).colorScheme;
    // A small row's art is small: keep the avatar close to its corner.
    final inset = avatarSize >= 28 ? 10.0 : 4.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        cover,
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
                  url: avatar,
                  art: ArtSubject.cover(ArtCoverKind.teacher, avatar),
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

/// Below this, YouTube cards leave out their channel's picture: on that
/// channel's own page every card would carry the same face.
class NoChannelAvatars extends InheritedWidget {
  const NoChannelAvatars({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NoChannelAvatars>() != null;

  @override
  bool updateShouldNotify(NoChannelAvatars oldWidget) => false;
}
