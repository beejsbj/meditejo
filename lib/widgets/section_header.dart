import 'package:flutter/material.dart';
import 'package:medito/constants/constants.dart';

/// A quiet heading for a group of results or a part of a page.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.padding});

  final String title;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding:
            padding ??
            const EdgeInsets.fromLTRB(padding16, padding24, padding16, 0),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontFamily: googleSans,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
    );
  }
}
