import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:medito/services/dharma_seed/dharma_seed_models.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/views/dharma_seed/widgets/course_rows_sliver.dart';
import 'package:medito/views/dharma_seed/widgets/session_rows_sliver.dart';
import 'package:medito/views/player/widgets/bottom_actions/single_back_action_bar.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/widgets/attribution_notice.dart';
import 'package:medito/widgets/save_button.dart';
import 'package:medito/widgets/section_header.dart';
import 'package:medito/widgets/widgets.dart';

/// A teacher: photo, biography, their courses and their talks, with Save.
/// Talks load a page at a time, newest first.
class TeacherView extends ConsumerStatefulWidget {
  const TeacherView({super.key, required this.teacherId});

  /// The app ID, `ds-teacher-<id>`.
  final String teacherId;

  @override
  ConsumerState<TeacherView> createState() => _TeacherViewState();
}

class _TeacherViewState extends ConsumerState<TeacherView> {
  final _scrollController = ScrollController();

  static const _pageSize = 30;

  /// Talks loaded beyond the first page, and the first page they follow:
  /// a fresh first page (after a sync) makes them stale.
  final List<PackItemsModel> _more = [];
  DsTeacherPage? _basePage;
  bool _hasMore = true;
  bool _loadingMore = false;

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
        .read(dharmaSeedSourceProvider)
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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(dharmaSeedTeacherProvider(widget.teacherId));
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
                    ref.invalidate(dharmaSeedTeacherProvider(widget.teacherId)),
                isLoading: async.isLoading,
              )
            : const FolderShimmerWidget(),
      ),
    );
  }

  Widget _content(DsTeacherPage page) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final teacher = page.teacher;
    if (!identical(page, _basePage)) {
      _basePage = page;
      _more.clear();
      _hasMore = true;
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
          SliverToBoxAdapter(child: SectionHeader(title: l10n.teacherTalks)),
          const SliverPadding(padding: EdgeInsets.only(top: padding8)),
          SessionRowsSliver(items: talks),
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
        SliverToBoxAdapter(
          child: AttributionNotice(
            attribution: SourceAttribution(
              source: 'Dharma Seed',
              creator: teacher.name,
              url: teacher.pageUrl,
              licenseName: dharmaSeedLicenceName,
              licenseUrl: dharmaSeedLicenceUrl,
            ),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          ),
        ),
      ],
    );
  }
}
