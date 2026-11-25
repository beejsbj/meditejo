import 'package:flutter/material.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/utils/utils.dart';

/// Back, at the top-left of a pushed page: in its top bar or, with [onArt],
/// over its header art on a dark disc so the arrow reads on any picture.
/// The system's back gesture does the same; this is the one on screen.
class PageBackButton extends StatelessWidget {
  const PageBackButton({
    super.key,
    this.onPressed,
    this.onLongPress,
    this.onArt = false,
  });

  /// Defaults to popping the page.
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// Over a picture: a white arrow on a translucent dark disc.
  final bool onArt;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      key: const ValueKey('page_back'),
      tooltip: AppLocalizations.of(context)!.goBack,
      onPressed: onPressed ?? () => Navigator.maybePop(context),
      onLongPress: onLongPress,
      style: onArt
          ? IconButton.styleFrom(
              backgroundColor: ColorConstants.black.withOpacityValue(0.38),
              foregroundColor: ColorConstants.white,
              minimumSize: const Size(40, 40),
              tapTargetSize: MaterialTapTargetSize.padded,
            )
          : null,
      icon: const Icon(Icons.arrow_back),
    );
    return onArt ? Center(child: button) : button;
  }
}
