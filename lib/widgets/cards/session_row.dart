import 'package:flutter/material.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/cards/card_art.dart';
import 'package:medito/widgets/cards/card_tokens.dart';

/// One session as a compact row: small art, its title, a line of detail
/// (kind, teacher, length) and its played and downloaded state, with
/// [trailing] actions (Add to library, a menu) at the end. Used for singles in
/// the Library, Explore's latest sessions and search's talks.
class SessionRow extends StatelessWidget {
  const SessionRow({
    super.key,
    required this.title,
    required this.art,
    required this.onTap,
    this.detail,
    this.artUrl = '',
    this.completed = false,
    this.downloaded = false,
    this.trailing = const [],
  });

  final String title;
  final VoidCallback onTap;
  final String? detail;
  final String artUrl;

  /// The session's art, keyed by its id; shown when it has no picture.
  final ArtSubject art;
  final bool completed;
  final bool downloaded;
  final List<Widget> trailing;

  static const artSize = 48.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final cover = SizedBox.square(
      dimension: artSize,
      child: CardArt(url: artUrl, art: art, avatarSize: 20),
    );
    return InkWell(
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
              ClipRRect(
                borderRadius: BorderRadius.circular(kCardArtRadius - 4),
                child: cover,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: type.baseline.titleMedium,
                    ),
                    if (detail != null && detail!.isNotEmpty)
                      Text(
                        detail!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: type.baseline.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (downloaded)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.download_done_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (completed)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                ),
              ...trailing,
            ],
          ),
        ),
      ),
    );
  }
}
