import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/utils/youtube_error_message.dart';
import 'package:medito/views/pack/widgets/youtube_playlist_empty.dart';

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/views/dharma_seed/widgets/teacher_avatar.dart';
import 'package:medito/widgets/teacher_link.dart';
import 'package:medito/views/library/lib_course_settings.dart';
import 'package:medito/views/library/library_format.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/views/library/item_actions.dart';
import 'package:medito/services/youtube/youtube_ids.dart';
import 'package:medito/services/my_courses/my_course_source.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/views/pack/widgets/pack_complete_badge.dart';
import 'package:medito/views/pack/widgets/pack_item_widget.dart';
import 'package:medito/views/pack/widgets/course_actions.dart';
import 'package:medito/views/player/widgets/bottom_actions/pack_view_bottom_bar.dart';
import 'package:medito/views/player/widgets/bottom_actions/single_back_action_bar.dart';
import 'package:medito/views/categories/category_chips.dart';
import 'package:medito/widgets/attribution_notice.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/inputs/medito_segmented_tabs.dart';
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

  /// The header's Play, measured on scroll to know when it has gone.
  final _playButtonKey = GlobalKey();

  /// Whether the header's Play has scrolled under the app bar, so the bottom
  /// bar shows its copy.
  bool _barPlay = false;

  /// The pinned tab bar, to keep it in place when the tab changes.
  final _tabsKey = GlobalKey(debugLabel: 'course_tabs');

  /// Set when a tab change kept the tabs pinned: a short tab then gets room
  /// below it ([_filler]) until the user scrolls back above where it ends.
  bool _holdTabs = false;
  double _filler = 0;

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
    _scrollController.dispose();
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
          onBackPressed: popContext,
          showPlay: _barPlay,
        ),
        loading: () => backButton,
        error: (_, _) => backButton,
      ),
      body: AdaptivePageBody(
        maxWidth: 960,
        child: packAsyncValue.when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          data: (data) => _buildScaffoldWithData(data, ref),
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
    // The app bar fades its art with the offset.
    setState(() {
      // Back within the tab's own length: the room below is not needed.
      final position = _scrollController.position;
      if (_holdTabs &&
          position.pixels <= math.max(0, position.maxScrollExtent - _filler)) {
        _holdTabs = false;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateBarPlay());
  }

  /// Shows Play in the bottom bar once the header's own has scrolled under
  /// the collapsed app bar, and takes it away when it comes back.
  void _updateBarPlay() {
    if (!mounted) return;
    final box = _playButtonKey.currentContext?.findRenderObject();
    var gone = false;
    if (box is RenderBox && box.attached && box.hasSize) {
      final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      gone =
          bottom <= MediaQuery.paddingOf(context).top + _collapsedAppBarHeight;
    }
    if (gone != _barPlay) setState(() => _barPlay = gone);
  }

  RefreshIndicator _buildScaffoldWithData(PackModel pack, WidgetRef ref) {
    final tabs = _isCourse(pack) ? _tabs(pack) : null;
    final index = tabs == null ? 0 : _tab.clamp(0, tabs.length - 1);
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
          SliverToBoxAdapter(
            child: ColoredBox(
              color: Theme.of(context).cardColor,
              child: _header(pack),
            ),
          ),
          // The tabs stay under the collapsed title while the sessions
          // scroll (#92). A lone Sessions tab shows no bar.
          if (tabs != null && tabs.length > 1)
            PinnedHeaderSliver(
              child: ColoredBox(
                key: _tabsKey,
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: MeditoSegmentedTabs(
                    labels: [for (final tab in tabs) tab.$1],
                    selectedIndex: index,
                    onChanged: (i) => _selectTab(i, pack),
                  ),
                ),
              ),
            ),
          SliverList(
            delegate: SliverChildListDelegate([
              if (tabs != null) ...tabs[index].$2() else ..._sessions(pack),
              if (pack.attribution case final attribution?)
                AttributionNotice(
                  attribution: attribution,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                ),
              height32,
            ]),
          ),
          // A short tab (Summary, Teacher) opened from deep in the sessions
          // keeps the tabs pinned, with room below, instead of the page
          // springing back down under them. Only then: a short course at
          // rest does not scroll into blank space.
          if (tabs != null && tabs.length > 1 && _holdTabs)
            SliverLayoutBuilder(
              builder: (context, constraints) => SliverToBoxAdapter(
                child: SizedBox(height: _roomBelowTabs(constraints)),
              ),
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

  /// The header (#81): who leads the course, what it holds, how far along
  /// the user is, then its actions: a full-width Play / Resume over a row of
  /// Library, Pin, Share and ⋮. A plain pack shows its description in place
  /// of the first two.
  Widget _header(PackModel pack) {
    final course = _isCourse(pack);
    final who = course ? _who(pack) : null;
    final meta = course ? _meta(pack) : '';
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!course) DescriptionWidget(description: pack.description ?? ''),
        Padding(
          padding: EdgeInsets.fromLTRB(20, course ? 20 : 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ?who,
              if (meta.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: who == null ? 0 : 8),
                  child: Text(
                    meta,
                    key: const ValueKey('course_meta'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ),
              // Shown once a session is played: a course not yet begun has
              // nothing to measure.
              if (pack.playableTracks.any((i) => i.isCompleted == true)) ...[
                const SizedBox(height: 16),
                _progress(pack),
              ],
              const SizedBox(height: 20),
              CourseActionRow(pack: pack, playKey: _playButtonKey),
              LibCourseSettings(courseId: pack.id),
            ],
          ),
        ),
        _packTags(pack),
      ],
    );
  }

  /// Who the course is by: the teacher (avatar and name, opening their
  /// page), the channel or author an import names, or, for one the user
  /// made, that it is a playlist.
  Widget? _who(PackModel pack) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    if (isMyCourseId(pack.id)) {
      return Text(
        l10n.playlistKind,
        style: theme.textTheme.titleMedium?.copyWith(color: muted),
      );
    }
    final teacher = pack.teacher;
    if (teacher != null) {
      return TeacherLink(
        key: const ValueKey('course_teacher'),
        id: teacher.id,
        name: teacher.name,
        photoUrl: teacher.photoUrl,
      );
    }
    // A Dharma Seed subtitle is a summary ("2014 · 38 talks"), not a name.
    final subtitle = (pack.subtitle ?? '').trim();
    if (subtitle.isEmpty || pack.id.startsWith('ds-')) return null;
    return Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium,
    );
  }

  /// "2019 · 32 sessions · 21 h": when it was recorded, how many sessions
  /// (whatever the source calls them) and how long they run together. Each
  /// part is left out when the course does not know it.
  String _meta(PackModel pack) {
    final l10n = AppLocalizations.of(context)!;
    final tracks = pack.playableTracks;
    final years = {
      for (final item in tracks)
        if ((item.date ?? '').length >= 4) item.date!.substring(0, 4),
    }.toList()..sort();
    final totalMs = tracks.fold<int>(0, (sum, i) => sum + (i.durationMs ?? 0));
    return [
      if (years.length == 1) years.single,
      if (years.length > 1) '${years.first}–${years.last}',
      if (tracks.isNotEmpty) l10n.courseSessionCount(tracks.length),
      if (totalMs > 0) _length(totalMs),
    ].join(' · ');
  }

  /// A course's running time: to the minute under ten hours, to the hour
  /// beyond, where the minutes stop meaning anything.
  static String _length(int ms) {
    final minutes = (ms / Duration.millisecondsPerMinute).round();
    if (minutes < 600) return formatLongDuration(ms);
    return '${(minutes / 60).round()} h';
  }

  /// A thin bar of the sessions played, under the count.
  Widget _progress(PackModel pack) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final tracks = pack.playableTracks;
    final total = tracks.length;
    final done = tracks.where((i) => i.isCompleted == true).length;
    final label = done == total
        ? l10n.courseAllPlayed(total)
        : l10n.coursePlayed(done, total);
    return Semantics(
      label: label,
      excludeSemantics: true,
      // The count over the bar, so a long translation at a large text size
      // wraps instead of squeezing the bar.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            key: const ValueKey('course_progress'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: onSurface.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: done / total,
              minHeight: 4,
              backgroundColor: onSurface.withValues(alpha: 0.1),
              color: context.brandAccent,
            ),
          ),
        ],
      ),
    );
  }

  /// The space a short tab needs below its content for the page to still
  /// scroll until the tabs pin under the title: the viewport under the
  /// collapsed title bar, less the tabs and what the tab shows.
  double _roomBelowTabs(SliverConstraints constraints) {
    final tabs = _tabsKey.currentContext
        ?.findAncestorRenderObjectOfType<RenderSliver>();
    if (tabs == null || !tabs.attached) return _filler = 0;
    final tabsAndContent =
        constraints.precedingScrollExtent -
        tabs.constraints.precedingScrollExtent;
    final underTitle =
        constraints.viewportMainAxisExtent -
        MediaQuery.paddingOf(context).top -
        _collapsedAppBarHeight;
    return _filler = math.max(0, underTitle - tabsAndContent);
  }

  /// Switches tab. Once the tabs are pinned under the title, the new tab
  /// opens at its top, under them, rather than wherever the old tab's
  /// scroll position (deep in 32 sessions) would leave it.
  void _selectTab(int index, PackModel pack) {
    final tabs = _tabsKey.currentContext
        ?.findAncestorRenderObjectOfType<RenderSliver>();
    if (tabs != null && tabs.attached && _scrollController.hasClients) {
      final pinnedAt =
          tabs.constraints.precedingScrollExtent -
          MediaQuery.paddingOf(context).top -
          _collapsedAppBarHeight;
      if (_scrollController.offset >= pinnedAt) {
        _scrollController.jumpTo(math.max(0, pinnedAt));
        _holdTabs = true;
      }
    }
    setState(() => _tab = index);
    // A one-video YouTube course's Summary is its video's description: read
    // it now if it never was (#85).
    if (_tabs(pack)[index].$1 ==
            AppLocalizations.of(context)!.courseSummaryTab &&
        pack.id.startsWith('yt-') &&
        ref.read(youtubeAvailableProvider)) {
      ref.read(youtubeSourceProvider).describe(pack.id);
    }
  }

  /// The course's tabs (Sessions, Summary, Teacher), each with what it
  /// shows. A tab with nothing to show is left out.
  List<(String, List<Widget> Function())> _tabs(PackModel pack) {
    final l10n = AppLocalizations.of(context)!;
    final hasSummary =
        (pack.description ?? '').trim().isNotEmpty || pack.attribution != null;
    return [
      (l10n.courseSessionsTab, () => _sessions(pack)),
      if (hasSummary) (l10n.courseSummaryTab, () => _summary(pack)),
      if (pack.teacher != null)
        (l10n.courseTeacherTab, () => [_teacher(pack.teacher!)]),
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
            bio.isNotEmpty
                ? bio
                : isYtChannelId(teacher.id)
                ? l10n.youtubeChannelNoAbout
                : l10n.teacherNoBio,
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      ),
    );
  }

  /// The session rows, with the "mark all" button after them. A retreat
  /// recorded over several days shows each day as a group (#82); any other
  /// dated course says the date in each row.
  List<Widget> _sessions(PackModel pack) {
    if (pack.items.isEmpty && pack.id.startsWith('yt-playlist-')) {
      return [YoutubePlaylistEmpty(packId: pack.id)];
    }
    if (pack.items.isEmpty && isMyCourseId(pack.id)) {
      return [_myCourseEmpty()];
    }
    final rows = _RowStyle.of(pack, Localizations.localeOf(context));
    final days = _retreatDays(pack);
    final widgets = <Widget>[];
    if (pack.items.any((i) => i.section != null)) {
      widgets.addAll(_sectioned(pack, rows));
    } else if (days == null) {
      widgets.addAll(_listItems(pack, rows));
    } else {
      for (final group in days.groups) {
        widgets.add(_dayGroup(group, first: days.first, rows: rows));
      }
    }
    return [...widgets, _markAllButton(pack)];
  }

  /// A retreat's days: consecutive sessions sharing a recording date, in
  /// order, each day after the last. Null where the rows say their own
  /// dates instead:
  /// - a short course, one with an undated session, or one recorded in a day;
  /// - days out of order (a feed listed newest first);
  /// - about one session a day on average, or more than half the days with
  ///   a single session, which would be boxes of one row;
  /// - a feed or other source spread over more than three weeks (a podcast,
  ///   a series). A Dharma Seed retreat is a retreat by its record, so a
  ///   month-long one keeps its days, up to [_longestRetreat].
  /// Days count from [first].
  ({List<_DayGroup> groups, DateTime first})? _retreatDays(PackModel pack) {
    final items = pack.items;
    if (items.length < 8 || items.any((i) => i.date == null)) return null;
    final groups = <_DayGroup>[];
    for (final item in items) {
      if (groups.isEmpty || groups.last.date != item.date) {
        groups.add(_DayGroup(item.date!));
      }
      groups.last.items.add(item);
    }
    if (groups.length < 2) return null;
    final days = [for (final group in groups) ?_day(group.date)];
    if (days.length != groups.length) return null;
    for (var i = 1; i < days.length; i++) {
      if (!days[i].isAfter(days[i - 1])) return null;
    }
    // About a session a day, or mostly lone sessions: a box per row says
    // nothing a dated row does not.
    if (items.length / groups.length < _minSessionsPerDay) return null;
    final lone = groups.where((group) => group.items.length == 1).length;
    if (lone * 2 > groups.length) return null;
    final span = days.last.difference(days.first).inDays;
    final longest = pack.id.startsWith('ds-retreat-') ? _longestRetreat : 21;
    return span <= longest ? (groups: groups, first: days.first) : null;
  }

  /// Sessions per recorded day, on average, below which a retreat's days
  /// are not boxed.
  static const _minSessionsPerDay = 1.3;

  /// The longest Dharma Seed retreat, in days, still shown by its days (a
  /// three-month retreat's part).
  static const _longestRetreat = 100;

  /// A `yyyy-MM-dd` date as a UTC day, so counting days between two of them
  /// is exact across a daylight-saving change.
  DateTime? _day(String date) {
    final parsed = DateTime.tryParse(date);
    return parsed == null
        ? null
        : DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  /// One day of a retreat: its sessions in a bordered box, the day ("Day 3 ·
  /// Sun, Apr 16") as a small label inside, ticked once all are played. The
  /// rows leave the date to it.
  Widget _dayGroup(
    _DayGroup group, {
    required DateTime first,
    required _RowStyle rows,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = _day(group.date)!;
    final label =
        '${l10n.courseDay(date.difference(first).inDays + 1)} · '
        '${DateFormat.MMMEd(locale).format(date)}';
    final allDone = group.items.every((item) => item.isCompleted == true);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Padding(
      key: ValueKey('day_${group.date}'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Material(
        type: MaterialType.transparency,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                  if (allDone) const PackCompleteBadge(size: 16),
                ],
              ),
            ),
            for (final item in group.items)
              _buildListTile(
                item,
                item == group.items.last,
                rows: rows,
                dated: false,
              ),
          ],
        ),
      ),
    );
  }

  /// A personal course's sessions under the headings its maker gave them;
  /// sessions before the first heading stand on their own.
  List<Widget> _sectioned(PackModel pack, _RowStyle style) {
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
          rows: style,
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

  List<Widget> _listItems(PackModel pack, _RowStyle rows) {
    return [
      for (final packItem in pack.items)
        _buildListTile(packItem, pack.items.last == packItem, rows: rows),
    ];
  }

  /// One session (or sub-pack, or link) row. [dated] is false inside a
  /// retreat's day, which says the date once for all its rows.
  Widget _buildListTile(
    PackItemsModel item,
    bool isLast, {
    required _RowStyle rows,
    bool dated = true,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final unavailable = item.unavailable == true;
    final date = dated ? rows.date(item) : null;
    final row = Semantics(
      button: true,
      child: InkWell(
        onLongPress: item.type == TypeConstants.track
            // InkWell gives the long-press haptic itself.
            ? () => showItemActions(context, ref, _actionsFor(item).spec)
            : null,
        onTap: () => unavailable
            ? showSnackBar(
                context,
                AppLocalizations.of(context)!.myCourseUnavailableSnack,
              )
            : _onListItemTap(item.id, item.type, context),
        splashColor: ColorConstants.charcoal,
        child: PackItemWidget(
          item: item,
          // Unavailable said in words too, not only by fading the row.
          badge: unavailable ? l10n.myCourseUnavailable : rows.kind(item, l10n),
          courseTeacher: rows.teacher,
          courseTeacherId: rows.teacherId,
          courseByline: rows.byline,
          date: date,
          onSetComplete: unavailable || item.type == TypeConstants.pack
              ? null
              : (complete) => _setComplete(item, complete),
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
                _actionsFor(item),
              ],
            ),
          )
        else
          row,
        if (!isLast && dated)
          const Divider(
            color: ColorConstants.charcoal,
            thickness: 0.5,
            height: 1,
          )
        // Inside a day's box, a hairline in the box's own colour, inset.
        else if (!isLast)
          Divider(
            color: Theme.of(context).colorScheme.outlineVariant,
            thickness: 1,
            height: 1,
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }

  /// The session row's "⋮", and the spec its long-press opens too.
  ContentActionsButton _actionsFor(PackItemsModel item) => ContentActionsButton(
    id: item.id,
    title: item.title,
    fallback: MyItemDraft.fromPackItem(item),
    inCourse: widget.id,
    teacherId: item.teacherId,
    isComplete: item.isCompleted ?? false,
    onSetComplete: (complete) => _setComplete(item, complete),
    playable: item.unavailable != true,
  );

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

/// What a course's rows say beyond each session's own details, worked out
/// once per course (#82): whose name rows need not repeat, whether kinds
/// are worth a chip, and how to write a date.
class _RowStyle {
  _RowStyle._({
    required this.teacher,
    required this.teacherId,
    required this.byline,
    required bool mixed,
    this.dateFormat,
  }) : _mixed = mixed;

  factory _RowStyle.of(PackModel pack, Locale locale) {
    final tracks = pack.playableTracks;
    final kinds = [
      for (final item in tracks)
        if (item.kind case final kind?) DharmaSeedKind.fromRecordingType(kind),
    ];
    final dates = {
      for (final item in tracks)
        if ((item.date ?? '').length >= 10) item.date!.substring(0, 10),
    };
    final years = {for (final date in dates) date.substring(0, 4)};
    final tag = locale.toLanguageTag();
    // A Dharma Seed subtitle is a summary ("2014 · 38 talks"), not a name,
    // and a playlist's sessions come from many teachers.
    final subtitle = (pack.subtitle ?? '').trim();
    final byline = pack.id.startsWith('ds-') || isMyCourseId(pack.id)
        ? null
        : subtitle;
    return _RowStyle._(
      teacher: pack.teacher?.name,
      teacherId: pack.teacher?.id,
      byline: byline?.isEmpty ?? true ? null : byline,
      // Sits and talks side by side; talks with a Q & A stay quiet.
      mixed:
          kinds.any((kind) => kind.isPractice) &&
          kinds.any((kind) => !kind.isPractice),
      // Recorded in a day (a daylong), the date says nothing per row. The
      // header already gives a single year: "Mar 5", else "Mar 5, 2019".
      dateFormat: dates.length < 2
          ? null
          : years.length == 1
          ? DateFormat.MMMd(tag)
          : DateFormat.yMMMd(tag),
    );
  }

  /// Who leads the course; rows by them leave out the name. Matched by
  /// [teacherId] first, then by this name or the [byline].
  final String? teacher;

  /// The app ID of the course's teacher, when it has one.
  final String? teacherId;

  /// The name under the title, where it is a name and not a summary.
  final String? byline;

  /// Whether the course holds both practice and talks.
  final bool _mixed;

  final DateFormat? dateFormat;

  /// The kind chip for [item], only where the course mixes practice and
  /// talks: the session's own kind, in the app's language.
  String? kind(PackItemsModel item, AppLocalizations l10n) {
    final kind = item.kind;
    if (!_mixed || kind == null) return null;
    final known = DharmaSeedKind.fromRecordingType(kind);
    if (known != DharmaSeedKind.other || kind == known.label) {
      return switch (known) {
        DharmaSeedKind.meditation => l10n.sessionKindMeditation,
        DharmaSeedKind.chanting => l10n.sessionKindChanting,
        DharmaSeedKind.talk => l10n.sessionKindTalk,
        DharmaSeedKind.questions => l10n.sessionKindQuestions,
        DharmaSeedKind.other => l10n.sessionKindRecording,
      };
    }
    if (kind == MyCourseSource.importedLabel) return l10n.librarySourceImported;
    // A source's own name ("YouTube") is not translated.
    return kind;
  }

  /// When [item] was recorded, as its row says it.
  String? date(PackItemsModel item) {
    final parsed = DateTime.tryParse(item.date ?? '');
    if (parsed == null || dateFormat == null) return null;
    return dateFormat!.format(parsed);
  }
}

/// Sessions of a course recorded on one day.
class _DayGroup {
  _DayGroup(this.date);

  /// `yyyy-MM-dd`.
  final String date;
  final List<PackItemsModel> items = [];
}
