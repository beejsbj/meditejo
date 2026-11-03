import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/colors/color_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/views/library/library_actions.dart';

import 'bottom_action_bar.dart';

/// The bottom bar's Pin: pins the course or ([session]) session [id] to
/// Home, or takes it off. Filled and in the accent colour while pinned.
BottomActionBarItem pinActionItem(
  BuildContext context,
  WidgetRef ref,
  String id, {
  bool session = false,
}) {
  final l10n = AppLocalizations.of(context)!;
  final pinned = ref.watch(pinnedCoursesProvider).contains(id);
  return BottomActionBarItem(
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.72, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      ),
      child: Icon(
        pinned ? Icons.push_pin : Icons.push_pin_outlined,
        key: ValueKey(pinned ? 'pin_on' : 'pin_off'),
        color: pinned
            ? context.brandAccent
            : Theme.of(context).colorScheme.onSurface,
      ),
    ),
    semanticLabel: pinned ? l10n.unpinCourse : l10n.pinCourse,
    onTap: () => togglePin(context, ref, id, session: session),
  );
}
