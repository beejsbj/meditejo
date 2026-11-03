import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/library/lib_ids.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/providers/meditation/downloaded_track_ids_provider.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/utils/track_variant_selector.dart';
import 'package:medito/utils/youtube_error_message.dart';
import 'package:medito/providers/duration_preference_provider.dart';
import 'package:medito/providers/guide_name_preference_provider.dart';
import 'package:medito/views/categories/labels_sheet.dart';
import 'package:medito/views/library/library_actions.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/views/player/start_session.dart';
import 'package:medito/widgets/snackbar_widget.dart';
import 'package:share_plus/share_plus.dart';

/// What a row's "⋮" or long-press can do. One list for every object (a
/// course, a session, a playlist, a library entry): the sheet shows the ones
/// that apply, in this order, and hides the rest.
enum ItemAction {
  play,
  addToPlaylist,
  edit,
  duplicate,
  pin,
  save,
  download,
  markPlayed,
  goToTeacher,
  share,
  moveToPractice,
  moveToTalks,
  rename,
  labels,
  removeFromCourse,
  remove,
  delete,
}

/// What the sheet knows about the object it was opened for.
class ItemActionsSpec {
  const ItemActionsSpec({
    required this.id,
    this.title = '',
    this.fallback,
    this.inCourse,
    this.entry,
    this.teacherId,
    this.isComplete,
    this.onSetComplete,
    this.playable = true,
    this.popOnDelete = false,
  });

  final String id;

  /// The object's title, for a copy's name and the share text.
  final String title;

  /// Describes a session in case its source cannot be read when adding it.
  final MyItemDraft? fallback;

  /// The personal course this row is listed in, if any.
  final String? inCourse;

  /// The library entry, when opened from the Library. Adds the actions that
  /// only apply to what is already there (move, rename, labels, remove).
  final LibraryEntry? entry;

  /// The app ID of the teacher's page; null where the source has none, which
  /// hides "Go to teacher".
  final String? teacherId;

  /// A session row's played state and the way to change it, from inside a
  /// course. Without [onSetComplete] "Mark as played" is hidden.
  final bool? isComplete;
  final Future<bool> Function(bool complete)? onSetComplete;

  /// False for a session whose source has lost it: nothing to play, download
  /// or share.
  final bool playable;

  /// Leave the page after deleting: true only when opened from the page of
  /// the thing deleted. A row on a list just disappears from it.
  final bool popOnDelete;

  bool get isTeacher => entry?.kind == LibraryKind.teacher;
  bool get isCourse => isCourseId(id) || (entry?.isCourse ?? false);
}

/// The actions to show for [spec], in menu order. Pure: what the app knows
/// about the object right now comes in as [saved], [canSave], [pinned] and
/// [downloaded].
List<ItemAction> itemActionsFor(
  ItemActionsSpec spec, {
  bool saved = false,
  bool canSave = false,
  bool pinned = false,
  bool downloaded = false,
  bool downloadable = true,
}) {
  final entry = spec.entry;
  final mine = isMyCourseId(spec.id);
  final isTeacher = spec.isTeacher;
  final isCourse = spec.isCourse;
  final inLibrary = entry != null || saved;
  if (isTeacher) return [ItemAction.remove];
  return [
    if (spec.playable) ItemAction.play,
    ItemAction.addToPlaylist,
    if (mine) ItemAction.edit,
    if (isCourse) ItemAction.duplicate,
    if (isCourse && inLibrary) ItemAction.pin,
    if (!inLibrary && canSave) ItemAction.save,
    if (!isCourse && spec.playable && downloadable && !downloaded)
      ItemAction.download,
    if (!isCourse && spec.playable) ItemAction.markPlayed,
    if (spec.teacherId != null) ItemAction.goToTeacher,
    if (spec.playable) ItemAction.share,
    if (entry != null && entry.group == LibraryGroup.talks)
      ItemAction.moveToPractice,
    if (entry != null && entry.group == LibraryGroup.practice)
      ItemAction.moveToTalks,
    if (entry != null) ItemAction.rename,
    if (entry != null) ItemAction.labels,
    if (spec.inCourse != null && isMyCourseId(spec.inCourse!))
      ItemAction.removeFromCourse,
    if (entry != null && !mine) ItemAction.remove,
    if (mine) ItemAction.delete,
  ];
}

