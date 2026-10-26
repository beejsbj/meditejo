import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../constants.dart';

/// Medito's text roles, kept at the sizes the screens not yet redesigned
/// were laid out with (`displayLarge` is an 18 px heading there, not M3's
/// 57 px display). Colours come from the scheme: the muted roles take
/// `onSurfaceVariant`. Redesigned screens use [ExpressiveTypography] instead.
TextTheme legacyTextTheme(ColorScheme scheme) {
  final strong = scheme.onSurface;
  final muted = scheme.onSurfaceVariant;
  return Typography.material2021().black
      .apply(fontFamily: googleSans, bodyColor: strong, displayColor: strong)
      .copyWith(
        displayLarge: TextStyle(
          // greetings text
          // btm bar text selected
          fontSize: 18,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w800,
          height: 1.5,
          color: strong,
          fontFamily: googleSans,
        ),
        displayMedium: TextStyle(
          // btm bar text unselected
          fontSize: 18,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w700,
          height: 1.5,
          color: muted,
          fontFamily: googleSans,
        ),
        displaySmall: TextStyle(
          // header of rows on homepage
          fontSize: 18,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w800,
          height: 1.3,
          color: strong,
          fontFamily: googleSans,
        ),
        headlineMedium: TextStyle(
          // packs title on home and packs screen
          // streak tile data (not title)
          // downloads tile session name
          // overflow menu
          fontSize: 16,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w600,
          height: 1.3,
          color: strong,
          fontFamily: googleSans,
        ),
        headlineSmall: TextStyle(
          // stats widget
          fontSize: 20,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w700,
          height: 1.2,
          color: strong,
          fontFamily: googleSans,
        ),
        titleMedium: TextStyle(
          // packs subtitle on home
          // downloads subtitle
          fontSize: 14,
          letterSpacing: 0.4,
          fontWeight: FontWeight.w500,
          height: 1.5,
          color: muted,
          fontFamily: googleSans,
        ),
        titleSmall: TextStyle(
          // shortcut title
          fontSize: 14,
          letterSpacing: 0.2,
          fontWeight: FontWeight.w500,
          height: 1.5,
          color: strong,
          fontFamily: googleSans,
        ),
        bodySmall: TextStyle(
          // caption / overline / tag (12)
          fontSize: 12,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
          height: 1.5,
          color: muted,
          fontFamily: googleSans,
        ),
        bodyMedium: TextStyle(
          // error widget
          fontSize: 16,
          letterSpacing: 0.5,
          fontWeight: FontWeight.normal,
          height: 1.3,
          color: muted,
          fontFamily: googleSans,
        ),
        bodyLarge: TextStyle(
          // daily text and quote
          fontSize: 14,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: strong,
          fontFamily: googleSans,
        ),
        titleLarge: TextStyle(
          // onboarding option button label
          fontSize: 16,
          letterSpacing: 0.2,
          fontWeight: FontWeight.w500,
          height: 1.3,
          color: strong,
          fontFamily: googleSans,
        ),
        labelLarge: TextStyle(
          // section header (20)
          fontSize: 20,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
          height: 1.5,
          color: strong,
          fontFamily: googleSans,
        ),
        labelMedium: TextStyle(
          // error widget
          fontSize: 16,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w500,
          height: 1.3,
          color: strong,
          fontFamily: googleSans,
        ),
        labelSmall: TextStyle(
          // daily text and quote
          fontSize: 14,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: strong,
          fontFamily: googleSans,
        ),
      );
}

/// The ambient theme's text roles (kept for older call sites).
TextTheme meditoTextTheme(BuildContext context) => Theme.of(context).textTheme;

MarkdownStyleSheet buildMarkdownStyleSheet(BuildContext context) {
  return MarkdownStyleSheet.fromTheme(Theme.of(context));
}
