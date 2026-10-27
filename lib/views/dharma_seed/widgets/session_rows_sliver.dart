import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/meditation/downloaded_track_ids_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/widgets/add_to_library_icon.dart';
import 'package:medito/widgets/cards/session_row.dart';
import 'package:medito/widgets/cover_art.dart';

/// Single sessions as compact rows: art (with the teacher's photo as a small
/// avatar for Dharma Seed), title, a line of kind, teacher and length, and
/// their played and downloaded state, with Add to library and the session's
/// menu. Tapping opens the session's own page, where the credit and licence
/// are shown.
class SessionRowsSliver extends ConsumerWidget {
  const SessionRowsSliver({
    super.key,
    required this.items,
    this.onBeforeNavigate,
  });

  final List<PackItemsModel> items;

  /// Runs before a row navigates, e.g. to dismiss the keyboard.
  final VoidCallback? onBeforeNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final played = ref.watch(playedTrackIdsProvider);
    final downloaded = ref.watch(downloadedTrackIdsProvider);
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Semantics(
          key: ValueKey('session_${item.id}'),
          button: true,
          child: SessionRow(
            title: item.title,
            detail: item.subtitle,
            artUrl: item.coverUrl ?? '',
            art: singleArt(item.id),
            completed: item.isCompleted ?? played.contains(item.id),
            downloaded: downloaded.contains(item.id),
            onTap: () {
              onBeforeNavigate?.call();
              handleNavigation(
                TypeConstants.track,
                [item.id, item.path],
                context,
                ref: ref,
              );
            },
            trailing: [
              AddToLibraryIcon(id: item.id),
              ContentActionsButton(
                id: item.id,
                fallback: MyItemDraft.fromPackItem(item),
              ),
            ],
          ),
        );
      },
    );
  }
}
