import 'package:flutter/material.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/views/dharma_seed/widgets/teacher_avatar.dart';
import 'package:medito/widgets/cards/card_tokens.dart';

/// A teacher in a strip: their photo (or generated art) in a circle, with
/// their name beneath. One button to screen readers, named for the teacher.
class TeacherTile extends StatelessWidget {
  const TeacherTile({
    super.key,
    required this.name,
    required this.photoUrl,
    required this.onTap,
  });

  final String name;
  final String photoUrl;
  final VoidCallback onTap;

  static const photo = 76.0;
  static const width = 92.0;

  /// A strip of tiles is this tall: the photo, a gap and two lines of name at
  /// the current text size.
  static double stripHeight(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'Ag', style: context.typography.baseline.labelLarge),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final name = painter.height * 2;
    painter.dispose();
    return (photo + 8 + name + 8).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: name,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(kCardArtRadius),
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              TeacherAvatar(name: name, photoUrl: photoUrl, size: photo),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: context.typography.baseline.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A teacher as a row: photo, name and a line of detail (how many talks),
/// with [trailing] actions at the end.
class TeacherRow extends StatelessWidget {
  const TeacherRow({
    super.key,
    required this.name,
    required this.photoUrl,
    required this.onTap,
    this.detail,
    this.trailing = const [],
  });

  final String name;
  final String photoUrl;
  final VoidCallback onTap;
  final String? detail;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              kCardGutter,
              8,
              trailing.isEmpty ? kCardGutter : 4,
              8,
            ),
            child: Row(
              children: [
                TeacherAvatar(name: name, photoUrl: photoUrl, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: type.emphasized.titleMedium,
                      ),
                      if (detail != null && detail!.isNotEmpty)
                        Text(
                          detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.baseline.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                ...trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
