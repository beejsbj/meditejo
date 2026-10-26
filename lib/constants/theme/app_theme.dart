import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/palette_theme.dart';
import 'package:medito/constants/theme/text_theme.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/services/identity/palettes.dart';

import 'input_theme.dart';

/// The app's colour scheme for [brightness] under [palette] (the default
/// palette when none is given). See `palette_theme.dart`.
ColorScheme meditejoColorScheme(
  Brightness brightness, [
  IdentityPalette? palette,
]) => paletteColorScheme(palette ?? IdentityPalettes.fallback, brightness);

/// Material 3 Expressive, built from the tokens in `tokens.dart`. Screens
/// not yet redesigned keep the text roles they were laid out with
/// (`text_theme.dart`) but take their colours, shapes and components from
/// here.
ThemeData appTheme(
  BuildContext context, [
  ThemeMode? themeMode,
  IdentityPalette? palette,
]) {
  final brightness = MediaQuery.of(context).platformBrightness;
  final isDark =
      themeMode == ThemeMode.dark ||
      (themeMode == ThemeMode.system && brightness == Brightness.dark);
  return meditejoTheme(isDark ? Brightness.dark : Brightness.light, palette);
}

/// The theme for [brightness] under [palette] (the default when none).
ThemeData meditejoTheme(Brightness brightness, [IdentityPalette? palette]) {
  final active = palette ?? IdentityPalettes.fallback;
  final scheme = meditejoColorScheme(brightness, active);
  final isDark = brightness == Brightness.dark;
  final typography = ExpressiveTypography.from(scheme);
  final type = typography.baseline;
  final emphasized = typography.emphasized;

  final pill = MeditejoShapes.stadium;
  final buttonText = emphasized.titleMedium!.copyWith(
    fontWeight: FontWeight.w600,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: MeditejoType.family,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    cardColor: scheme.surfaceContainerHigh,
    dividerColor: scheme.outlineVariant,
    textTheme: legacyTextTheme(scheme),
    extensions: [typography, MeditejoPalette(active)],
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    inputDecorationTheme: inputDecorationTheme(scheme, type),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleTextStyle: emphasized.titleLarge,
      systemOverlayStyle: SystemUiOverlayStyle(
        systemNavigationBarColor: scheme.surfaceContainer,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: pill,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? emphasized.labelMedium!.copyWith(color: scheme.onSurface)
            : type.labelMedium!.copyWith(color: scheme.onSurfaceVariant),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: pill,
      selectedLabelTextStyle: emphasized.labelMedium!.copyWith(
        color: scheme.onSurface,
      ),
      unselectedLabelTextStyle: type.labelMedium!.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    // Buttons: Expressive's round (pill) shape. The elevated button is drawn
    // as a filled one: the app's older screens use it for their main action.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: pill, textStyle: buttonText),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.outline),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        shape: pill,
        textStyle: emphasized.labelLarge,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: pill,
        textStyle: emphasized.labelLarge,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      elevation: 0,
      shape: MeditejoShapes.rounded(MeditejoShapes.large),
    ),
    chipTheme: ChipThemeData(
      shape: MeditejoShapes.rounded(MeditejoShapes.small),
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.secondaryContainer,
      labelStyle: type.labelLarge!.copyWith(color: scheme.onSurfaceVariant),
      secondaryLabelStyle: emphasized.labelLarge!.copyWith(
        color: scheme.onSecondaryContainer,
      ),
      checkmarkColor: scheme.onSecondaryContainer,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: MeditejoShapes.rounded(MeditejoShapes.largeIncreased),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: scheme.surfaceContainerLow,
      dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MeditejoShapes.extraLarge),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: type.headlineSmall!.copyWith(color: scheme.onSurface),
      contentTextStyle: type.bodyMedium!.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      shape: MeditejoShapes.rounded(MeditejoShapes.extraLarge),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: MeditejoShapes.rounded(MeditejoShapes.large),
      textStyle: type.bodyLarge!.copyWith(color: scheme.onSurface),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: type.bodyMedium!.copyWith(
        color: scheme.onInverseSurface,
      ),
      actionTextColor: scheme.inversePrimary,
      shape: MeditejoShapes.rounded(MeditejoShapes.medium),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    listTileTheme: ListTileThemeData(
      shape: MeditejoShapes.rounded(MeditejoShapes.large),
      iconColor: scheme.onSurfaceVariant,
    ),
    // Material's 2024 indicators: rounded ends, a gap and a stop dot. Native.
    progressIndicatorTheme: ProgressIndicatorThemeData(
      // ignore: deprecated_member_use
      year2023: false,
      color: scheme.primary,
      linearTrackColor: scheme.secondaryContainer,
      circularTrackColor: scheme.secondaryContainer,
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      hourMinuteShape: MeditejoShapes.rounded(MeditejoShapes.medium),
      dayPeriodShape: MeditejoShapes.rounded(MeditejoShapes.medium),
      shape: MeditejoShapes.rounded(MeditejoShapes.extraLarge),
    ),
  );
}
