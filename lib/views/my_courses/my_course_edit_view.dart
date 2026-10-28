import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/widgets/snackbar_widget.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/network_image_widget.dart';

/// Edits a personal course: title, description, kind, cover, and its
/// sessions and headings, dragged into order or removed. Nothing is written
/// until Save; leaving with changes asks first.
class MyCourseEditView extends ConsumerStatefulWidget {
  const MyCourseEditView({super.key, required this.courseId});

  final String courseId;

  @override
  ConsumerState<MyCourseEditView> createState() => _MyCourseEditViewState();
}

class _MyCourseEditViewState extends ConsumerState<MyCourseEditView> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  MyCourseEdit? _initial;
  MyCourseEdit? _edit;

  /// Each line with a key that survives reordering, and a controller for
  /// headings.
  final List<_Line> _lines = [];
  var _nextKey = 0;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final edit = await ref.read(myCourseSourceProvider).edit(widget.courseId);
    if (!mounted) return;
    if (edit == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _initial = edit;
      _edit = edit;
      _title.text = edit.title;
      _description.text = edit.description;
      _lines
        ..clear()
        ..addAll(edit.lines.map(_wrap));
    });
  }

  _Line _wrap(MyCourseLine line) => _Line(
    key: _nextKey++,
    line: line,
    controller: line.isHeading
        ? TextEditingController(text: line.heading)
        : null,
  );

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    for (final line in _lines) {
      line.controller?.dispose();
    }
    super.dispose();
  }

  /// The edit as it stands on screen.
  MyCourseEdit get _current => _edit!.copyWith(
    title: _title.text,
    description: _description.text,
    lines: [
      for (final l in _lines)
        l.line.isHeading ? MyCourseLine.heading(l.controller!.text) : l.line,
    ],
  );

  bool get _dirty {
    final initial = _initial;
    if (initial == null || _edit == null) return false;
    final now = _current;
    return now.title != initial.title ||
        now.description != initial.description ||
        now.coverUrl != initial.coverUrl ||
        now.group != initial.group ||
        !_sameLines(now.lines, initial.lines);
  }

  static bool _sameLines(List<MyCourseLine> a, List<MyCourseLine> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].isHeading != b[i].isHeading) return false;
      if (a[i].isHeading
          ? a[i].heading != b[i].heading
          : a[i].item!.id != b[i].item!.id) {
        return false;
      }
    }
    return true;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final l10n = AppLocalizations.of(context)!;
      var edit = _current;
      // Blank is named in the user's language, not the source's.
      if (edit.title.trim().isEmpty) {
        edit = edit.copyWith(title: l10n.myCourseDefaultTitle);
      }
      await ref.read(myCourseSourceProvider).save(widget.courseId, edit);
      _initial = _current;
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      AppLogger.e('MY_COURSES', 'Could not save ${widget.courseId}', e, st);
      if (mounted) {
        setState(() => _saving = false);
        showSnackBar(context, AppLocalizations.of(context)!.myCourseSaveFailed);
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    final l10n = AppLocalizations.of(context)!;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.myCourseDiscardTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.myCourseKeepEditing),
          ),
          TextButton(
            key: const ValueKey('my_course_discard'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.myCourseDiscard),
          ),
        ],
      ),
    );
    return discard == true;
  }

  void _addHeading() =>
      setState(() => _lines.insert(0, _wrap(const MyCourseLine.heading(''))));

  void _remove(_Line line) => setState(() {
    _lines.remove(line);
    // Disposed after the frame that stops showing its field.
    final controller = line.controller;
    if (controller != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
  });

  void _reorder(int from, int to) => setState(() {
    _lines.insert(to, _lines.removeAt(from));
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final edit = _edit;
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _initial = _current;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.myCourseEdit),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                key: const ValueKey('my_course_save'),
                onPressed: edit == null || _saving ? null : _save,
                child: Text(l10n.myCourseSave),
              ),
            ),
          ],
        ),
        body: edit == null
            ? const Center(child: CircularProgressIndicator())
            : ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom + 24,
                ),
                header: _header(context, edit),
                footer: _footer(context),
                itemCount: _lines.length,
                onReorderItem: _reorder,
                itemBuilder: (context, index) =>
                    _lineTile(context, _lines[index], index),
              ),
      ),
    );
  }

  Widget _header(BuildContext context, MyCourseEdit edit) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final label = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('my_course_title'),
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.myCourseTitleLabel),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('my_course_description'),
            controller: _description,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.myCourseDescriptionLabel,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Text(l10n.myCourseKindLabel, style: label),
          const SizedBox(height: 8),
          MyCourseKindPicker(
            value: edit.group,
            onChanged: (group) =>
                setState(() => _edit = edit.copyWith(group: group)),
          ),
          const SizedBox(height: 20),
          Text(l10n.myCourseCoverLabel, style: label),
          const SizedBox(height: 8),
          _coverPicker(context, edit),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Text(l10n.myCourseSessionsLabel, style: label)),
              TextButton.icon(
                key: const ValueKey('my_course_add_heading'),
                onPressed: _addHeading,
                icon: const Icon(Icons.title_rounded),
                label: Text(l10n.myCourseAddHeading),
              ),
            ],
          ),
          if (_lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                l10n.myCourseEditEmpty,
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }

  /// Generated art first, then each session's artwork.
  Widget _coverPicker(BuildContext context, MyCourseEdit edit) {
    final l10n = AppLocalizations.of(context)!;
    final current = _current;
    final choices = ['', ...current.coverChoices];
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: choices.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final url = choices[index];
          final selected = current.effectiveCoverUrl == url;
          return Semantics(
            button: true,
            selected: selected,
            label: index == 0
                ? l10n.myCourseCoverGenerated
                : l10n.myCourseCoverChoice(index),
            child: InkWell(
              key: ValueKey('my_course_cover_$index'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _edit = edit.copyWith(coverUrl: url)),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    width: 2,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox.square(
                    dimension: 62,
                    child: NetworkImageWidget(
                      url: url,
                      art: courseArt(widget.courseId),
                      shouldCache: true,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('my_course_delete'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () async {
            if (await deleteMyCourse(context, ref, widget.courseId) &&
                context.mounted) {
              _initial = _current;
              // The course page under this one is gone too.
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          },
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(l10n.myCourseDelete),
        ),
      ),
    );
  }

  Widget _lineTile(BuildContext context, _Line line, int index) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final handle = ReorderableDragStartListener(
      index: index,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Icon(
          Icons.drag_handle_rounded,
          semanticLabel: l10n.myCourseDragHandle,
        ),
      ),
    );
    final remove = IconButton(
      key: ValueKey('my_course_remove_${line.key}'),
      tooltip: l10n.myCourseRemoveRow,
      icon: const Icon(Icons.close_rounded),
      onPressed: () => _remove(line),
    );

    if (line.line.isHeading) {
      return Padding(
        key: ValueKey('line_${line.key}'),
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            handle,
            Expanded(
              child: TextField(
                key: ValueKey('my_course_heading_${line.key}'),
                controller: line.controller,
                textCapitalization: TextCapitalization.sentences,
                style: theme.textTheme.titleMedium,
                decoration: InputDecoration(
                  hintText: l10n.myCourseHeadingHint,
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            remove,
          ],
        ),
      );
    }

    final item = line.line.item!;
    final minutes = (item.durationMs / Duration.millisecondsPerMinute).round();
    final detail = [
      if (line.line.unavailable)
        l10n.myCourseUnavailable
      else if (item.kind.isNotEmpty)
        item.kind,
      if (item.subtitle.isNotEmpty) item.subtitle,
      if (minutes > 0) l10n.courseSessionLength(minutes),
    ].join(' · ');
    return Material(
      key: ValueKey('line_${line.key}'),
      type: MaterialType.transparency,
      child: Opacity(
        opacity: line.line.unavailable ? 0.5 : 1,
        child: Row(
          children: [
            handle,
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox.square(
                dimension: 40,
                child: NetworkImageWidget(
                  url: item.coverUrl,
                  art: singleArt(item.id),
                  shouldCache: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
            remove,
          ],
        ),
      ),
    );
  }
}

class _Line {
  _Line({required this.key, required this.line, this.controller});

  final int key;
  final MyCourseLine line;
  final TextEditingController? controller;
}
