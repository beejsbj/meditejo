import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/services/dharma_seed/dharma_seed_models.dart';
import 'package:medito/views/dharma_seed/widgets/teacher_avatar.dart';

void openTeacher(BuildContext context, WidgetRef ref, DsTeacherItem teacher) {
  handleNavigation(TypeConstants.teacher, [teacher.id], context, ref: ref);
}

/// Teachers in a horizontal strip of photos with names, for Explore.
class TeacherStrip extends ConsumerWidget {
  const TeacherStrip({super.key, required this.teachers});

  final List<DsTeacherItem> teachers;

  static const _photo = 76.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Photo, gap and two lines of name: the name's height follows the text
    // size, so the strip does too.
    final nameLines = 2 * MediaQuery.textScalerOf(context).scale(13 * 1.25);
    return SizedBox(
      height: padding16 + padding8 + _photo + 8 + nameLines + 8,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          padding16,
          padding16,
          padding16,
          padding8,
        ),
        itemCount: teachers.length,
        separatorBuilder: (_, _) => const SizedBox(width: padding16),
        itemBuilder: (context, index) {
          final teacher = teachers[index];
          return Semantics(
            button: true,
            label: teacher.name,
            excludeSemantics: true,
            onTap: () => openTeacher(context, ref, teacher),
            child: InkWell(
              key: ValueKey('teacher_${teacher.id}'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => openTeacher(context, ref, teacher),
              child: SizedBox(
                width: 92,
                child: Column(
                  children: [
                    TeacherAvatar(
                      name: teacher.name,
                      photoUrl: teacher.photoUrl,
                      size: _photo,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      teacher.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A teacher as a result row: photo, name and how many talks they gave.
class TeacherRows extends ConsumerWidget {
  const TeacherRows({super.key, required this.teachers, this.onBeforeNavigate});

  final List<DsTeacherItem> teachers;
  final VoidCallback? onBeforeNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final teacher in teachers)
          Semantics(
            button: true,
            child: InkWell(
              key: ValueKey('teacher_row_${teacher.id}'),
              onTap: () {
                onBeforeNavigate?.call();
                openTeacher(context, ref, teacher);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: padding16,
                  vertical: padding8,
                ),
                child: Row(
                  children: [
                    TeacherAvatar(
                      name: teacher.name,
                      photoUrl: teacher.photoUrl,
                      size: 52,
                    ),
                    const SizedBox(width: padding16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            teacher.name,
                            style: theme.textTheme.headlineMedium,
                          ),
                          if (teacher.talkCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                l10n.teacherTalkCount(teacher.talkCount),
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
