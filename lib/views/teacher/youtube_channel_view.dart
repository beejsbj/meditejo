import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/youtube/youtube_source.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/views/dharma_seed/widgets/course_rows_sliver.dart';
import 'package:medito/views/dharma_seed/widgets/session_rows_sliver.dart';
import 'package:medito/widgets/headers/page_back_button.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/widgets/attribution_notice.dart';
import 'package:medito/widgets/cards/card_art.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/save_button.dart';
import 'package:medito/widgets/section_header.dart';
import 'package:medito/widgets/widgets.dart';

/// A YouTube channel as a teacher (#85): its picture, its own description,
/// and the courses and videos of its that are in the library. The channel's
/// page is read the first time it is opened; until then it shows what the
/// imports said.
class YoutubeChannelView extends ConsumerStatefulWidget {
  const YoutubeChannelView({super.key, required this.teacherId});

  /// `yt-channel-<key>`.
  final String teacherId;

  @override
  ConsumerState<YoutubeChannelView> createState() => _YoutubeChannelViewState();
}

class _YoutubeChannelViewState extends ConsumerState<YoutubeChannelView> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(youtubeChannelPageProvider(widget.teacherId));
    final page = async.value;
    return Scaffold(
      // The page's header carries Back over its art; until there is one, a
      // plain top bar does.
      appBar: page != null ? null : AppBar(leading: const PageBackButton()),
      body: AdaptivePageBody(
        maxWidth: 960,
        child: page != null
            ? _content(page)
            : async.hasValue
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
                onTap: () => ref.invalidate(
                  youtubeChannelPageProvider(widget.teacherId),
                ),
                isLoading: async.isLoading,
              )
            : const FolderShimmerWidget(),
      ),
    );
  }

  Widget _content(YoutubeChannelPage page) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final channel = page.channel;
    final about = channel.bio.trim();
    final counts = [
      if (page.courses.isNotEmpty) l10n.teacherCourseCount(page.courses.length),
      if (page.sessions.isNotEmpty) l10n.librarySessions(page.sessions.length),
    ];
    // Every card here is the channel's own: no need for its face on each.
    return NoChannelAvatars(
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          MeditoAppBarLarge(
            scrollController: _scrollController,
            hasLeading: true,
            title: channel.name,
            coverUrl: channel.photoUrl,
            art: teacherArt(channel.id),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (counts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Text(
                      counts.join(' · '),
                      key: const ValueKey('channel_counts'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                // Save and the channel's own page, as a Dharma Seed
                // teacher's page has Save and Website.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SaveButton(
                        id: channel.id,
                        label: l10n.teacherSave,
                        savedLabel: l10n.courseSaved,
                      ),
                      if (channel.pageUrl.isNotEmpty)
                        OutlinedButton(
                          key: const ValueKey('channel_open_youtube'),
                          onPressed: () => launchURLInBrowser(channel.pageUrl),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            shape: const StadiumBorder(),
                          ),
                          child: Text(l10n.youtubeChannelOpen),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: SelectableText(
                    about.isEmpty ? l10n.youtubeChannelNoAbout : about,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          if (page.courses.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(title: l10n.teacherCourses),
            ),
            const SliverPadding(padding: EdgeInsets.only(top: padding8)),
            CourseRowsSliver(courses: page.courses),
          ],
          if (page.sessions.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(title: l10n.courseSessionsTab),
            ),
            const SliverPadding(padding: EdgeInsets.only(top: padding8)),
            SessionRowsSliver(
              items: page.sessions,
              hideTeacherId: widget.teacherId,
            ),
          ],
          SliverToBoxAdapter(
            child: AttributionNotice(
              attribution: youtubeAttribution(channel.pageUrl, channel.name),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            ),
          ),
        ],
      ),
    );
  }
}