String _label(
  AppLocalizations l10n,
  ItemAction action, {
  required bool pinned,
  required bool complete,
}) => switch (action) {
  ItemAction.play => l10n.play,
  ItemAction.addToPlaylist => l10n.myCourseAddTo,
  ItemAction.edit => l10n.myCourseEdit,
  ItemAction.duplicate => l10n.myCourseDuplicate,
  ItemAction.pin => pinned ? l10n.unpinCourse : l10n.pinCourse,
  ItemAction.save => l10n.libraryAddToLibrary,
  ItemAction.download => l10n.downloadAudio,
  ItemAction.markPlayed =>
    complete ? l10n.itemMarkUnplayed : l10n.itemMarkPlayed,
  ItemAction.goToTeacher => l10n.itemGoToTeacher,
  ItemAction.share => l10n.share,
  ItemAction.moveToPractice => l10n.libraryMoveToPractice,
  ItemAction.moveToTalks => l10n.libraryMoveToTalks,
  ItemAction.rename => l10n.libraryRename,
  ItemAction.labels => l10n.libraryMenuLabels,
  ItemAction.removeFromCourse => l10n.myCourseRemoveRow,
  ItemAction.remove => l10n.libraryRemove,
  ItemAction.delete => l10n.myCourseDelete,
};

IconData _icon(
  ItemAction action, {
  required bool pinned,
  required bool complete,
}) => switch (action) {
  ItemAction.play => Icons.play_arrow_rounded,
  ItemAction.addToPlaylist => Icons.playlist_add_rounded,
  ItemAction.edit => Icons.edit_rounded,
  ItemAction.duplicate => Icons.copy_all_rounded,
  ItemAction.pin => pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
  ItemAction.save => Icons.bookmark_add_outlined,
  ItemAction.download => Icons.download_rounded,
  ItemAction.markPlayed =>
    complete
        ? Icons.radio_button_unchecked_rounded
        : Icons.check_circle_outline_rounded,
  ItemAction.goToTeacher => Icons.person_outline_rounded,
  ItemAction.share => Icons.share_outlined,
  ItemAction.moveToPractice ||
  ItemAction.moveToTalks => Icons.swap_horiz_rounded,
  ItemAction.rename => Icons.drive_file_rename_outline_rounded,
  ItemAction.labels => Icons.label_outline_rounded,
  ItemAction.removeFromCourse => Icons.playlist_remove_rounded,
  ItemAction.remove => Icons.bookmark_remove_outlined,
  ItemAction.delete => Icons.delete_outline_rounded,
};

