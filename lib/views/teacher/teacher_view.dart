import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:medito/services/youtube/youtube_ids.dart';
import 'package:medito/models/catalogue/catalogue_models.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/views/dharma_seed/widgets/course_rows_sliver.dart';
import 'package:medito/views/dharma_seed/widgets/session_rows_sliver.dart';
import 'package:medito/views/player/widgets/bottom_actions/single_back_action_bar.dart';
import 'package:medito/views/teacher/youtube_channel_view.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/widgets/attribution_notice.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/save_button.dart';
import 'package:medito/widgets/section_header.dart';
import 'package:medito/widgets/widgets.dart';

/// A teacher of any built-in catalogue: photo, biography, their courses and
/// their talks, with Save.
/// Talks load a page at a time, newest first. A source with a large archive
/// shows only its latest talks there, then the archive: years as closed
/// groups, in a section per kind (evening, morning), whose talks are read and
/// built only once a year is opened. A YouTube channel (`yt-channel-<key>`)
/// is a teacher too, with its own page.
class TeacherView extends StatelessWidget {
  const TeacherView({super.key, required this.teacherId});

  /// The app ID: `ds-teacher-<id>`, `dt-teacher-thanissaro` or
  /// `yt-channel-<key>`.
  final String teacherId;

  @override
  Widget build(BuildContext context) => isYtChannelId(teacherId)
      ? YoutubeChannelView(teacherId: teacherId)
      : _CatalogueTeacherView(teacherId: teacherId);
}

class _CatalogueTeacherView extends ConsumerStatefulWidget {
  const _CatalogueTeacherView({required this.teacherId});

  final String teacherId;

  @override
  ConsumerState<_CatalogueTeacherView> createState() => _TeacherViewState();
}

class _TeacherViewState extends ConsumerState<_CatalogueTeacherView> {
  final _scrollController = ScrollController();

  static const _pageSize = 30;

  /// Talks loaded beyond the first page, and the first page they follow:
  /// a fresh first page (after a sync) makes them stale.
  final List<PackItemsModel> _more = [];
  CatalogueTeacherPage? _basePage;
  bool _hasMore = true;
  bool _loadingMore = false;

