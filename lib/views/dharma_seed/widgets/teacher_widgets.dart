import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/models/catalogue/catalogue_models.dart';
import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/teacher_tiles.dart';

void openTeacher(
  BuildContext context,
  WidgetRef ref,
  CatalogueTeacher teacher,
) {
  handleNavigation(TypeConstants.teacher, [teacher.id], context, ref: ref);
}

/// Teachers in a horizontal strip of photos with names, for Explore.
class TeacherStrip extends ConsumerWidget {
  const TeacherStrip({super.key, required this.teachers});

  final List<CatalogueTeacher> teachers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: TeacherTile.stripHeight(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kCardGutter),
        itemCount: teachers.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final teacher = teachers[index];
          return TeacherTile(
            key: ValueKey('teacher_${teacher.id}'),
            id: teacher.id,
            name: teacher.name,
            photoUrl: teacher.photoUrl,
            onTap: () => openTeacher(context, ref, teacher),
          );
        },
      ),
    );
  }
}

/// A teacher as a result row: photo, name and how many talks they gave.
class TeacherRows extends ConsumerWidget {
  const TeacherRows({super.key, required this.teachers, this.onBeforeNavigate});

  final List<CatalogueTeacher> teachers;
  final VoidCallback? onBeforeNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        for (final teacher in teachers)
          TeacherRow(
            key: ValueKey('teacher_row_${teacher.id}'),
            id: teacher.id,
            name: teacher.name,
            photoUrl: teacher.photoUrl,
            detail: teacher.talkCount > 0
                ? l10n.teacherTalkCount(teacher.talkCount)
                : null,
            onTap: () {
              onBeforeNavigate?.call();
              openTeacher(context, ref, teacher);
            },
          ),
      ],
    );
  }
}
