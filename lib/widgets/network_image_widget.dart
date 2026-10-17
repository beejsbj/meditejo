import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/widgets/generated_artwork.dart';
import 'package:shimmer/shimmer.dart';

class NetworkImageWidget extends StatelessWidget {
  final String url;
  final double? height, width;
  final bool shouldCache;
  final Gradient? gradient;
  final Widget? errorWidget;

  /// When set, a missing or failed image shows [GeneratedArtwork] for this
  /// seed instead of the bundled placeholder (unless [errorWidget] is given).
  final String? seed;
  const NetworkImageWidget({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.shouldCache = false,
    this.gradient,
    this.errorWidget,
    this.seed,
  });

  Widget get _fallback =>
      errorWidget ??
      (seed == null
          ? Image.asset(AssetConstants.placeholder, fit: BoxFit.cover)
          : GeneratedArtwork(seed: seed!));

  // Artwork only, never labelled: excluded so each card doesn't pick up an
  // "image" trait (or a stray unlabelled image stop) from it.
  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: _buildImage(context));

  Widget _buildImage(BuildContext context) {
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
          image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
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