/// Opens the one actions sheet for [spec] and runs the choice. Used by a
/// row's "⋮", its long-press, and the course page's own "⋮".
Future<void> showItemActions(
  BuildContext context,
  WidgetRef ref,
  ItemActionsSpec spec,
) async {
  final router = ref.read(contentRouterProvider);
  var canSave = false;
  var saved = spec.entry != null;
  if (!saved) {
    try {
      canSave = router.canSave(spec.id);
      saved = canSave && await router.isSaved(spec.id);
    } catch (e) {
      AppLogger.d('ACTIONS', 'Could not read saved state of ${spec.id}: $e');
    }
  }
  if (!context.mounted) return;
  final pinned = ref.read(pinnedCoursesProvider).contains(spec.id);
  final downloaded = ref.read(downloadedTrackIdsProvider).contains(spec.id);
  final downloadable = await _isDownloadable(ref, spec.id);
  // The played state may not have been read yet from a screen that never
  // watched it.
  try {
    await ref.read(statsProvider.future);
  } catch (e) {
    AppLogger.d('ACTIONS', 'Stats unavailable for played state: $e');
  }
  if (!context.mounted) return;
  final actions = itemActionsFor(
    spec,
    saved: saved,
    canSave: canSave,
    pinned: pinned,
    downloaded: downloaded,
    downloadable: downloadable,
  );
  final l10n = AppLocalizations.of(context)!;
  final complete =
      spec.isComplete ?? ref.read(playedTrackIdsProvider).contains(spec.id);
  final title = spec.entry?.displayTitle ?? spec.title;
  final action = await showModalBottomSheet<ItemAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          key: const ValueKey('item_actions_sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  title,
                  key: const ValueKey('item_actions_title'),
                  textAlign: TextAlign.start,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            for (final action in actions)
              ListTile(
                key: ValueKey('item_action_${action.name}'),
                leading: Icon(
                  _icon(action, pinned: pinned, complete: complete),
                ),
                title: Text(
                  _label(l10n, action, pinned: pinned, complete: complete),
                ),
                onTap: () => Navigator.pop(context, action),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  return _run(context, ref, action, spec, played: complete);
}

/// Whether the session's audio is a remote file the app can download. An
/// imported local file is already on the device. Only imported sessions are
/// checked up front (a local read); other sources are remote.
Future<bool> _isDownloadable(WidgetRef ref, String id) async {
  if (!isLibTrackId(id)) return true;
  try {
    final track = await ref.read(tracksProvider(trackId: id).future);
    final path = track.voices.firstOrNull?.audioFiles.firstOrNull?.path;
    return path == null || path.startsWith('http');
  } catch (_) {
    return true;
  }
}

/// Sets a session's played state in local stats, whichever source it is
/// from. Returns whether it stuck.
Future<bool> _setPlayed(WidgetRef ref, String id, bool complete) async {
  try {
    final stats = ref.read(statsManagerProvider);
    await stats.initialize();
    if (complete) {
      await stats.addTrackChecked(id);
    } else {
      await stats.removeTrackChecked(id);
    }
    await ref.read(statsProvider.notifier).refreshFromLocal();
    return true;
  } catch (e, st) {
    AppLogger.e('ACTIONS', 'Could not set played for $id', e, st);
    return false;
  }
}

Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  ItemAction action,
  ItemActionsSpec spec, {
  bool played = false,
}) async {
  final id = spec.id;
  final entry = spec.entry;
  switch (action) {
    case ItemAction.play:
      return _play(context, ref, spec);
    case ItemAction.addToPlaylist:
      return showAddToCourse(context, ref, id: id, fallback: spec.fallback);
    case ItemAction.edit:
      return openMyCourseEditor(context, id);
    case ItemAction.duplicate:
      return duplicateAsMyCourse(
        context,
        ref,
        packId: id,
        title: entry?.displayTitle ?? spec.title,
      );
    case ItemAction.pin:
      return togglePinnedCourse(context, ref, id);
    case ItemAction.save:
      return _save(context, ref, id);
    case ItemAction.download:
      return _download(context, ref, id);
    case ItemAction.markPlayed:
      final set = spec.onSetComplete;
      if (set != null) {
        await set(!played);
      } else {
        await _setPlayed(ref, id, !played);
      }
    case ItemAction.goToTeacher:
      return handleNavigation(
        TypeConstants.teacher,
        [spec.teacherId!, spec.teacherId!],
        context,
        ref: ref,
      );
    case ItemAction.share:
      return _share(context, spec);
    case ItemAction.moveToPractice:
      return setLibraryGroup(ref, entry!, LibraryGroup.practice);
    case ItemAction.moveToTalks:
      return setLibraryGroup(ref, entry!, LibraryGroup.talks);
    case ItemAction.rename:
      return renameLibraryEntry(context, ref, entry!);
    case ItemAction.labels:
      return showLabelsSheet(context, id: id, title: entry!.title);
    case ItemAction.removeFromCourse:
      final l10n = AppLocalizations.of(context)!;
      await ref.read(myCourseSourceProvider).removeItem(spec.inCourse!, id);
      if (context.mounted) showSnackBar(context, l10n.myCourseRemovedSnack);
    case ItemAction.remove:
      return removeFromLibrary(context, ref, entry!);
    case ItemAction.delete:
      if (await deleteMyCourse(context, ref, id) &&
          spec.popOnDelete &&
          context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
  }
}

/// The session a course's Play starts: the first playable one not yet
/// played, else the first (a finished course starts over).
@visibleForTesting
PackItemsModel? nextSessionIn(PackModel pack, Set<String> played) {
  final tracks = pack.playableTracks;
  return tracks
          .where((i) => i.isCompleted != true && !played.contains(i.id))
          .firstOrNull ??
      tracks.firstOrNull;
}

/// A session starts as it would from its course; a course starts at its
/// next unfinished session.
Future<void> _play(
  BuildContext context,
  WidgetRef ref,
  ItemActionsSpec spec,
) async {
  final id = spec.id;
  if (!spec.isCourse) {
    return startSession(
      context,
      ref,
      trackId: id,
      path: '/tracks/$id',
      courseId: spec.inCourse,
    );
  }
  try {
    // Read the raw pack first so the derived one (with completion) is ready.
    final raw = await ref.read(packDataProvider(packId: id).future);
    final PackModel pack = ref.read(packProvider(packId: id)).value ?? raw;
    final next = nextSessionIn(pack, ref.read(playedTrackIdsProvider));
    if (!context.mounted) return;
    if (next == null) {
      await openCourse(context, ref, id);
      return;
    }
    await startSession(
      context,
      ref,
      trackId: next.id,
      path: next.path,
      courseId: id,
    );
  } catch (e, st) {
    AppLogger.e('ACTIONS', 'Could not play $id', e, st);
    if (context.mounted) {
      showSnackBar(context, AppLocalizations.of(context)!.unableToLoadAudio);
    }
  }
}

Future<void> _save(BuildContext context, WidgetRef ref, String id) async {
  final l10n = AppLocalizations.of(context)!;
  final router = ref.read(contentRouterProvider);
  try {
    await router.setSaved(id, saved: true);
    if (!context.mounted) return;
    showSnackBar(
      context,
      l10n.libraryAddedSnack,
      actionLabel: l10n.undo,
      onActionPressed: () => router.setSaved(id, saved: false),
    );
  } catch (e, st) {
    AppLogger.e('ACTIONS', 'Could not add $id', e, st);
    if (context.mounted) showSnackBar(context, l10n.importFailAdd);
  }
}

/// Downloads the session's audio: the only voice and length, else the user's
/// usual ones.
Future<void> _download(BuildContext context, WidgetRef ref, String id) async {
  try {
    final track = await ref.read(tracksProvider(trackId: id).future);
    final onlyChoice =
        track.voices.length == 1 && track.voices.first.audioFiles.length == 1;
    final selection = onlyChoice
        ? (voice: track.voices.first, file: track.voices.first.audioFiles.first)
        : TrackVariantSelector.resolve(
            track,
            guideName: ref.read(guideNamePreferenceProvider),
            durationMs: ref.read(durationPreferenceProvider),
          );
    final request = PlaybackRequest.fromTrack(
      track,
      selection.voice,
      selection.file,
    );
    if (!request.remoteUrl.startsWith('http')) return;
    final key = audioFileName(
      request.trackId,
      request.fileId,
      request.remoteUrl,
    );
    final state = ref.read(audioDownloaderProvider).audioDownloadState[key];
    if (state == AudioDownloadState.downloading ||
        state == AudioDownloadState.downloaded) {
      return;
    }
    if (context.mounted) {
      showSnackBar(context, AppLocalizations.of(context)!.downloadingAudio);
    }
    await ref
        .read(audioDownloaderProvider.notifier)
        .downloadTrackAudio(request);
  } catch (e, st) {
    AppLogger.e('ACTIONS', 'Could not download $id', e, st);
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    showSnackBar(
      context,
      e is YoutubeUnavailableError
          ? youtubeErrorMessage(l10n, e)
          : l10n.unableToLoadAudio,
      backgroundColor: Colors.red,
    );
  }
}

void _share(BuildContext context, ItemActionsSpec spec) {
  final l10n = AppLocalizations.of(context)!;
  final title = spec.entry?.displayTitle ?? spec.title;
  final text = spec.isCourse
      ? l10n.sharePackText(title, 'meditejo://meditejo/packs/${spec.id}')
      : l10n.shareTrackText(title, 'meditejo://meditejo/tracks/${spec.id}');
  unawaited(SharePlus.instance.share(ShareParams(text: text)));
}