  /// The archive: the section shown, the groups opened, and the talks of
  /// each opened group once read.
  int _archiveSection = 0;
  final Set<String> _openGroups = {};
  final Map<String, List<PackItemsModel>> _groupTalks = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _showMore(int shown) async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    // The page this offset belongs to: if a sync replaces it while the next
    // page loads, that page would land on the wrong base.
    final base = _basePage;
    final next = await ref
        .read(catalogueSourceForTeacherProvider(widget.teacherId))
        .teacherTalks(widget.teacherId, offset: shown);
    if (!mounted) return;
    if (!identical(base, _basePage)) {
      setState(() => _loadingMore = false);
      return;
    }
    setState(() {
      _more.addAll(next);
      _hasMore = next.length >= _pageSize;
      _loadingMore = false;
    });
  }

  Future<void> _toggleGroup(String id) async {
    if (_openGroups.remove(id)) {
      setState(() {});
      return;
    }
    setState(() => _openGroups.add(id));
    if (_groupTalks.containsKey(id)) return;
    await _readGroup(id);
  }

  /// Reads [id]'s talks into the cache. A read that fails closes the group
  /// again, so tapping it retries, rather than leaving a spinner.
  Future<void> _readGroup(String id) async {
    try {
      final talks = await ref
          .read(catalogueSourceForTeacherProvider(widget.teacherId))
          .archiveTalks(id);
      if (!mounted) return;
      setState(() => _groupTalks[id] = talks);
    } catch (_) {
      if (!mounted) return;
      setState(() => _openGroups.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(catalogueTeacherProvider(widget.teacherId));
    final page = async.value;
    final backBar = SingleBackButtonActionBar(
      onBackPressed: () => Navigator.pop(context),
    );

    return Scaffold(
      bottomNavigationBar: backBar,
      body: AdaptivePageBody(
        maxWidth: 960,
        child: page != null
            ? _content(page)
            : async.error is CatalogueEntryUnavailable
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(padding24),
                  child: Text(
                    AppLocalizations.of(context)!.teacherNotFound,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              )
            : async.hasError
            ? MeditoErrorWidget(
                error: async.error is AppError
                    ? async.error! as AppError
                    : const UnknownError(),
                onTap: () =>
                    ref.invalidate(catalogueTeacherProvider(widget.teacherId)),
                isLoading: async.isLoading,
              )
            : const FolderShimmerWidget(),
      ),
    );
  }

  Widget _content(CatalogueTeacherPage page) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final teacher = page.teacher;
    if (!identical(page, _basePage)) {
      // A fresh page (a feed landed) makes the cached years stale: closed ones
      // are dropped, and open ones are read again, keeping their old rows
      // on screen until the new ones arrive.
      final first = _basePage == null;
      _basePage = page;
      _more.clear();
      _hasMore = true;
      if (!first) {
        _groupTalks.removeWhere((id, _) => !_openGroups.contains(id));
        for (final id in _openGroups.toList()) {
          unawaited(_readGroup(id));
        }
      }
    }
    final talks = [...page.talks, ..._more];
    final hasMore = _more.isEmpty ? page.hasMoreTalks : _hasMore;
    final bio = teacher.bio.trim();

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        MeditoAppBarLarge(
          scrollController: _scrollController,
          title: teacher.name,
          hasLeading: false,
          coverUrl: teacher.photoUrl,
          art: teacherArt(teacher.id),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Text(
                  '${l10n.teacherTalkCount(teacher.talkCount)} · '
                  '${l10n.teacherCourseCount(teacher.retreatCount)}',
                  key: const ValueKey('teacher_counts'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SaveButton(
                      id: teacher.id,
                      label: l10n.teacherSave,
                      savedLabel: l10n.courseSaved,
                    ),
                    if (teacher.website.isNotEmpty)
                      OutlinedButton(
                        onPressed: () => launchURLInBrowser(teacher.website),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(l10n.teacherWebsite),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: SelectableText(
                  bio.isEmpty ? l10n.teacherNoBio : bio,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
        ),
        if (page.courses.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionHeader(title: l10n.teacherCourses)),
          const SliverPadding(padding: EdgeInsets.only(top: padding8)),
          CourseRowsSliver(courses: page.courses),
        ],
        if (talks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: page.archive.isEmpty
                  ? l10n.teacherTalks
                  : l10n.teacherLatestTalks,
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(top: padding8)),
          SessionRowsSliver(items: talks, hideTeacherId: widget.teacherId),
        ],
        if (hasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(padding16),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        key: const ValueKey('teacher_show_more'),
                        onPressed: () => _showMore(talks.length),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(l10n.teacherShowMore),
                      ),
              ),
            ),
          ),
        ..._archive(page.archive),
        SliverToBoxAdapter(
          child: teacher.attribution == null
              ? const SizedBox(height: 32)
              : AttributionNotice(
                  attribution: teacher.attribution!,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                ),
        ),
      ],
    );
  }

  /// The archive section: a switch between its sections when there are
  /// several, then the section's years, each a closed row until tapped.
  List<Widget> _archive(List<CatalogueArchiveSection> archive) {
    if (archive.isEmpty) return const [];
    final l10n = AppLocalizations.of(context)!;
    final index = _archiveSection.clamp(0, archive.length - 1);
    return [
      SliverToBoxAdapter(child: SectionHeader(title: l10n.teacherArchive)),
      if (archive.length > 1)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, padding8, 20, 0),
            child: SegmentedButton<int>(
              key: const ValueKey('archive_sections'),
              showSelectedIcon: false,
              segments: [
                for (final (i, section) in archive.indexed)
                  ButtonSegment(value: i, label: Text(section.title)),
              ],
              selected: {index},
              onSelectionChanged: (chosen) =>
                  setState(() => _archiveSection = chosen.single),
            ),
          ),
        ),
      const SliverPadding(padding: EdgeInsets.only(top: padding8)),
      for (final group in archive[index].groups) ...[
        SliverToBoxAdapter(child: _groupRow(group, l10n)),
        if (_openGroups.contains(group.id))
          if (_groupTalks[group.id] case final talks?)
            SessionRowsSliver(items: talks, hideTeacherId: widget.teacherId)
          else
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(padding16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
      ],
    ];
  }

  Widget _groupRow(CatalogueArchiveGroup group, AppLocalizations l10n) {
    final open = _openGroups.contains(group.id);
    return Semantics(
      expanded: open,
      button: true,
      child: ListTile(
        key: ValueKey('archive_${group.id}'),
        dense: true,
        title: Text(group.title),
        subtitle: Text(l10n.teacherTalkCount(group.talkCount)),
        trailing: Icon(
          open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
        ),
        onTap: () => _toggleGroup(group.id),
      ),
    );
  }
}
