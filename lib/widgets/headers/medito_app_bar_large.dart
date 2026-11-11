import 'package:medito/constants/constants.dart';
import 'package:medito/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/headers/page_back_button.dart';

class MeditoAppBarLarge extends StatefulWidget {
  const MeditoAppBarLarge({
    super.key,
    required this.scrollController,
    required this.title,
    this.coverUrl,
    this.art,
    this.bgColor = ColorConstants.onyx,
    this.hasLeading = false,
  });

  final ScrollController scrollController;
  final String title;
  final String? coverUrl;

  /// What the header stands for (by id); shown when there is no picture.
  final ArtSubject? art;
  final Color bgColor;

  /// Whether Back shows at the top-left, over the art: on a pushed page.
  final bool hasLeading;

  @override
  State<MeditoAppBarLarge> createState() => _MeditoAppBarLargeState();
}

class _MeditoAppBarLargeState extends State<MeditoAppBarLarge> {
  final topBarHeight = 300.0;

  /// The title's left edge: at the page's gutter while the header is open,
  /// clear of Back once it has collapsed into the toolbar.
  static const _expandedPadding = 16.0;
  static const _collapsedPadding = 60.0;

  @override
  Widget build(BuildContext context) {
    final scrollPosition = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;
    final scrollFactor = (scrollPosition / 240).clamp(0.0, 1.0);
    final hasLeading = widget.hasLeading;

    return SliverAppBar.large(
      shadowColor: ColorConstants.ebony,
      surfaceTintColor: ColorConstants.transparent,
      expandedHeight: topBarHeight,
      backgroundColor: ColorConstants.onyx,
      automaticallyImplyLeading: false,
      leading: hasLeading ? const PageBackButton(onArt: true) : null,
      flexibleSpace: Builder(
        builder: (context) {
          // How far the header has collapsed, from its own extent.
          final settings = context
              .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
          final range = settings == null
              ? 0.0
              : settings.maxExtent - settings.minExtent;
          final collapsed = settings == null || range <= 0
              ? 0.0
              : (1 - (settings.currentExtent - settings.minExtent) / range)
                    .clamp(0.0, 1.0);
          // Only the last stretch moves the title aside, as it reaches the
          // toolbar's row.
          final aside = hasLeading
              ? Curves.easeIn.transform(collapsed) *
                    (_collapsedPadding - _expandedPadding)
              : 0.0;
          return FlexibleSpaceBar(
            centerTitle: false,
            titlePadding: EdgeInsetsDirectional.only(
              start: _expandedPadding + aside,
              end: 16,
              bottom: 17.0,
            ),
            title: _topBarTitle(widget.title),
            background: _topBarBackground(scrollFactor, widget.coverUrl),
          );
        },
      ),
    );
  }

  Text _topBarTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).primaryTextTheme.titleLarge?.copyWith(
        fontFamily: googleSans,
        fontWeight: FontWeight.w700,
        color: ColorConstants.white,
      ),
    );
  }

  Opacity _topBarBackground(double scrollFactor, String? coverUrl) {
    if (coverUrl != null || widget.art != null) {
      return Opacity(
        opacity: 1 - scrollFactor,
        // The scrim sits over the picture or, when there is none, over the
        // generated art, which can be pale: the white title stays legible.
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.4, 1],
              colors: [
                ColorConstants.black.withOpacityValue(0),
                ColorConstants.black.withOpacityValue(0.45),
              ],
            ),
          ),
          child: NetworkImageWidget(
            url: coverUrl ?? '',
            shouldCache: true,
            art: widget.art,
            alignment: Alignment.topCenter,
          ),
        ),
      );
    }

    return Opacity(
      opacity: 1 - scrollFactor,
      child: Container(color: widget.bgColor),
    );
  }
}
