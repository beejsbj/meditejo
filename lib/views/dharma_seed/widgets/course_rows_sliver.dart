import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/views/pack/widgets/pack_complete_badge.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/views/my_courses/playlist_label.dart';
import 'package:medito/widgets/add_to_library_icon.dart';
import 'package:medito/widgets/cards/card_art.dart';
import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/course_card.dart';
import 'package:medito/widgets/cover_art.dart';

/// Courses as wide row cards: art, title, and "teacher · year · N talks",
/// with Add to library and the course's menu. Used where a strip of large
/// cards would crowd the page (search results, a teacher's courses).
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
    final l10n = AppLocalizations.of(context)!;
    return SliverList.builder(
      itemCount: courses.length,
      itemBuilder: (context, index) {
        final course = courses[index];
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            kCardGutter,
            0,
            kCardGutter,
            kCardGap / 2,
          ),
          child: Semantics(
            button: true,
            child: CourseRowCard(
              key: ValueKey('course_${course.id}'),
              title: course.title,
              detail: playlistAwareDetail(l10n, course.id, course.subtitle),
              art: CardArt(
                url: course.coverUrl ?? '',
                art: courseArt(course.id),
                avatarSize: 28,
              ),
              onTap: () {
                onBeforeNavigate?.call();
                handleNavigation(
                  TypeConstants.pack,
                  [course.id, course.path],
                  context,
                  ref: ref,
                );
              },
              trailing: [
                if (completed.contains(course.id))
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: PackCompleteBadge(),
                  ),
                AddToLibraryIcon(id: course.id),
                ContentActionsButton(id: course.id, title: course.title),
              ],
            ),
          ),
        );
      },
    );
  }
}
