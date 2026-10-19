import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/views/pack/widgets/pack_complete_badge.dart';
import 'package:medito/widgets/add_to_library_icon.dart';
import 'package:medito/widgets/network_image_widget.dart';

/// Courses as compact rows: artwork, title, and "teacher · year · N talks".
/// Used where a grid of cards would crowd the page (search results, a
/// teacher's courses).
class CourseRowsSliver extends ConsumerWidget {
  const CourseRowsSliver({
    super.key,
    required this.courses,
    this.onBeforeNavigate,
  });

  final List<PackItemsModel> courses;
  final VoidCallback? onBeforeNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completed = ref.watch(completedPackIdsProvider);
    final theme = Theme.of(context);
    return SliverList.builder(
      itemCount: courses.length,
      itemBuilder: (context, index) {
        final course = courses[index];
        return Semantics(
          button: true,
          child: InkWell(
            key: ValueKey('course_${course.id}'),
            onTap: () {
              onBeforeNavigate?.call();
              handleNavigation(
                TypeConstants.pack,
                [course.id, course.path],
                context,
                ref: ref,
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: padding16,
                vertical: 10,
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox.square(
                      dimension: 64,
                      child: NetworkImageWidget(
                        url: course.coverUrl ?? '',
                        seed: course.title,
                        shouldCache: true,
                        alignment: Alignment.topCenter,
                      ),
                    ),
                  ),
                  const SizedBox(width: padding16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineMedium,
                        ),
                        if ((course.subtitle ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              course.subtitle!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (completed.contains(course.id))
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: PackCompleteBadge(),
                    ),
                  AddToLibraryIcon(id: course.id),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
