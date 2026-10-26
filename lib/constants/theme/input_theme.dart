import 'package:flutter/material.dart';

import 'tokens.dart';

/// Filled fields on a tonal container, no outline until focused: Material's
/// filled text field, with Expressive's larger corners.
InputDecorationTheme inputDecorationTheme(ColorScheme scheme, TextTheme type) {
  OutlineInputBorder border([Color? color, double width = 0]) =>
      OutlineInputBorder(
        borderSide: color == null
            ? BorderSide.none
            : BorderSide(color: color, width: width),
        borderRadius: BorderRadius.circular(MeditejoShapes.large),
      );

  return InputDecorationTheme(
    labelStyle: type.bodyLarge!.copyWith(color: scheme.onSurfaceVariant),
    hintStyle: type.bodyLarge!.copyWith(color: scheme.onSurfaceVariant),
    enabledBorder: border(),
    focusedBorder: border(scheme.primary, 2),
    errorBorder: border(scheme.error, 1),
    focusedErrorBorder: border(scheme.error, 2),
    border: border(),
    filled: true,
    fillColor: scheme.surfaceContainerHighest,
  );
}
