import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/library/library_database.dart';

final _libCourseProvider = FutureProvider.autoDispose
    .family<LibCourseRow?, String>((ref, id) {
      ref.watch(libraryRevisionProvider);
      return ref.watch(libraryDatabaseProvider).courseById(id);
    });

/// How an imported feed lists its episodes and whether it looks for new
/// ones. Nothing for a course made of files, or for anything not imported.
class LibCourseSettings extends ConsumerWidget {
  const LibCourseSettings({super.key, required this.courseId});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(_libCourseProvider(courseId)).value;
    if (course == null || course.origin != 'feed') {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;

    Future<void> change({String? order, bool? refresh}) async {
      await ref
          .read(libSourceProvider)
          .updateCourseSettings(courseId, episodeOrder: order, autoRefresh: refresh);
      ref.invalidate(_libCourseProvider(courseId));
      ref.invalidate(packDataProvider(packId: courseId));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('course_order_oldest'),
              label: Text(l10n.importOrderOldest),
              selected: course.episodeOrder == 'oldest',
              onSelected: (_) => change(order: 'oldest'),
            ),
            ChoiceChip(
              key: const ValueKey('course_order_newest'),
              label: Text(l10n.importOrderNewest),
              selected: course.episodeOrder == 'newest',
              onSelected: (_) => change(order: 'newest'),
            ),
          ],
        ),
        // A plain row: the course header paints its own background, which
        // would hide a ListTile's ink.
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.libraryCheckNew,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Switch(
              key: const ValueKey('course_auto_refresh'),
              value: course.autoRefresh,
              onChanged: (value) => change(refresh: value),
            ),
          ],
        ),
      ],
    );
  }
}
