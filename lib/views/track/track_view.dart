// ignore_for_file: use_build_context_synchronously
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/duration_preference_provider.dart';
import 'package:medito/providers/guide_name_preference_provider.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/utils/resume_request.dart';
import 'package:medito/utils/track_variant_selector.dart';
import 'package:medito/views/library/library_format.dart';
import 'package:medito/widgets/save_button.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/player/widgets/bottom_actions/single_back_action_bar.dart';
import 'package:medito/views/home/widgets/home_gradient_border.dart';
import 'package:medito/views/player/widgets/bottom_actions/track_view_bottom_bar.dart';
import 'package:medito/views/tags/widgets/tag_chips.dart';
import 'package:medito/widgets/attribution_notice.dart';
import 'package:medito/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TrackView extends ConsumerStatefulWidget {
  const TrackView({super.key, required this.trackId});

  final String trackId;

  @override
  ConsumerState<TrackView> createState() => _TrackViewState();
}

class _TrackViewState extends ConsumerState<TrackView>
    with AutomaticKeepAliveClientMixin<TrackView> {
  @override
  bool get wantKeepAlive => true;

  // True while play() is loading the audio and we're about to push the player.
  // Drives the button's spinner and disables it so a second tap can't fire a
  // duplicate playback + navigation.
  bool _isStarting = false;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final trackAsyncValue = ref.watch(tracksProvider(trackId: widget.trackId));
    final guideName = ref.watch(guideNamePreferenceProvider);
    final lastSelectedDuration = ref.watch(durationPreferenceProvider);

    void popContext() => Navigator.pop(context);

    final backButton = SingleBackButtonActionBar(onBackPressed: popContext);

    // Using 700 as a threshold for "cramped" vertical space where compact layout is preferred
    final useCompactLayout = MediaQuery.of(context).size.height < 700;

    return Scaffold(
      bottomNavigationBar: trackAsyncValue.when(
        data: (track) => TrackViewBottomBar(
          trackId: widget.trackId,
          trackTitle: track.title,
          coverUrl: track.coverUrl,
          onBackPressed: popContext,
        ),
        loading: () => backButton,
        error: (_, _) => backButton,
      ),
      body: AdaptivePageBody(
        maxWidth: 600,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
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
                    useCompactLayout,
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
    bool useCompactLayout,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(aspectRatio: 16 / 9, child: _buildCoverImage(track)),
        const SizedBox(height: 24),
        _buildTrackContent(
          track,
          activeVoice,
          activeFile,
          useCompactLayout: useCompactLayout,
        ),
      ],
    );
  }

  Widget _buildCoverImage(Track track) {
    return _buildImageWithData(track.coverUrl, seed: track.title);
  }

  Widget _buildImageWithData(String url, {required String seed}) {
    return HomeGradientBorder(
      backgroundColor: Theme.of(context).cardColor,
      borderRadius: 20,
      borderWidth: 0.5,
      child: NetworkImageWidget(
        url: url,
        shouldCache: true,
        // No picture: calm generated art, the same tile for the same title.
        seed: seed,
        alignment: Alignment.topCenter,
      ),
    );
  }

  Widget _buildTrackContent(
    Track track,
    TrackVoice activeVoice,
    TrackAudioFile activeFile, {
    required bool useCompactLayout,
  }) {
    final showGuideNameDropdown = track.voices.first.guideName
        .isNotNullAndNotEmpty();
    final guideName = ref.watch(guideNamePreferenceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, track.title),
        // "Guided meditation · Rob Burbea · 42 min"
        if ((track.subtitle ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              track.subtitle!,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        const SizedBox(height: 8),
        _getSubTitle(context, track.description),
        if (track.attribution case final attribution?)
          AttributionNotice(
            attribution: attribution,
            padding: const EdgeInsets.only(top: 16),
          ),
        _tags(track),
        const SizedBox(height: 24),
        if (useCompactLayout && showGuideNameDropdown)
          _buildCompactPickers(track, activeVoice, activeFile, guideName)
        else ...[
          if (showGuideNameDropdown) ...[
            _guideNameDropdown(
              track,
              activeVoice,
              isLandscape: false,
              guideNameState: guideName,
            ),
            const SizedBox(height: 12),
          ],
          _durationDropdown(activeVoice, activeFile, isLandscape: false),
        ],
        const SizedBox(height: 12),
        // Add to the library (a talk or an imported recording), when the
        // source allows it.
        SaveButton(
          id: track.id,
          label: AppLocalizations.of(context)!.libraryAddToLibrary,
          savedLabel: AppLocalizations.of(context)!.libraryInLibrary,
        ),
        const SizedBox(height: 12),
        _playBtn(ref, track, activeVoice, activeFile, isFullWidth: true),
        ..._fromStart(track, activeVoice, activeFile),
      ],
    );
  }

  /// The saved place, if it is in the file shown (another length of the same
  /// track has its own).
  ResumePoint? _resumeIn(Track track, TrackAudioFile file) {
    final point = ref.watch(resumePointProvider(track.id)).value;
    return point != null && point.appliesTo(file.id) ? point : null;
  }

  /// "From the beginning", offered only when there is a place to resume.
  List<Widget> _fromStart(Track track, TrackVoice voice, TrackAudioFile file) {
    final resume = _resumeIn(track, file);
    if (resume == null) return const [];
    return [
      Align(
        child: TextButton(
          key: const ValueKey('track_from_start'),
          onPressed: _isStarting
              ? null
              : () => _handlePlay(ref, track, voice, file, fromStart: true),
          child: Text(AppLocalizations.of(context)!.libraryFromStart),
        ),
      ),
    ];
  }

  Widget _buildCompactPickers(
    Track track,
    TrackVoice activeVoice,
    TrackAudioFile activeFile,
    String? guideNameState,
  ) {
    return Row(
      children: [
        Expanded(
          child: _guideNameDropdown(
            track,
            activeVoice,
            isLandscape: false,
            guideNameState: guideNameState,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _durationDropdown(activeVoice, activeFile, isLandscape: false),
        ),
      ],
    );
  }

  Widget _playBtn(
    WidgetRef ref,
    Track track,
    TrackVoice activeVoice,
    TrackAudioFile activeFile, {
    required bool isFullWidth,
  }) {
    // In dark mode a white fill pops against the ebony scaffold (~18:1).
    // In light mode the same white fill sits on #F8F9FA at ~1.07:1 and the
    // button disappears into the page — so switch to the themed primary
    // (near-black accent) with a white icon for light mode.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resume = _resumeIn(track, activeFile);
    return SizedBox(
      height: 56,
      width: isFullWidth ? double.infinity : null,
      child: ElevatedButton(
        // Guarded so a rapid second tap can't push a second player route
        // before the first navigation covers this button.
        onPressed: _isStarting
            ? null
            : () {
                _handlePlay(ref, track, activeVoice, activeFile);
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark
              ? ColorConstants.white
              : Theme.of(context).colorScheme.primary,
          foregroundColor: isDark
              ? ColorConstants.black
              : Theme.of(context).colorScheme.onPrimary,
        ),
        child: resume == null
            ? Icon(
                Icons.play_arrow_rounded,
                size: 32,
                semanticLabel: AppLocalizations.of(context)!.play,
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_arrow_rounded, size: 32),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(
                      context,
                    )!.libraryResumeAt(formatClock(resume.positionMs)),
                  ),
                ],
              ),
      ),
    );
  }

  Text _title(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        letterSpacing: 0.2,
        fontSize: 22,
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  /// The track's tags as chips. Empty (zero height) when tags are unavailable.
  Widget _tags(Track track) {
    return TrackTagChips(
      trackId: track.id,
      padding: const EdgeInsets.only(top: 12),
    );
  }

  Widget _getSubTitle(BuildContext context, String? subTitle) {
    if (subTitle != null) {
      return MarkdownWidget(
        body: subTitle,
        selectable: true,
        textAlign: WrapAlignment.start,
        p: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        a: Theme.of(context).textTheme.headlineMedium?.copyWith(
          decoration: TextDecoration.underline,
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        onTapLink: (text, href, title) {
          handleNavigation(TypeConstants.url, [href], context);
        },
      );
    }

    return const SizedBox();
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

  Widget _durationDropdown(
    TrackVoice activeVoice,
    TrackAudioFile activeFile, {
    required bool isLandscape,
  }) {
    return DropdownWidget<TrackAudioFile>(
      value: activeFile,
      iconData: Icons.timer_sharp,
      topLeft: 7,
      topRight: 7,
      bottomRight: 7,
      bottomLeft: 7,
      disabledLabelText:
          '${convertDurationToMinutes(milliseconds: activeFile.duration)} ${AppLocalizations.of(context)!.min}',
      items: activeVoice.audioFiles.map<DropdownMenuItem<TrackAudioFile>>((
        TrackAudioFile value,
      ) {
        return DropdownMenuItem<TrackAudioFile>(
          value: value,
          child: Text(
            '${convertDurationToMinutes(milliseconds: value.duration)} ${AppLocalizations.of(context)!.min}',
          ),
        );
      }).toList(),
      onChanged: _handleOnDurationChange,
      isLandscape: isLandscape,
    );
  }

  Widget _guideNameDropdown(
    Track track,
    TrackVoice activeVoice, {
    required bool isLandscape,
    required String? guideNameState,
  }) {
    if (activeVoice.guideName.isNotNullAndNotEmpty()) {
      return DropdownWidget<TrackVoice>(
        value: activeVoice,
        iconData: Icons.face,
        bottomRight: 7,
        topLeft: 7,
        topRight: 7,
        bottomLeft: 7,
        disabledLabelText: '${activeVoice.guideName}',
        items: track.voices.map<DropdownMenuItem<TrackVoice>>((
          TrackVoice value,
        ) {
          return DropdownMenuItem<TrackVoice>(
            value: value,
            child: Text(value.guideName ?? ''),
          );
        }).toList(),
        onChanged: _handleOnGuideNameChange,
        isLandscape: isLandscape,
      );
    }

    return const SizedBox();
  }
}
