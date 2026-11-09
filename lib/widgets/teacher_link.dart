import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/views/dharma_seed/widgets/teacher_avatar.dart';

/// Who leads a course or a session: the teacher's (or channel's) avatar and
/// name, opening their page. One line; a long name ellipsizes.
class TeacherLink extends ConsumerWidget {
  const TeacherLink({
    super.key,
    required this.id,
    required this.name,
    this.photoUrl = '',
  });

  /// The teacher page's app ID (`ds-teacher-…`, `yt-channel-…`).
  final String id;
  final String name;
  final String photoUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () =>
            handleNavigation(TypeConstants.teacher, [id], context, ref: ref),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.only(right: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: TeacherAvatar(
                  id: id,
                  name: name,
                  photoUrl: photoUrl,
                  size: 32,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
