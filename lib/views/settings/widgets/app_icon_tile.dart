import 'package:flutter/material.dart';
import 'package:medito/views/home/widgets/bottom_sheet/row_item_widget.dart';

/// One primary icon while the Meditejo mark is being chosen.
class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    required this.icon,
    required this.title,
    this.hasUnderline = true,
  });

  final Widget icon;
  final String title;
  final bool hasUnderline;

  @override
  Widget build(BuildContext context) => RowItemWidget(
    icon: icon,
    title: title,
    subTitle: 'Meditejo',
    hasUnderline: hasUnderline,
    isTrailingIcon: false,
    trailing: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.asset(
        'assets/images/app_icons/placeholder.png',
        width: 28,
        height: 28,
      ),
    ),
  );
}
