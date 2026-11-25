// ignore_for_file: use_build_context_synchronously
import 'package:intl/intl.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/providers/duration_preference_provider.dart';
import 'package:medito/providers/guide_name_preference_provider.dart';
import 'package:medito/providers/library/episode_course_provider.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/library/lib_ids.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/utils/episode_title.dart';
import 'package:medito/utils/resume_request.dart';
import 'package:medito/utils/track_variant_selector.dart';
import 'package:medito/views/library/item_actions.dart';
import 'package:medito/views/library/library_format.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/views/pack/widgets/course_actions.dart';
import 'package:medito/views/player/widgets/bottom_actions/pin_action.dart';
import 'package:medito/widgets/save_button.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/widgets/headers/page_back_button.dart';
import 'package:medito/widgets/play_bar.dart';
import 'package:medito/views/home/widgets/home_gradient_border.dart';
import 'package:medito/views/categories/category_chips.dart';
import 'package:medito/widgets/attribution_notice.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/teacher_link.dart';
import 'package:medito/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// An episode's page (#84): its cover, its own title (without what every
/// episode of its course repeats), the course it is part of, who leads it,
/// a row of toggles (Library, Add to playlist, Pin, Share, ⋮), its
/// description, and the credit, small, at the end. Laid out as a course's
/// header is (#81). Back is at the top; Play is the bottom bar ([PlayBar]).
class TrackView extends ConsumerStatefulWidget {
  const TrackView({
    super.key,
    required this.trackId,
    this.fromStart = false,
    this.openedOver,
  });

  final String trackId;

  /// Opened to restart: Play begins at 0:00 instead of resuming.
  final bool fromStart;

  /// The route name of the page this one was opened over. When that is
  /// its course's page ([coursePageRouteName]), the course line goes back
  /// to it instead of opening it again.
  final String? openedOver;

  /// What the page always shows as buttons, so its ⋮ does not repeat them:
  /// Play, Add to playlist, Pin, Share, and the teacher's line. Add to
  /// library joins them while its button shows; with the button hidden (a
  /// saved course holds the episode) the ⋮ keeps it.
  static const shownAsButtons = {
    ItemAction.play,
    ItemAction.addToPlaylist,
    ItemAction.pin,
    ItemAction.share,
    ItemAction.goToTeacher,
  };

  @override
  ConsumerState<TrackView> createState() => _TrackViewState();
}

/// The course line's chevron: a no-break space and "›", so it stays on the
/// line of the course name's last word.
@visibleForTesting
const courseChevron = '\u00A0›';

/// Who leads the session, when their page is known.
typedef _Teacher = ({String id, String name, String photoUrl});

class _TrackViewState extends ConsumerState<TrackView>
    with AutomaticKeepAliveClientMixin<TrackView> {
  @override
  bool get wantKeepAlive => true;

  // True while play() is loading the audio and we're about to push the player.
  // Disables the button so a second tap can't fire a duplicate playback +
  // navigation.
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    // A YouTube episode whose description was never read: read it now that
    // its page is open (#85), and show it when it arrives.
    if (widget.trackId.startsWith('yt-video-') &&
        ref.read(youtubeAvailableProvider)) {
      _describe();
    }
  }

  Future<void> _describe() async {
    final changed = await ref
        .read(youtubeSourceProvider)
        .describe(widget.trackId);
    // A refresh keeps the page showing while the track is read again.
    if (changed && mounted) {
      ref.invalidate(tracksProvider(trackId: widget.trackId));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final trackAsyncValue = ref.watch(tracksProvider(trackId: widget.trackId));
    final guideName = ref.watch(guideNamePreferenceProvider);
    final lastSelectedDuration = ref.watch(durationPreferenceProvider);

    final shown = trackAsyncValue.hasValue && !trackAsyncValue.hasError
        ? trackAsyncValue.value
        : null;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        leading: const PageBackButton(),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: ColorConstants.transparent,
        scrolledUnderElevation: 0,
      ),
      // Play is the bottom-most thing, always on screen.
      bottomNavigationBar: shown == null
          ? null
          : _playBar(
              shown,
              TrackVariantSelector.resolve(
                shown,
                guideName: guideName,
                durationMs: lastSelectedDuration,
              ),
            ),
      body: AdaptivePageBody(
        maxWidth: 600,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: trackAsyncValue.when(
                data: (track) {
                  final selection = TrackVariantSelector.resolve(
                    track,
                    guideName: guideName,
                    durationMs: lastSelectedDuration,
                  );

                  return _buildPortraitLayout(
                    track,
                    selection.voice,
                    selection.file,
                  );
                },
                loading: () => const TrackShimmerWidget(),
                error: (err, stack) {
                  final error = err is AppError ? err : const UnknownError();
                  return MeditoErrorWidget(
                    error: error,
                    onTap: () =>
                        ref.refresh(tracksProvider(trackId: widget.trackId)),
                    isScaffold: false,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(
    Track track,
    TrackVoice activeVoice,
    TrackAudioFile activeFile,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(aspectRatio: 16 / 9, child: _buildCoverImage(track)),
        const SizedBox(height: 24),
        _buildTrackContent(track, activeVoice, activeFile),
      ],
    );
  }

  Widget _buildCoverImage(Track track) {
    return _buildImageWithData(track.coverUrl, art: singleArt(track.id));
  }

  Widget _buildImageWithData(String url, {required ArtSubject art}) {
    return HomeGradientBorder(
      backgroundColor: Theme.of(context).cardColor,
      borderRadius: 20,
      borderWidth: 0.5,
      child: NetworkImageWidget(
        url: url,
        shouldCache: true,
        art: art,
        alignment: Alignment.topCenter,
      ),
    );
  }

  Widget _buildTrackContent(
    Track track,
    TrackVoice activeVoice,
    TrackAudioFile activeFile,
  ) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final courseId = ref.watch(episodeCourseIdProvider(track.id)).value;
    final listed = courseId == null
        ? null
        : ref.watch(packProvider(packId: courseId)).value;
    final item = listed?.items.where((i) => i.id == track.id).firstOrNull;
    // A course that no longer lists the session (taken out of a playlist
    // just now) is not its course.
    final course = item == null ? null : listed;
    // A playlist the user made is in the library by being made.
    final courseSaved =
        course != null &&
        (isMyCourseId(course.id) ||
            (ref.watch(savedProvider(course.id)).value ?? false));
    final title = course == null
        ? track.title
        : episodeTitle(
            track.title,
            courseTitle: course.title,
            teacher: item?.teacher ?? course.teacher?.name,
            siblings: [
              for (final i in course.items)
                if (i.type == TypeConstants.track) i.title,
            ],
          );
    final teacher = _teacherOf(course, item);
    final meta = _meta(item);
    final description = track.description.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, title),
        if (course != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _courseLink(course, saved: courseSaved),
          ),
        if (teacher != null)
          Padding(
            padding: EdgeInsets.only(top: course == null ? 4 : 0),
            child: TeacherLink(
              key: const ValueKey('track_teacher'),
              id: teacher.id,
              name: teacher.name,
              photoUrl: teacher.photoUrl,
            ),
          )
        // "Guided meditation · Rob Burbea · 42 min", where no teacher page
        // is known to link to.
        else if ((track.subtitle ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              track.subtitle!,
              style: theme.textTheme.titleMedium?.copyWith(color: muted),
            ),
          ),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              meta,
              key: const ValueKey('track_meta'),
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
        const SizedBox(height: 16),
        // A picker with one option is not a choice, so it is not shown
        // (playing still uses that option).
        ..._pickers(track, activeVoice, activeFile),
        _actions(
          track,
          courseId: course?.id,
          courseSaved: courseSaved,
          teacherId: teacher?.id,
        ),
        if (description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: _Description(
              key: const ValueKey('track_description'),
              // A YouTube description is plain text: its line breaks are
              // the author's, so they stay.
              body: track.id.startsWith('yt-')
                  ? description.replaceAll('\n', '  \n')
                  : description,
            ),
          ),
        _tags(track),
        if (track.attribution case final attribution?)
          AttributionNotice(
            attribution: attribution,
            padding: const EdgeInsets.only(top: 24),
          ),
      ],
    );
  }

  /// "In Meditating with John Vervaeke" when the course is in the library
  /// (in place of an Add to library for the episode), else "Part of …".
  /// Either opens the course.
  Widget _courseLink(PackModel course, {required bool saved}) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final label = saved
        ? l10n.trackInCourse(course.title)
        : l10n.trackPartOf(course.title);
    final style = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w500,
    );
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 16) *
        (style?.height ?? 1.5);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('track_course'),
        borderRadius: BorderRadius.circular(12),
        // Back to the course's page when this one was opened over it;
        // else to it.
        onTap: () => widget.openedOver == coursePageRouteName(course.id)
            ? Navigator.of(context).pop()
            : openCourse(context, ref, course.id),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Centred on the first line, however many the name takes.
              SizedBox(
                height: lineHeight,
                child: Center(
                  child: Icon(
                    saved
                        ? Icons.bookmark_rounded
                        : Icons.playlist_play_rounded,
                    size: 20,
                    color: saved ? context.brandAccent : muted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                // The chevron is text, joined to the last word by a
                // no-break space, so a long course name that wraps keeps it
                // beside the words: never alone on a line, never out at the
                // edge.
                child: Text.rich(
                  TextSpan(
                    text: label,
                    children: [
                      TextSpan(
                        text: courseChevron,
                        style: style?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The session's own teacher when its course names one (a retreat's
  /// guest teacher, a podcast's guest), else the course's.
  _Teacher? _teacherOf(PackModel? course, PackItemsModel? item) {
    final lead = course?.teacher;
    final id = item?.teacherId;
    if (id != null && id.isNotEmpty) {
      final isLead = lead != null && lead.id == id;
      final name = (item?.teacher ?? '').trim().isNotEmpty
          ? item!.teacher!.trim()
          : isLead
          ? lead.name
          : '';
      if (name.isEmpty) return null;
      return (id: id, name: name, photoUrl: isLead ? lead.photoUrl : '');
    }
    if (lead == null || item == null) return null;
    final named = item.teacher?.trim();
    if (named != null && named.isNotEmpty && named != lead.name) return null;
    return (id: lead.id, name: lead.name, photoUrl: lead.photoUrl);
  }

  /// "Talk · Mar 4, 2019": the session's kind and when it was recorded,
  /// as its course lists it. Empty when the course says neither.
  String _meta(PackItemsModel? item) {
    if (item == null) return '';
    final l10n = AppLocalizations.of(context)!;
    final kind = item.kind == null
        ? DharmaSeedKind.other
        : DharmaSeedKind.fromRecordingType(item.kind);
    final kindLabel = switch (kind) {
      DharmaSeedKind.meditation => l10n.sessionKindMeditation,
      DharmaSeedKind.chanting => l10n.sessionKindChanting,
      DharmaSeedKind.talk => l10n.sessionKindTalk,
      DharmaSeedKind.questions => l10n.sessionKindQuestions,
      DharmaSeedKind.other => null,
    };
    final date = DateTime.tryParse(item.date ?? '');
    final locale = Localizations.localeOf(context).toLanguageTag();
    return [
      ?kindLabel,
      if (date != null) DateFormat.yMMMd(locale).format(date),
    ].join(' · ');
  }

  /// Under the title and meta, as a course's header has them: Add to library (unless the
  /// episode's course is already there), Add to playlist, Pin, Share and ⋮
  /// with the rest.
  Widget _actions(
    Track track, {
    required String? courseId,
    required bool courseSaved,
    required String? teacherId,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final canSave = ref.watch(contentRouterProvider).canSave(track.id);
    final saved =
        canSave && (ref.watch(savedProvider(track.id)).value ?? false);
    // Its course in the library holds it already ("In <course>" says so);
    // one saved on its own keeps its toggle, to take it out.
    final showSave = canSave && (saved || !courseSaved);
    const dailyMeditationId = 'BmTFAyYt8jVMievZ'; // from back end :(
    final toggles = [
      if (showSave)
        SaveIconButton(
          id: track.id,
          label: l10n.libraryAddToLibrary,
          savedLabel: l10n.libraryInLibrary,
        ),
      RoundIconButton(
        key: const ValueKey('track_add_to_course'),
        tooltip: l10n.myCourseAddTo,
        icon: Icons.playlist_add_rounded,
        onPressed: () => showAddToCourse(
          context,
          ref,
          id: track.id,
          fallback: MyItemDraft.fromTrack(track),
        ),
      ),
      if (track.id != dailyMeditationId)
        PinIconButton(id: track.id, session: true),
      // A link to a file that lives only on this device opens nothing for
      // the person it is sent to (#107's rule).
      if (!isLibTrackId(track.id))
        CourseShareButton.session(trackId: track.id, title: track.title),
      RoundIconButton(
        key: const ValueKey('track_actions'),
        tooltip: l10n.myCourseMore,
        icon: Icons.more_vert_rounded,
        onPressed: () => showItemActions(
          context,
          ref,
          ItemActionsSpec(
            id: track.id,
            title: track.title,
            fallback: MyItemDraft.fromTrack(track),
            inCourse: courseId,
            teacherId: teacherId,
            hide: {...TrackView.shownAsButtons, if (showSave) ItemAction.save},
          ),
        ),
      ),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: toggles);
  }

  /// The saved place, if it is in the file shown (another length of the same
  /// track has its own).
  ResumePoint? _resumeIn(Track track, TrackAudioFile file) {
    if (widget.fromStart) return null;
    final point = ref.watch(resumePointProvider(track.id)).value;
    return point != null && point.appliesTo(file.id) ? point : null;
  }

  /// The bottom bar. A play disc and the length ("44 min"); or, with a
  /// place to resume, the disc in a ring of how far in that is and "from
  /// 12:34", with a small "From the beginning" at the bar's end. The words
  /// "Play" and "Resume at 12:34" are the screen reader's label and the
  /// tooltip.
  Widget _playBar(
    Track track,
    ({TrackVoice voice, TrackAudioFile file}) selection,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final voice = selection.voice;
    final file = selection.file;
    final resume = _resumeIn(track, file);
    final minutes = convertDurationToMinutes(milliseconds: file.duration);
    final label = resume != null
        ? l10n.libraryResumeAt(formatClock(resume.positionMs))
        : minutes > 0
        ? l10n.playForMinutes(minutes)
        : l10n.play;
    return PlayBar(
      actionKey: const ValueKey('track_play'),
      label: label,
      tooltip: label,
      caption: resume != null
          ? l10n.playFromPosition(formatClock(resume.positionMs))
          : minutes > 0
          ? '$minutes ${l10n.min}'
          : null,
      progress: resume == null ? null : _fraction(resume, file),
      busy: _isStarting,
      // Guarded so a rapid second tap can't push a second player route
      // before the first navigation covers this button.
      onTap: _isStarting ? null : () => _handlePlay(ref, track, voice, file),
      trailing: resume == null
          ? null
          : IconButton(
              key: const ValueKey('track_from_start'),
              tooltip: l10n.libraryFromStart,
              onPressed: _isStarting
                  ? null
                  : () => _handlePlay(ref, track, voice, file, fromStart: true),
              icon: const Icon(Icons.restart_alt_rounded),
            ),
    );
  }

  /// How far into [file] the saved place is, for the bar's ring. Never
  /// empty: a place a few seconds in still reads as a resume.
  static double _fraction(ResumePoint resume, TrackAudioFile file) {
    final total = resume.durationMs > 0 ? resume.durationMs : file.duration;
    if (total <= 0) return 0.06;
    return (resume.positionMs / total).clamp(0.06, 1.0);
  }

  Text _title(BuildContext context, String title) {
    return Text(
      title,
      key: const ValueKey('track_title'),
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        letterSpacing: 0.2,
        fontSize: 22,
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  /// The track's categories and labels as chips. Empty (zero height) when it
  /// has none.
  Widget _tags(Track track) {
    return CategoryChips(
      subject: (id: track.id, title: track.title),
      padding: const EdgeInsets.only(top: 16),
    );
  }

  void _handleOnGuideNameChange(TrackVoice? newVoice) {
    if (newVoice == null) return;

    ref
        .read(guideNamePreferenceProvider.notifier)
        .setGuideName(newVoice.guideName);

    // Keep the duration preference in step with what the new voice offers
    final currentDuration = ref.read(durationPreferenceProvider);
    if (currentDuration != null) {
      final bestFile = TrackVariantSelector.closestDuration(
        newVoice.audioFiles,
        currentDuration,
      );
      ref
          .read(durationPreferenceProvider.notifier)
          .setDuration(bestFile.duration);
    }
  }

  void _handleOnDurationChange(TrackAudioFile? value) {
    if (value != null) {
      ref.read(durationPreferenceProvider.notifier).setDuration(value.duration);
    }
  }

  Future<void> _handlePlay(
    WidgetRef ref,
    Track track,
    TrackVoice voice,
    TrackAudioFile file, {
    bool fromStart = false,
  }) async {
    if (_isStarting) return;
    fromStart = fromStart || widget.fromStart;
    setState(() => _isStarting = true);

    // Prepare the request (sets player state synchronously) then open the
    // player immediately. PlayerView starts playback and shows its own loading
    // state, so there's no wait on this screen and no double-tap window.
    // Where the user left off is read first (a quick local read); "from the
    // beginning" forgets it.
    var request = PlaybackRequest.fromTrack(track, voice, file);
    if (fromStart) {
      await ref.read(libraryStoreProvider).clearPosition(track.id);
    } else {
      request = await withResumePosition(ref, request);
    }
    if (!mounted) return;
    ref.read(playerProvider.notifier).prepare(request);

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PlayerView()),
    ).whenComplete(() {
      if (mounted) setState(() => _isStarting = false);
    });
  }

  /// The guide and length choices, each as chips and only when there is more
  /// than one to choose from.
  List<Widget> _pickers(
    Track track,
    TrackVoice activeVoice,
    TrackAudioFile activeFile,
  ) {
    final guides = [
      for (final v in track.voices)
        if (v.guideName.isNotNullAndNotEmpty()) v,
    ];
    final lengths = activeVoice.audioFiles;
    return [
      if (guides.length > 1 && track.voices.length > 1)
        _chipRow(
          key: const ValueKey('track_guide_chips'),
          icon: Icons.face,
          chips: [
            for (final v in guides)
              (
                label: v.guideName!,
                selected: v == activeVoice,
                onSelected: () => _handleOnGuideNameChange(v),
              ),
          ],
        ),
      if (lengths.length > 1)
        _chipRow(
          key: const ValueKey('track_length_chips'),
          icon: Icons.timer_sharp,
          chips: [
            for (final f in lengths)
              (
                label:
                    '${convertDurationToMinutes(milliseconds: f.duration)} ${AppLocalizations.of(context)!.min}',
                selected: f == activeFile,
                onSelected: () => _handleOnDurationChange(f),
              ),
          ],
        ),
    ];
  }

  Widget _chipRow({
    required Key key,
    required IconData icon,
    required List<({String label, bool selected, VoidCallback onSelected})>
    chips,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(icon, size: 20),
          for (final c in chips)
            ChoiceChip(
              label: Text(c.label),
              selected: c.selected,
              onSelected: (_) => c.onSelected(),
            ),
        ],
      ),
    );
  }
}

/// The episode's description. A long one (a YouTube description, a
/// podcast's show notes) opens a few lines deep, fading out, with Show more.
class _Description extends StatefulWidget {
  const _Description({super.key, required this.body});

  final String body;

  /// Longer than this, or with more lines, it starts folded.
  static const _foldAt = 320;
  static const _foldLines = 6;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 15,
      height: 1.5,
      fontWeight: FontWeight.normal,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
    );
    final text = MarkdownWidget(
      body: widget.body,
      selectable: true,
      textAlign: WrapAlignment.start,
      p: style,
      a: style?.copyWith(decoration: TextDecoration.underline),
      onTapLink: (text, href, title) {
        handleNavigation(TypeConstants.url, [href], context);
      },
    );
    final long =
        widget.body.length > _Description._foldAt ||
        '\n'.allMatches(widget.body).length > _Description._foldLines;
    if (!long) return text;
    // Five lines at the reader's text size.
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 15) *
        (style?.height ?? 1.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_open)
          text
        else
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, 0.6, 1],
            ).createShader(rect),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: lineHeight * 5),
              child: text,
            ),
          ),
        TextButton(
          key: const ValueKey('track_description_more'),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: theme.colorScheme.onSurface,
          ),
          onPressed: () => setState(() => _open = !_open),
          child: Text(_open ? l10n.trackShowLess : l10n.trackShowMore),
        ),
      ],
    );
  }
}
