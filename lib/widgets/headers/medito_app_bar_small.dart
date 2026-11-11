import 'package:medito/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:medito/widgets/headers/page_back_button.dart';

class MeditoAppBarSmall extends StatelessWidget implements PreferredSizeWidget {
  const MeditoAppBarSmall({
    super.key,
    this.title,
    this.titleWidget,
    this.isTransparent = false,
    this.hasBackButton = true,
    this.actions,
    this.closePressed,
    this.bottom,
  });

  /// What Back does, in place of popping the page.
  final void Function()? closePressed;
  final Widget? titleWidget;
  final bool isTransparent;

  /// Back at the top-left, on a page that was pushed.
  final bool hasBackButton;
  final List<Widget>? actions;
  final String? title;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    final hasBottom = bottom != null;
    final hasActions = actions != null && actions!.isNotEmpty;
    return AppBar(
      leading: hasBackButton ? PageBackButton(onPressed: closePressed) : null,
      automaticallyImplyLeading: false,
      centerTitle: true,
      actions: actions,
      elevation: 0,
      backgroundColor: isTransparent
          ? ColorConstants.transparent
          : Theme.of(context).colorScheme.surface,
      title: hasBottom ? null : getTitleWidget(context),
      toolbarHeight: hasBottom && !hasActions && !hasBackButton ? 0 : null,
      bottom: bottom,
    );
  }

  Widget getTitleWidget(BuildContext context) {
    return titleWidget == null
        ? Text(title ?? '', style: Theme.of(context).textTheme.displayLarge)
        : Row(children: [titleWidget!]);
  }

  @override
  Size get preferredSize {
    if (bottom != null) {
      return Size.fromHeight(bottom!.preferredSize.height);
    }
    return const Size.fromHeight(56.0);
  }
}
