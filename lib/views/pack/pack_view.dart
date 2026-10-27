import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/utils/youtube_error_message.dart';
import 'package:medito/views/pack/widgets/youtube_playlist_empty.dart';

import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/views/dharma_seed/widgets/teacher_avatar.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/views/library/lib_course_settings.dart';
import 'package:medito/views/library/library_actions.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/views/pack/widgets/pack_complete_badge.dart';
import 'package:medito/views/pack/widgets/pack_item_widget.dart';
import 'package:medito/views/pack/widgets/pack_path_button.dart';
import 'package:medito/views/player/widgets/bottom_actions/pack_view_bottom_bar.dart';
import 'package:medito/views/player/widgets/bottom_actions/single_back_action_bar.dart';
import 'package:medito/views/categories/category_chips.dart';
import 'package:medito/widgets/attribution_notice.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/inputs/medito_segmented_tabs.dart';
import 'package:medito/widgets/save_button.dart';
import 'package:medito/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/headers/description_widget.dart';

class PackView extends ConsumerStatefulWidget {
  const PackView({super.key, required this.id});

  final String id;

  @override
  ConsumerState<PackView> createState() => _PackViewState();
}

class _PackViewState extends ConsumerState<PackView>
    with AutomaticKeepAliveClientMixin<PackView> {
  final ScrollController _scrollController = ScrollController();
  // The inline play button and the Stack it docks into, measured on scroll.
  final _playButtonKey = GlobalKey();
  final _bodyKey = GlobalKey();

  /// Where the inline play button's slot sits at scroll offset 0. The slot's
  /// on-screen top is always this minus the offset (content below the app bar
  /// moves 1:1 with scrolling), so the floating button can be placed from the
  /// current offset without waiting a frame for a measurement.
  double? _playSlotTopAtZero;

  /// SliverAppBar.large's collapsed toolbar height (Material 3).
  static const _collapsedAppBarHeight = 64.0;
  bool _markingAll = false;

  /// The course page's tab: Sessions, Summary or Teacher.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final packAsyncValue = ref.watch(packProvider(packId: widget.id));

    void popContext() => Navigator.pop(context);

    // Create a reusable back button widget
    final backButton = SingleBackButtonActionBar(onBackPressed: popContext);

    return Scaffold(
      bottomNavigationBar: packAsyncValue.when(
        data: (pack) => PackViewBottomBar(
          packId: widget.id,
          packName: pack.title,
          onBackPressed: popContext,
        ),
        loading: () => backButton,
        error: (_, _) => backButton,
      ),
      body: AdaptivePageBody(
        maxWidth: 960,
        child: packAsyncValue.when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          data: (data) {
            final playable = PackPathButton.isPlayable(data);
            if (playable) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => mounted ? _measurePlaySlot() : null,
              );
            }
            final slotTop = _playSlotTopAtZero;
            final offset = _scrollController.hasClients
                ? _scrollController.offset
                : 0.0;
            return Stack(
              key: _bodyKey,
              children: [
                _buildScaffoldWithData(
                  data,
                  ref,
                  floatingPlay: playable && slotTop != null,
                ),
                // One button, drawn above the app bar: it rides with the
                // content, then sticks straddling the collapsed bar's edge
                // (Spotify-style). No swap between copies, so no jump.
                if (playable && slotTop != null)
                  Positioned(
                    top: math.max(slotTop - offset, _dockedPlayTop),
                    right: PackPathButton.rightInset,
                    child: PackPlayButton(pack: data),
                  ),
              ],
            );
          },
          error: (err, stack) {
            final error = err is AppError ? err : const UnknownError();
            return MeditoErrorWidget(
              error: error,
              onTap: () => ref.refresh(packDataProvider(packId: widget.id)),
              isLoading: packAsyncValue.isLoading,
            );
          },
          loading: () => const FolderShimmerWidget(),
        ),
      ),
    );
  }

  void _scrollListener() {
    setState(() => {});
  }

  /// Re-measures the play slot after layout (description, tags or text scale
  /// can move it); only rebuilds when it actually moved.
  void _measurePlaySlot() {
    final slot = _playButtonKey.currentContext?.findRenderObject();
    final body = _bodyKey.currentContext?.findRenderObject();
    if (slot is! RenderBox || body is! RenderBox || !slot.attached) return;
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final atZero = slot.localToGlobal(Offset.zero, ancestor: body).dy + offset;
    final previous = _playSlotTopAtZero;
    if (previous == null || (previous - atZero).abs() > 0.5) {
      setState(() => _playSlotTopAtZero = atZero);
    }
  }

  double get _dockedPlayTop =>
      MediaQuery.paddingOf(context).top +
      _collapsedAppBarHeight -
      PackPathButton.buttonSize / 2;

  RefreshIndicator _buildScaffoldWithData(
    PackModel pack,
    WidgetRef ref, {
    bool floatingPlay = false,
  }) {
    return RefreshIndicator(
      onRefresh: () async {
        if (widget.id.startsWith('yt-playlist-')) {
          try {
            await ref
                .read(youtubeSourceProvider)
                .refresh(widget.id, force: true);
            ref.invalidate(packTrackIdsProvider);
          } on YoutubeUnavailableError catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    youtubeErrorMessage(
                      AppLocalizations.of(context)!,
                      e,
                      playlist: true,
                    ),
                  ),
                ),
              );
            }
          }
        }
        return ref.refresh(packDataProvider(packId: widget.id));
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          MeditoAppBarLarge(
            scrollController: _scrollController,
            title: pack.title,
            hasLeading: false,
            coverUrl: pack.coverUrl ?? '',
            art: courseArt(pack.id),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              // Header surface with the play button on its lower edge.
              PackPathButton(
                pack: pack,
                buttonKey: _playButtonKey,
                // The floating copy takes over once the slot is measured.
                hideButton: floatingPlay,
                child: _isCourse(pack)
                    ? _courseHeader(pack)
                    : Column(
                        children: [
                          DescriptionWidget(
                            description: pack.description ?? '',
                            endReserve: PackPathButton.endReserve,
                          ),
                          _packTags(pack),
                        ],
                      ),
              ),
              if (_isCourse(pack)) ..._courseBody(pack) else ..._sessions(pack),
              if (pack.attribution case final attribution?)
                AttributionNotice(
                  attribution: attribution,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                ),
              height32,
            ]),
          ),
        ],
      ),
    );
  }

  /// A source-backed course (a Dharma Seed retreat): it knows its sessions'
  /// kinds, its teacher or its credit, so the page shows progress, tabs and
  /// attribution. Plain packs keep the original layout.
  bool _isCourse(PackModel pack) =>
      isMyCourseId(pack.id) ||
      pack.teacher != null ||
      pack.attribution != null ||
      pack.items.any((item) => item.kind != null);

  /// Progress, the next session, and Save, on the header surface; the play
  /// button sits on its lower-right edge, so text keeps clear of it.
  Widget _courseHeader(PackModel pack) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tracks = pack.playableTracks;
    final total = tracks.length;
    final done = tracks.where((i) => i.isCompleted == true).length;
    final next = tracks.where((i) => i.isCompleted != true).firstOrNull;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        20,
        20 + PackPathButton.endReserve,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A course shows its source (teacher or channel); a playlist says
          // what it is.
          if (isMyCourseId(pack.id))
            Text(
              l10n.playlistKind,
              style: theme.textTheme.titleMedium?.copyWith(color: muted),
            )
          else if ((pack.subtitle ?? '').isNotEmpty)
            Text(
              pack.subtitle!,
              style: theme.textTheme.titleMedium?.copyWith(color: muted),
            ),
          if (total > 0) ...[
            const SizedBox(height: 12),
            Text(
              key: const ValueKey('course_progress'),
              next == null
                  ? l10n.courseAllPlayed(total)
                  : l10n.courseLeft(total - done, total),
              style: theme.textTheme.headlineMedium,
            ),
            if (next != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${done == 0 && ref.watch(resumePointProvider(next.id)).value == null ? l10n.packStart : l10n.packContinue}: '
                  '${next.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
          ],
          const SizedBox(height: 16),
          // A personal course lives in the library; it is deleted, not
          // unsaved.
          if (isMyCourseId(pack.id))
            FilledButton.tonalIcon(
              key: const ValueKey('my_course_edit'),
              onPressed: () => openMyCourseEditor(context, pack.id),
              icon: const Icon(Icons.edit_rounded),
              label: Text(l10n.myCourseEditAction),
            )
          else
            SaveButton(
              id: pack.id,
              label: l10n.courseSave,
              savedLabel: l10n.courseSaved,
            ),
          if ((ref.watch(inLibraryProvider(pack.id)).value ?? false) ||
              ref.watch(pinnedCoursesProvider).contains(pack.id))
            TextButton.icon(
              key: const ValueKey('course_pin'),
              onPressed: () => togglePinnedCourse(context, ref, pack.id),
              icon: Icon(
                ref.watch(pinnedCoursesProvider).contains(pack.id)
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
              ),
              label: Text(
                ref.watch(pinnedCoursesProvider).contains(pack.id)
                    ? l10n.unpinCourse
                    : l10n.pinCourse,
              ),
            ),
          LibCourseSettings(courseId: pack.id),
          _packTags(pack),
        ],
      ),
    );
  }

  /// Tabs (Sessions, Summary, Teacher) and the chosen tab's content. A tab
  /// with nothing to show is left out, and a lone Sessions tab shows no bar.
  List<Widget> _courseBody(PackModel pack) {
    final l10n = AppLocalizations.of(context)!;
    final hasSummary =
        (pack.description ?? '').trim().isNotEmpty || pack.attribution != null;
    final tabs = <(String, List<Widget> Function())>[
      (l10n.courseSessionsTab, () => _sessions(pack)),
      if (hasSummary) (l10n.courseSummaryTab, () => _summary(pack)),
      if (pack.teacher != null)
        (l10n.courseTeacherTab, () => [_teacher(pack.teacher!)]),
    ];
    final index = _tab.clamp(0, tabs.length - 1);
    return [
      if (tabs.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: MeditoSegmentedTabs(
            labels: [for (final tab in tabs) tab.$1],
            selectedIndex: index,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
      ...tabs[index].$2(),
    ];
  }

  List<Widget> _summary(PackModel pack) {
    final l10n = AppLocalizations.of(context)!;
    final description = (pack.description ?? '').trim();
    return [
      const SizedBox(height: 12),
      if (description.isEmpty)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            l10n.courseNoSummary,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        )
      else
        DescriptionWidget(description: description),
    ];
  }

  Widget _teacher(PackTeacher teacher) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final bio = teacher.bio.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TeacherAvatar(
                id: teacher.id,
                name: teacher.name,
                photoUrl: teacher.photoUrl,
                size: 72,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(teacher.name, style: theme.textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SelectableText(
            bio.isEmpty ? l10n.teacherNoBio : bio,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const ValueKey('course_open_teacher'),
            onPressed: () => handleNavigation(
              TypeConstants.teacher,
              [teacher.id],
              context,
              ref: ref,
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape: const StadiumBorder(),
            ),
            child: Text(teacher.name),
          ),
        ],
      ),
    );
  }

  /// The course's categories and the user's labels; nothing when it has none.
  Widget _packTags(PackModel pack) {
    return Align(
      alignment: Alignment.centerLeft,
      child: CategoryChips(
        subject: (id: pack.id, title: pack.title),
        // Right inset clears the play button on the header's lower edge.
        padding: const EdgeInsets.fromLTRB(
          20,
          0,
          20 + PackPathButton.endReserve,
          16,
        ),
      ),
    );
  }

  /// The session rows, with the "mark all" button after them. A long course
  /// recorded over several days is grouped under day headings.
  List<Widget> _sessions(PackModel pack) {
    if (pack.items.isEmpty && pack.id.startsWith('yt-playlist-')) {
      return [YoutubePlaylistEmpty(packId: pack.id)];
    }
    if (pack.items.isEmpty && isMyCourseId(pack.id)) {
      return [_myCourseEmpty()];
    }
    final groups = _dayGroups(pack.items);
    final rows = <Widget>[];
    if (pack.items.any((i) => i.section != null)) {
      rows.addAll(_sectioned(pack));
    } else if (groups == null) {
      rows.addAll(_listItems(pack, ref));
    } else {
      final first = _day(groups.first.date);
      final last = _day(groups.last.date);
      // A retreat reads as "Day 3"; a years-long series only by its dates.
      final numbered =
          first != null && last != null && last.difference(first).inDays <= 21;
      for (final group in groups) {
        rows.add(_dayHeader(group, first: numbered ? first : null));
        for (final item in group.items) {
          rows.add(
            _buildListTile(
              item,
              item == group.items.last && group == groups.last,
            ),
          );
        }
      }
    }
    return [...rows, _markAllButton(pack)];
  }

  /// Consecutive sessions sharing a recording date, for a long course. Null
  /// for a short one, one with an undated session, or one recorded in a day.
  List<_DayGroup>? _dayGroups(List<PackItemsModel> items) {
    if (items.length < 8 || items.any((i) => i.date == null)) return null;
    final groups = <_DayGroup>[];
    for (final item in items) {
      if (groups.isEmpty || groups.last.date != item.date) {
        groups.add(_DayGroup(item.date!));
      }
      groups.last.items.add(item);
    }
    return groups.length < 2 ? null : groups;
  }

  /// A `yyyy-MM-dd` date as a UTC day, so counting days between two of them
  /// is exact across a daylight-saving change.
  DateTime? _day(String date) {
    final parsed = DateTime.tryParse(date);
    return parsed == null
        ? null
        : DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  Widget _dayHeader(_DayGroup group, {DateTime? first}) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = _day(group.date);
    final formatted = date == null
        ? group.date
        : (first == null ? DateFormat.yMMMd(locale) : DateFormat.MMMEd(locale))
              .format(date);
    final label = first == null || date == null
        ? formatted
        : '${l10n.courseDay(date.difference(first).inDays + 1)} · $formatted';
    final allDone = group.items.every((item) => item.isCompleted == true);
    return Padding(
      key: ValueKey('day_${group.date}'),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (allDone) const PackCompleteBadge(size: 20),
        ],
      ),
    );
  }

  /// A personal course's sessions under the headings its maker gave them;
  /// sessions before the first heading stand on their own.
  List<Widget> _sectioned(PackModel pack) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    String? section;
    for (final (index, item) in pack.items.indexed) {
      if (item.section != null && item.section != section) {
        rows.add(
          Padding(
            key: ValueKey('section_$index'),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Semantics(
              header: true,
              child: Text(
                item.section!,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }
      section = item.section;
      final next = index + 1 < pack.items.length ? pack.items[index + 1] : null;
      rows.add(
        _buildListTile(
          item,
          next == null || (next.section != null && next.section != section),
        ),
      );
    }
    return rows;
  }

  Widget _myCourseEmpty() {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('my_course_empty'),
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.myCourseEmptyTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l10n.myCourseEmptyBody, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  List<Widget> _listItems(PackModel pack, WidgetRef ref) {
    return [
      for (final packItem in pack.items)
        _buildListTile(packItem, pack.items.last == packItem),
    ];
  }

  Widget _buildListTile(PackItemsModel item, bool isLast) {
    final unavailable = item.unavailable == true;
    final row = Semantics(
      button: true,
      child: InkWell(
        onTap: () => unavailable
            ? showSnackBar(
                context,
                AppLocalizations.of(context)!.myCourseUnavailableSnack,
              )
            : _onListItemTap(item.id, item.type, context),
        splashColor: ColorConstants.charcoal,
        child: unavailable
            // Said in words too, not only by fading the row.
            ? PackItemWidget(
                item: item.copyWith(
                  kind: AppLocalizations.of(context)!.myCourseUnavailable,
                ),
              )
            : item.type == TypeConstants.pack
            ? PackItemWidget(item: item)
            : PackItemWidget(
                item: item,
                onSetComplete: (complete) => _setComplete(item, complete),
              ),
      ),
    );
    return Column(
      children: [
        // Rows open a session, pack or link; without the role they read as
        // plain text. A session row's menu adds it to a personal course.
        if (item.type == TypeConstants.track)
          Opacity(
            opacity: unavailable ? 0.5 : 1,
            child: Row(
              children: [
                Expanded(child: row),
                ContentActionsButton(
                  id: item.id,
                  fallback: MyItemDraft.fromPackItem(item),
                  inCourse: widget.id,
                ),
              ],
            ),
          )
        else
          row,
        if (!isLast)
          const Divider(
            color: ColorConstants.charcoal,
            thickness: 0.5,
            height: 1,
          ),
      ],
    );
  }

  Future<bool> _setComplete(PackItemsModel item, bool complete) {
    return ref
        .read(packProvider(packId: widget.id).notifier)
        .setIsComplete(trackId: item.id, complete: complete);
  }

  Future<void> _markAll(bool complete) async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await ref
          .read(packProvider(packId: widget.id).notifier)
          .markAll(complete: complete);
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Widget _markAllButton(PackModel pack) {
    // What Mark all changes: a session its source lost is not one of them.
    final trackItems = pack.playableTracks;
    if (trackItems.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final allComplete = trackItems.every((item) => item.isCompleted == true);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          onPressed: _markingAll ? null : () => _markAll(!allComplete),
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: context.brandAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: ColorConstants.charcoal),
            ),
          ),
          icon: _markingAll
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.brandAccent,
                  ),
                )
              : Icon(allComplete ? Icons.remove_done : Icons.done_all),
          label: Text(
            allComplete ? l10n.markAllIncomplete : l10n.markAllComplete,
          ),
        ),
      ),
    );
  }

  Future<void> _onListItemTap(
    String id,
    String type,
    BuildContext context,
  ) async {
    // A session several courses list counts towards the one it was opened
    // from: handleNavigation writes it first, as the player reads it for its
    // cue scope.
    await handleNavigation(
      type,
      [id],
      context,
      ref: ref,
      courseId: type == TypeConstants.track ? widget.id : null,
    );
  }

  @override
  bool get wantKeepAlive => true;
}

/// Sessions of a course recorded on one day.
class _DayGroup {
  _DayGroup(this.date);

  /// `yyyy-MM-dd`.
  final String date;
  final List<PackItemsModel> items = [];
}
