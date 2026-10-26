import 'package:medito/services/youtube/youtube_source.dart';

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/library/import_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/services/library/folder_import.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/import_service.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/link_classifier.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/views/library/episode_picker.dart';
import 'package:medito/views/library/library_actions.dart';
import 'package:medito/views/library/library_format.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/widgets/attribution_notice.dart';
import 'package:medito/widgets/network_image_widget.dart';
import 'package:medito/widgets/snackbar_widget.dart';

/// Opens the import screen and, when something was added, says so with a way
/// to open it. With no [context] (a share arriving while the app is open) the
/// app's navigator is used.
Future<void> openImport(
  BuildContext? context,
  WidgetRef ref, {
  String? text,
  List<PickedFile> files = const [],
}) async {
  final navigator = context != null && context.mounted
      ? Navigator.of(context)
      : navigatorKey.currentState;
  if (navigator == null) return;
  final result = await navigator.push<ImportResult>(
    MaterialPageRoute(
      builder: (_) => ImportView(initialText: text, initialFiles: files),
    ),
  );
  final shown = navigatorKey.currentContext ?? context;
  if (result == null || shown == null || !shown.mounted) return;
  final l10n = AppLocalizations.of(shown)!;
  showSnackBar(
    shown,
    result.alreadyPresent ? l10n.libraryAlreadyIn : l10n.libraryAddedSnack,
    actionLabel: l10n.libraryOpen,
    onActionPressed: () {
      final target = navigatorKey.currentContext;
      if (target != null && target.mounted) {
        openLibraryId(target, ref, result.entryId, result.kind);
      }
    },
  );
}

/// Paste or share a link, or pick files; see a calm preview; add it. One
/// primary action.
class ImportView extends ConsumerStatefulWidget {
  const ImportView({super.key, this.initialText, this.initialFiles = const []});

  /// A link or text that arrived from outside (a share), previewed at once.
  final String? initialText;

  /// Files that arrived from outside, previewed at once.
  final List<PickedFile> initialFiles;

  @override
  ConsumerState<ImportView> createState() => _ImportViewState();
}

enum _Phase { idle, resolving, preview, adding }

class _ImportViewState extends ConsumerState<ImportView> {
  final _field = TextEditingController();
  final _titleField = TextEditingController();

  _Phase _phase = _Phase.idle;
  ImportPreview? _preview;
  ImportFailureReason? _failure;
  String? _clipboardLink;
  bool _editingTitle = false;
  var _kind = LibraryKind.course;
  var _alreadyInLibrary = false;
  var _group = LibraryGroup.practice;
  var _order = 'oldest';

  /// The episode a Single will add; the preview's default until picked.
  String? _episodeId;

  /// A folder is being picked, listed or copied, and how far the copy is.
  var _folderBusy = false;
  final _folderProgress = ValueNotifier<FolderProgress?>(null);
  late final ImportPickers _pickers;

