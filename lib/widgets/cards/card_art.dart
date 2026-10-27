import 'package:flutter/material.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/network_image_widget.dart';

/// A course's or session's art: curated art when it ships, else its own
/// picture when it has one (a YouTube thumbnail, a feed's artwork), else art
/// generated from its id, the same card everywhere it appears. See
/// `shownCoverUrl` for the rule.
class CardArt extends StatelessWidget {
  const CardArt({super.key, required this.art, this.url = ''});

  final ArtSubject art;
  final String url;

  @override
  Widget build(BuildContext context) => NetworkImageWidget(
    url: url,
    art: art,
    shouldCache: true,
    alignment: Alignment.topCenter,
  );
}
