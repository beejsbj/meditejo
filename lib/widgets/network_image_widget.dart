import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:shimmer/shimmer.dart';

class NetworkImageWidget extends StatelessWidget {
  final String url;
  final double? height, width;
  final bool shouldCache;
  final Gradient? gradient;
  final Widget? errorWidget;

  /// What the picture stands for. When set, a missing or failed image shows
  /// its [ArtCover] instead of the bundled placeholder (unless [errorWidget]
  /// is given), and curated art for a shipped id wins over [url] (see
  /// [shownCoverUrl]). Seeded by id, so build it with [courseArt] and kin.
  final ArtSubject? art;

  /// Which part of a cropped image stays in view. Portraits keep the face
  /// with [Alignment.topCenter].
  final Alignment alignment;
  const NetworkImageWidget({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.shouldCache = false,
    this.gradient,
    this.errorWidget,
    this.art,
    this.alignment = Alignment.center,
  });

  Widget get _fallback =>
      errorWidget ??
      (art == null
          ? Image.asset(AssetConstants.placeholder, fit: BoxFit.cover)
          : ArtCover(subject: art!));

  // Artwork only, never labelled: excluded so each card doesn't pick up an
  // "image" trait (or a stray unlabelled image stop) from it.
  @override
  Widget build(BuildContext context) {
    if (art == null) {
      return ExcludeSemantics(child: _buildImage(context, url));
    }
    // The curated file loads once; until it's in, a picture shows, and a
    // shipped id's curated card replaces it when it arrives.
    CuratedArt.instance.load();
    return ListenableBuilder(
      listenable: CuratedArt.instance,
      builder: (context, _) => ExcludeSemantics(
        child: _buildImage(context, shownCoverUrl(art, url)),
      ),
    );
  }

  Widget _buildImage(BuildContext context, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return _fallback;
    }

    return uri.path.endsWith('.svg')
        ? _buildSvgImage(url)
        : shouldCache
        ? _buildCachedImage(url)
        : _buildNetworkImage(url);
  }

  Widget _buildSvgImage(String url) {
    return SvgPicture.network(
      url,
      fit: BoxFit.contain,
      height: height,
      width: width,
      placeholderBuilder: (context) => _shimmerLoading(),
    );
  }

  Widget _buildCachedImage(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      imageBuilder: (context, imageProvider) => Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: imageProvider,
            fit: BoxFit.cover,
            alignment: alignment,
          ),
        ),
        foregroundDecoration: BoxDecoration(gradient: gradient),
      ),
      placeholder: (_, _) => _shimmerLoading(),
      errorWidget: (context, url, error) => _fallback,
    );
  }

  Widget _buildNetworkImage(String url) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      alignment: alignment,
      height: height,
      width: width,
      cacheHeight: height?.round(),
      cacheWidth: width?.round(),
      loadingBuilder: (_, child, loadingProgress) =>
          loadingProgress == null ? child : _shimmerLoading(),
      errorBuilder: (context, error, stackTrace) => _fallback,
    );
  }

  Widget _shimmerLoading() {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final baseColor = isDark
            ? ColorConstants.greyIsTheNewGrey
            : ColorConstants.lightGrey;
        final backgroundColor = isDark
            ? ColorConstants.onyx
            : ColorConstants.lightCard;

        return Shimmer.fromColors(
          period: const Duration(seconds: 1),
          baseColor: baseColor,
          highlightColor: backgroundColor,
          child: Container(
            color: backgroundColor,
            height: height,
            width: width,
          ),
        );
      },
    );
  }
}