  /// Bumped on every new request, so a slow earlier answer is dropped.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _pickers = ref.read(importPickersProvider);
    final text = widget.initialText?.trim();
    if (widget.initialFiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _resolveFiles(widget.initialFiles),
      );
    } else if (text != null && text.isNotEmpty) {
      _field.text = firstLinkIn(text) ?? text;
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
    }
  }

  @override
  void dispose() {
    // A folder's copies are only for this screen: stop one in progress and
    // drop any that nothing took.
    unawaited(_pickers.discardFolderImport());
    _folderProgress.dispose();
    _field.dispose();
    _titleField.dispose();
    super.dispose();
  }

  Future<void> _checkClipboard() async {
    final link = await ref.read(clipboardLinkReaderProvider)();
    if (mounted && link != null && _field.text.isEmpty) {
      setState(() => _clipboardLink = link);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    _field.text = firstLinkIn(text) ?? text;
    await _resolve();
  }

  void _useClipboard() {
    final link = _clipboardLink;
    if (link == null) return;
    _field.text = link;
    _resolve();
  }

  Future<void> _resolve() async {
    final input = _field.text.trim();
    FocusManager.instance.primaryFocus?.unfocus();
    if (input.isEmpty) {
      setState(() {
        _phase = _Phase.idle;
        _preview = null;
        _failure = ImportFailureReason.empty;
      });
      return;
    }
    await _run(() => ref.read(importServiceProvider).resolve(input));
  }

  Future<void> _resolveFiles(List<PickedFile> files) =>
      _run(() => ref.read(importServiceProvider).resolveFiles(files));

  /// [resolve] may answer null: nothing was chosen, so nothing changes.
  Future<void> _run(Future<ImportPreview?> Function() resolve) async {
    final request = ++_request;
    setState(() {
      _phase = _Phase.resolving;
      _failure = null;
      _preview = null;
      _clipboardLink = null;
    });
    try {
      final preview = await resolve();
      if (!mounted || request != _request) return;
      if (preview == null) {
        setState(() => _phase = _Phase.idle);
        return;
      }
      setState(() {
        _preview = preview;
        _kind = preview.kind;
        _episodeId = preview.defaultEpisodeId;
        _alreadyInLibrary = preview.alreadyInLibrary;
        _group = preview.group;
        _order = 'oldest';
        _editingTitle = false;
        _titleField.text = preview.title;
        _phase = _Phase.preview;
      });
    } on ImportFailure catch (e) {
      AppLogger.d('LIBRARY', 'Import did not resolve: $e');
      if (!mounted || request != _request) return;
      setState(() {
        _failure = e.reason;
        _phase = _Phase.idle;
      });
    } catch (e, st) {
      AppLogger.e('LIBRARY', 'Import failed', e, st);
      if (!mounted || request != _request) return;
      setState(() {
        _failure = ImportFailureReason.unreachable;
        _phase = _Phase.idle;
      });
    }
  }

  Future<void> _pickFiles() async {
    final files = await ref.read(importPickersProvider).pickAudioFiles();
    if (files == null || files.isEmpty || !mounted) return;
    _field.clear();
    await _resolveFiles(files);
  }

  Future<void> _pickFolder() async {
    _folderProgress.value = null;
    setState(() => _folderBusy = true);
    try {
      await _run(() async {
        final folder = await _pickers.pickFolder(
          onProgress: (progress) {
            if (mounted) _folderProgress.value = progress;
          },
        );
        if (folder == null || !mounted) return null;
        final service = ref.read(importServiceProvider);
        final path = folder.path;
        if (path != null) {
          // iOS: the folder is read where it is.
          _field.text = path;
          return service.resolve(path);
        }
        _field.clear();
        return service.resolveFiles(
          folder.files,
          suggestedTitle: folder.name,
          folder: true,
          unreadable: folder.unreadable,
        );
      });
    } finally {
      if (mounted) setState(() => _folderBusy = false);
    }
  }

  Future<void> _cancelFolder() => _pickers.cancelFolderImport();

  String _selectedId(
    ImportPreview preview,
    LibraryKind kind, [
    String? episodeId,
  ]) => ImportService.selectedId(preview, kind, episodeId: episodeId);

  /// Whether what the choices now add is already in the library. Only the
  /// kinds with a choice of what to add can differ from the preview.
  Future<void> _checkSelection(
    ImportPreview preview,
    LibraryKind kind, [
    String? episodeId,
  ]) async {
    if (preview.origin != ImportOrigin.youtube &&
        preview.origin != ImportOrigin.feed) {
      return;
    }
    final present = await ref
        .read(libraryStoreProvider)
        .contains(_selectedId(preview, kind, episodeId));
    if (mounted &&
        _preview == preview &&
        _kind == kind &&
        _episodeId == episodeId) {
      setState(() => _alreadyInLibrary = present);
    }
  }

  /// The title the preview starts with for [kind] and [episodeId]: the list's
  /// own, or the episode's for a Single.
  String _autoTitle(
    ImportPreview preview,
    LibraryKind kind,
    String? episodeId,
  ) {
    if (kind == LibraryKind.single) {
      final episode = preview.episode(episodeId);
      if (episode != null) return episode.title;
    }
    return preview.title;
  }

  /// Follows a change of kind or episode: a title the user has not edited
  /// follows it (and so does YouTube's detected group); one they typed stays.
  void _follow(ImportPreview preview, LibraryKind kind, String? episodeId) {
    final previous = _autoTitle(preview, _kind, _episodeId);
    final next = _autoTitle(preview, kind, episodeId);
    if (_titleField.text == previous) _titleField.text = next;
    if (preview.origin == ImportOrigin.youtube &&
        _group == youtubeGroup(previous)) {
      _group = youtubeGroup(next);
    }
    _kind = kind;
    _episodeId = episodeId;
    _alreadyInLibrary = false;
    unawaited(_checkSelection(preview, kind, episodeId));
  }

  Future<void> _chooseEpisode(ImportPreview preview) async {
    final picked = await showEpisodePicker(
      context,
      episodes: preview.episodes,
      selectedId: _episodeId ?? preview.defaultEpisodeId,
      latestId: preview.origin == ImportOrigin.feed
          ? preview.defaultEpisodeId
          : null,
    );
    if (picked == null || !mounted || picked == _episodeId) return;
    setState(() => _follow(preview, _kind, picked));
  }

  Future<void> _add() async {
    final preview = _preview;
    if (preview == null || _phase == _Phase.adding) return;
    final l10n = AppLocalizations.of(context)!;
    if (_alreadyInLibrary) {
      Navigator.pop(
        context,
        ImportResult(
          entryId: _selectedId(preview, _kind, _episodeId),
          kind: _kind,
          alreadyPresent: true,
        ),
      );
      return;
    }
    setState(() => _phase = _Phase.adding);
    final typed = _titleField.text.trim();
    try {
      final result = await ref
          .read(importServiceProvider)
          .add(
            preview,
            ImportChoice(
              kind: _kind,
              group: _group,
              title: typed.isEmpty || typed == preview.title ? null : typed,
              episodeOrder: _order,
              episodeId: _episodeId,
            ),
          );
      if (mounted) Navigator.pop(context, result);
    } on ImportFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e.reason;
        _phase = _Phase.preview;
      });
    } catch (e, st) {
      AppLogger.e('LIBRARY', 'Adding to the library failed', e, st);
      if (!mounted) return;
      showSnackBar(context, l10n.importFailAdd);
      setState(() => _phase = _Phase.preview);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final preview = _preview;
    final busy = _phase == _Phase.resolving || _phase == _Phase.adding;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.importTitle)),
      body: AdaptivePageBody(
        maxWidth: 640,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            padding16,
            padding8,
            padding16,
            MediaQuery.paddingOf(context).bottom + padding24,
          ),
          children: [
            TextField(
              key: const ValueKey('import_field'),
              controller: _field,
              enabled: _phase != _Phase.adding && !_folderBusy,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              onSubmitted: (_) => _resolve(),
              // Changing the link drops a preview of the old one, and abandons
              // one still resolving, so Add can never add something other
              // than what the field shows.
              onChanged: (_) {
                final resolving = _phase == _Phase.resolving;
                if (resolving ||
                    (_preview != null && _phase == _Phase.preview)) {
                  if (resolving) _request++;
                  setState(() {
                    _preview = null;
                    _phase = _Phase.idle;
                  });
                }
              },
              decoration: InputDecoration(
                hintText: l10n.importFieldHint,
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const ValueKey('import_paste'),
                      tooltip: l10n.importPaste,
                      onPressed: busy ? null : _paste,
                      icon: const Icon(Icons.content_paste_rounded),
                    ),
                    IconButton(
                      key: const ValueKey('import_go'),
                      tooltip: l10n.importPreviewAction,
                      onPressed: busy ? null : _resolve,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                ),
              ),
            ),
            if (_clipboardLink case final link? when preview == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.importClipboard(
                          Uri.tryParse(link)?.host.isNotEmpty == true
                              ? Uri.parse(link).host
                              : link,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('import_use_clipboard'),
                      onPressed: _useClipboard,
                      child: Text(l10n.importUseClipboard),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('import_files'),
                    onPressed: busy ? null : _pickFiles,
                    icon: const Icon(Icons.audio_file_outlined),
                    label: Text(l10n.importChooseFiles),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('import_folder'),
                    onPressed: busy ? null : _pickFolder,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(l10n.importChooseFolder),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_phase == _Phase.resolving && _folderBusy)
              _FolderProgressCard(
                progress: _folderProgress,
                onCancel: _cancelFolder,
              )
            else if (_phase == _Phase.resolving)
              _Looking(label: l10n.importLooking)
            else if (_failure != null)
              _FailureCard(reason: _failure!)
            else if (preview == null)
              Text(
                l10n.importHelp,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            if (preview != null && _phase != _Phase.resolving) ...[
              if (_failure != null) const SizedBox(height: 12),
              _PreviewCard(
                preview: preview,
                alreadyInLibrary: _alreadyInLibrary,
                titleField: _titleField,
                editingTitle: _editingTitle,
                onEditTitle: () => setState(() => _editingTitle = true),
                onTitleDone: () => setState(() => _editingTitle = false),
                kind: _kind,
                group: _group,
                order: _order,
                episodeId: _episodeId,
                onChooseEpisode: () => _chooseEpisode(preview),
                onKind: (value) =>
                    setState(() => _follow(preview, value, _episodeId)),
                onGroup: (value) => setState(() => _group = value),
                onOrder: (value) => setState(() => _order = value),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('import_add'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: busy ? null : _add,
                child: _phase == _Phase.adding
                    ? Text(l10n.importAdding)
                    : Text(
                        _alreadyInLibrary
                            ? l10n.libraryOpen
                            : l10n.importPrimary,
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Looking extends StatelessWidget {
  const _Looking({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(width: 12),
        Text(label),
      ],
    ),
  );
}

/// A plain sentence about what went wrong, never a stack trace or a code.
class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.reason});

  final ImportFailureReason reason;

  String _message(AppLocalizations l10n) => switch (reason) {
    ImportFailureReason.empty => l10n.importFailEmpty,
    ImportFailureReason.unrecognised => l10n.importFailUnrecognised,
    ImportFailureReason.youtubeUnavailable => l10n.youtubeUnavailable,
    ImportFailureReason.youtubeAgeRestricted => l10n.youtubeAgeRestricted,
    ImportFailureReason.youtubePrivate => l10n.youtubePrivate,
    ImportFailureReason.youtubeRateLimited => l10n.youtubeRateLimited,
    ImportFailureReason.unsupportedHost => l10n.importFailUnsupportedHost,
    ImportFailureReason.offline => l10n.importFailOffline,
    ImportFailureReason.notFound => l10n.importFailNotFound,
    ImportFailureReason.unreachable => l10n.importFailUnreachable,
    ImportFailureReason.noFeedOrAudio => l10n.importFailNoFeed,
    ImportFailureReason.noEpisodes => l10n.importFailNoEpisodes,
    ImportFailureReason.brokenFeed => l10n.importFailBrokenFeed,
    ImportFailureReason.dharmaSeedMissing => l10n.importFailDharmaSeed,
    ImportFailureReason.fileMissing => l10n.importFailFile,
    ImportFailureReason.noAudioFiles => l10n.importFailNoAudio,
    ImportFailureReason.folderEmpty => l10n.importFailFolderEmpty,
    ImportFailureReason.folderTooLarge => l10n.importFailFolderTooLarge,
    ImportFailureReason.folderNoSpace => l10n.importFailFolderNoSpace,
    ImportFailureReason.folderUnreadable => l10n.importFailFolderUnreadable,
    ImportFailureReason.folderUnavailable => l10n.importFailFolderUnavailable,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('import_failure'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_message(l10n), style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.preview,
    required this.alreadyInLibrary,
    required this.titleField,
    required this.editingTitle,
    required this.onEditTitle,
    required this.onTitleDone,
    required this.kind,
    required this.group,
    required this.order,
    required this.episodeId,
    required this.onChooseEpisode,
    required this.onKind,
    required this.onGroup,
    required this.onOrder,
  });

  final ImportPreview preview;
  final bool alreadyInLibrary;
  final TextEditingController titleField;
  final bool editingTitle;
  final VoidCallback onEditTitle;
  final VoidCallback onTitleDone;
  final LibraryKind kind;
  final LibraryGroup group;
  final String order;

  /// The episode a Single will add, when the list has episodes.
  final String? episodeId;
  final VoidCallback onChooseEpisode;
  final ValueChanged<LibraryKind> onKind;
  final ValueChanged<LibraryGroup> onGroup;
  final ValueChanged<String> onOrder;

  String _caption(AppLocalizations l10n, LibraryKind kind) {
    final course = kind == LibraryKind.course;
    return switch (preview.origin) {
      ImportOrigin.feed =>
        course
            ? l10n.importCaptionCourseAll(preview.itemCount)
            : l10n.importCaptionLatest,
      ImportOrigin.youtube =>
        course ? l10n.youtubeCourseCaption : l10n.youtubeSingleCaption,
      ImportOrigin.localFiles =>
        course ? l10n.importCaptionFilesCourse : l10n.importCaptionFilesSingles,
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final title = titleField.text.trim().isEmpty
        ? l10n.importDefaultTitle
        : titleField.text.trim();

    // A Single from a list is one episode: it, not the list, is described.
    final selected = kind == LibraryKind.single
        ? preview.episode(episodeId)
        : null;
    final displayedDuration = selected != null
        ? selected.durationMs ?? 0
        : preview.durationMs;
    final selectedSubtitle = selected != null && selected.subtitle.isNotEmpty
        ? selected.subtitle
        : preview.subtitle;
    final selectedArtwork = selected != null && selected.artworkUrl.isNotEmpty
        ? selected.artworkUrl
        : preview.artworkUrl;
    final counts = [
      if (kind != LibraryKind.teacher || preview.itemCount > 0)
        l10n.librarySessions(selected != null ? 1 : preview.itemCount),
      if (displayedDuration > 0)
        preview.durationComplete || selected != null
            ? formatLongDuration(displayedDuration)
            : l10n.importAtLeast(formatLongDuration(displayedDuration)),
    ].join(' · ');

    return Container(
      key: const ValueKey('import_preview'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(
                  preview.kind == LibraryKind.teacher ? 44 : 12,
                ),
                child: SizedBox.square(
                  dimension: 88,
                  child: NetworkImageWidget(
                    url: selectedArtwork,
                    shouldCache: true,
                    seed: title,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (editingTitle)
                      TextField(
                        key: const ValueKey('import_title_field'),
                        controller: titleField,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: l10n.importTitleLabel,
                          isDense: true,
                        ),
                        onSubmitted: (_) => onTitleDone(),
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              key: const ValueKey('import_title'),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('import_edit_title'),
                            tooltip: l10n.libraryRename,
                            visualDensity: VisualDensity.compact,
                            onPressed: onEditTitle,
                            icon: const Icon(Icons.edit_outlined, size: 20),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        preview.sourceLabel,
                        if (selectedSubtitle.isNotEmpty &&
                            preview.origin != ImportOrigin.audioUrl)
                          selectedSubtitle,
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                    if (counts.isNotEmpty)
                      Text(
                        counts,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (preview.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              preview.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (preview.firstItems.isNotEmpty && selected == null) ...[
            const SizedBox(height: 12),
            for (final item in preview.firstItems)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (item.durationMs != null && item.durationMs! > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          formatLongDuration(item.durationMs!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (preview.itemCount > preview.firstItems.length)
              Text(
                '…',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
          ],
          if (preview.skippedItems > 0) ...[
            const SizedBox(height: 8),
            Text(
              l10n.importSkipped(preview.skippedItems),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          if (preview.unreadableItems > 0) ...[
            const SizedBox(height: 8),
            Text(
              l10n.importUnreadable(preview.unreadableItems),
              key: const ValueKey('import_unreadable'),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          if (preview.attribution case final attribution?)
            AttributionNotice(
              attribution: attribution,
              compact: true,
              padding: const EdgeInsets.only(top: 4),
            ),
          if (alreadyInLibrary) ...[
            const SizedBox(height: 8),
            Text(
              l10n.importInLibraryNote,
              key: const ValueKey('import_already'),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          // Choices stay while one thing is being picked from a list, so an
          // episode that is already kept can be swapped for another.
          if (!alreadyInLibrary ||
              preview.origin == ImportOrigin.youtube ||
              (preview.origin == ImportOrigin.feed &&
                  kind == LibraryKind.single)) ...[
            if (preview.hasKindChoice) ...[
              const SizedBox(height: 16),
              SegmentedButton<LibraryKind>(
                key: const ValueKey('import_kind'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: LibraryKind.course,
                    label: Text(l10n.importKindCourse),
                  ),
                  ButtonSegment(
                    value: LibraryKind.single,
                    label: Text(l10n.importKindSingle),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: (value) => onKind(value.first),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _caption(l10n, kind),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
            ],
            if (selected != null && preview.hasEpisodeChoice) ...[
              const SizedBox(height: 8),
              _EpisodeRow(
                key: const ValueKey('import_episode'),
                episode: selected,
                latest:
                    preview.origin == ImportOrigin.feed &&
                    selected.id == preview.defaultEpisodeId,
                onChange: onChooseEpisode,
              ),
            ],
            if (preview.origin == ImportOrigin.feed &&
                kind == LibraryKind.course) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('import_order_oldest'),
                    label: Text(l10n.importOrderOldest),
                    selected: order == 'oldest',
                    onSelected: (_) => onOrder('oldest'),
                  ),
                  ChoiceChip(
                    key: const ValueKey('import_order_newest'),
                    label: Text(l10n.importOrderNewest),
                    selected: order == 'newest',
                    onSelected: (_) => onOrder('newest'),
                  ),
                ],
              ),
            ],
            if (kind != LibraryKind.teacher && !alreadyInLibrary) ...[
              const SizedBox(height: 16),
              Text(l10n.importCountsAs, style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              SegmentedButton<LibraryGroup>(
                key: const ValueKey('import_group'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: LibraryGroup.practice,
                    label: Text(l10n.importGroupPractice),
                  ),
                  ButtonSegment(
                    value: LibraryGroup.talks,
                    label: Text(l10n.importGroupTalk),
                  ),
                ],
                selected: {group},
                onSelectionChanged: (value) => onGroup(value.first),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Copying a picked folder: what is happening, how far, and a way out.
class _FolderProgressCard extends StatelessWidget {
  const _FolderProgressCard({required this.progress, required this.onCancel});

  final ValueListenable<FolderProgress?> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ValueListenableBuilder<FolderProgress?>(
      valueListenable: progress,
      builder: (context, value, _) => Padding(
        key: const ValueKey('import_folder_progress'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                value == null || value.filesTotal < 1
                    ? l10n.importFolderLooking
                    : l10n.importFolderCopying(
                        min(value.filesDone + 1, value.filesTotal),
                        value.filesTotal,
                      ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: value?.fraction),
            if (value != null && value.name.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                value.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('import_folder_cancel'),
                onPressed: onCancel,
                child: Text(l10n.importFolderCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The episode a Single will add, with a way to pick another.
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    super.key,
    required this.episode,
    required this.latest,
    required this.onChange,
  });

  final ImportEpisode episode;
  final bool latest;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.importEpisodeLabel, style: theme.textTheme.bodySmall),
              Text(
                episode.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                episodeDetail(context, episode, latest: latest),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        TextButton(
          key: const ValueKey('import_episode_change'),
          onPressed: onChange,
          child: Text(l10n.importEpisodeChange),
        ),
      ],
    );
  }
}
