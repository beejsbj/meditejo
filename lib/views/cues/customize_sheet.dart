import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/cues/cue_runtime_provider.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/cues/custom_bell_provider.dart';
import 'package:medito/providers/player/audio_state_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/audio/session_bell_preview.dart';
import 'package:medito/services/bells/custom_bell.dart';
import 'package:medito/views/cues/bell_list.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/views/soundscape/sound_labels.dart';
import 'package:medito/views/soundscape/sounds_view.dart';
import 'package:medito/widgets/inputs/wheel_picker.dart';

/// When a session started or running now will end. While playing
/// ([positionMs] > 0) the countdown has already been spent, and a timer's
/// length is simply what remains of its generated file.
DateTime customizeFinishesAt(
  DateTime now,
  CueSettings settings, {
  required bool isTimer,
  required int audioDurationMs,
  required int positionMs,
  double speed = 1,
  int? timerMinutes,
  bool isActive = false,
  int? extensionRemainingMs,
  int? countdownRemainingMs,
}) {
  if (extensionRemainingMs != null) {
    return now.add(Duration(milliseconds: extensionRemainingMs));
  }
  final active = isActive || positionMs > 0;
  final remaining = Duration(
    milliseconds: (audioDurationMs - positionMs).clamp(0, 1 << 40),
  );
  var end = now;
  if (!active) end = end.add(Duration(seconds: settings.countdownSeconds));
  if (active && countdownRemainingMs != null) {
    end = end.add(Duration(milliseconds: countdownRemainingMs));
  }
  if (isTimer) {
    end = end.add(
      active
          ? remaining
          : Duration(minutes: timerMinutes ?? settings.durationMinutes),
    );
  } else {
    end = end
        .add(Duration(microseconds: (remaining.inMicroseconds / speed).round()))
        .add(Duration(minutes: settings.extendMinutes));
  }
  return end;
}

/// Opens the Customize sheet for [request]. With [beforeStart] the sheet has a
/// Start button and the future completes true only when it was pressed;
/// dismissing it completes false so the caller can cancel.
Future<bool> showCustomizeSheet(
  BuildContext context, {
  required PlaybackRequest request,
  bool beforeStart = false,
}) async {
  final container = ProviderScope.containerOf(context);
  final scope = await container.read(
    cueScopeForRequestProvider(request).future,
  );
  if (!context.mounted) return false;
  final result = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        var positionMs = 0;
        var speed = 1.0;
        if (!beforeStart) {
          // Coarse so the line is not rebuilt on every position tick.
          positionMs =
              ref.watch(audioStateProvider.select((s) => s.position ~/ 1000)) *
              1000;
          speed = ref.watch(audioStateProvider.select((s) => s.speed.speed));
        }
        final runtime = ref.watch(
          cueRuntimeProvider.select(
            (s) => (s.phase, s.countdownMs ~/ 1000, s.extensionMs ~/ 1000),
          ),
        );
        return CustomizeSheet(
          scope: scope,
          isActive: !beforeStart,
          extensionRemainingMs: !beforeStart && runtime.$1 == 'extension'
              ? runtime.$3 * 1000
              : null,
          countdownRemainingMs: !beforeStart && runtime.$1 == 'countdown'
              ? runtime.$2 * 1000
              : null,
          isTimer: request.isTimer,
          audioDurationMs: request.duration,
          positionMs: positionMs,
          speed: speed,
          onStart: beforeStart
              ? () => Navigator.of(sheetContext).pop(true)
              : null,
        );
      },
    ),
  );
  return result ?? false;
}

/// The longest timer [CueSettings] stores.
const _maxDurationMinutes = 299;

/// Which part of the sheet is open. One at a time, so the sheet never turns
/// into a wall of controls.
enum _Part {
  duration,
  extend,
  countdown,
  startBell,
  intervalBell,
  endBell,
  pulse,
  background,
  autoplay,
}

/// Cue settings in one place, in sections (Bells, Rhythm, Time, Sound, Flow)
/// that show their values at a glance and open in place. Edits are saved as
/// the defaults for the scope's kind (or as a per-course override) and picked
/// up by the player through the provider.
class CustomizeSheet extends ConsumerStatefulWidget {
  const CustomizeSheet({
    super.key,
    required this.scope,
    this.isTimer = false,
    this.audioDurationMs = 0,
    this.positionMs = 0,
    this.speed = 1,
    this.onStart,
    this.showFinishes = true,
    this.timerMinutes,
    this.clock = DateTime.now,
    this.isActive = false,
    this.extensionRemainingMs,
    this.countdownRemainingMs,
  });

  final CueScope scope;
  final bool isTimer;
  final int audioDurationMs;
  final int positionMs;
  final double speed;
  final bool isActive;
  final int? extensionRemainingMs, countdownRemainingMs;

  /// Shows a Start button; pressing it hands control back to the caller.
  final VoidCallback? onStart;

  /// The "Finishes at" line; a stopwatch has no end to show.
  final bool showFinishes;

  /// A timer length chosen elsewhere; the sheet's own Duration row is hidden
  /// when this is set (a stopwatch passes 0).
  final int? timerMinutes;
  final DateTime Function() clock;

  @override
  ConsumerState<CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends ConsumerState<CustomizeSheet> {
  Timer? _tick;
  late bool _courseOverride;
  late final SessionBellPreview _preview;
  _Part? _open;
  final _wheels = WheelSettleGroup();
  bool _startPending = false;

  CueScope get _scope => widget.scope;
  bool get _practice => _scope.kind == CueKind.practice;

  /// What the scope's list is called: a playlist is what the user made, a
  /// course comes from a source.
  String get _scopeNoun =>
      isMyCourseId(_scope.courseId ?? '') ? 'playlist' : 'course';

  @override
  void initState() {
    super.initState();
    _courseOverride = ref.read(cueSettingsStoreProvider).hasOverride(_scope);
    _preview = ref.read(sessionBellPreviewProvider);
    _tick = Timer.periodic(
      const Duration(seconds: 30),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    // A bell auditioned here never rings on after the sheet closes.
    unawaited(_preview.stop().catchError((Object _) {}));
    super.dispose();
  }

  void _edit(CueSettings value) => unawaited(
    ref
        .read(cueSettingsProvider(_scope).notifier)
        .update(value, courseOverride: _courseOverride),
  );

  void _toggle(_Part part) {
    final closing = _open;
    setState(() => _open = _open == part ? null : part);
    // Folding a bell list silences what it was auditioning.
    if (closing != null && _bellParts.contains(closing)) {
      unawaited(_preview.stop().catchError((Object _) {}));
    }
  }

  static const _bellParts = {
    _Part.startBell,
    _Part.intervalBell,
    _Part.endBell,
  };

  /// Rings [asset] once at [volume], as a session would. Best effort: a tap
  /// that interrupts a still-loading bell, or a sound the platform will not
  /// play, is not an error worth surfacing.
  void _audition(String asset, double volume) => unawaited(
    (asset.isEmpty ? _preview.stop() : _preview.play(volume, asset: asset))
        .catchError((Object _) {}),
  );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(cueSettingsProvider(_scope));
    final isTimer = widget.isTimer;
    final canSetDuration =
        isTimer && widget.timerMinutes == null && widget.onStart != null;

    final time = _Section(
      title: 'Time',
      children: [
        if (canSetDuration)
          _row(
            _Part.duration,
            icon: Icons.timer_outlined,
            title: 'Duration',
            value: _minutes(s.durationMinutes),
            editor: () => _WheelField<int>(
              label: 'Duration',
              showLabel: false,
              options: [
                for (var m = 1; m <= _maxDurationMinutes; m++)
                  WheelOption(
                    m,
                    _minutes(m),
                    semanticsLabel: _spokenMinutes(m),
                  ),
              ],
              value: s.durationMinutes.clamp(1, _maxDurationMinutes),
              parse: _range(1, _maxDurationMinutes),
              hint: '1 to $_maxDurationMinutes minutes',
              onChanged: (v) => _edit(s.copyWith(durationMinutes: v)),
            ),
          )
        else if (!isTimer)
          _row(
            _Part.extend,
            icon: Icons.more_time_rounded,
            title: 'Extend with silence',
            value: s.extendMinutes == 0 ? 'Off' : '+${s.extendMinutes} min',
            editor: () => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Caption(
                  'Keep going in silence (with any background sound) after '
                  'the audio ends, then ring the ending bell.',
                ),
                _WheelField<int>(
                  label: 'Extra minutes',
                  options: [
                    const WheelOption(0, 'Off'),
                    for (var m = 1; m <= 60; m++)
                      WheelOption(
                        m,
                        '+$m min',
                        semanticsLabel: _spokenMinutes(m),
                      ),
                  ],
                  value: s.extendMinutes,
                  parse: _range(0, 60),
                  hint: '0 to 60 minutes',
                  onChanged: (v) => _edit(s.copyWith(extendMinutes: v)),
                ),
              ],
            ),
          ),
        _row(
          _Part.countdown,
          icon: Icons.hourglass_top_rounded,
          title: 'Countdown',
          value: s.countdownSeconds == 0 ? 'Off' : '${s.countdownSeconds} sec',
          editor: () => _WheelField<int>(
            label: 'Countdown',
            showLabel: false,
            options: const [
              WheelOption(0, 'Off'),
              WheelOption(5, '5 sec', semanticsLabel: '5 seconds'),
              WheelOption(10, '10 sec', semanticsLabel: '10 seconds'),
            ],
            value: s.countdownSeconds,
            visibleItems: 3,
            onChanged: (v) => _edit(s.copyWith(countdownSeconds: v)),
          ),
        ),
      ],
    );

    final bells = _Section(
      title: 'Bells',
      children: [
        _bellRow(
          _Part.startBell,
          s,
          title: 'Starting bell',
          icon: Icons.notifications_active_outlined,
          sound: s.startSound,
          value: _bellName(s.startSound),
          apply: (v) => s.copyWith(startSound: v),
        ),
        _bellRow(
          _Part.intervalBell,
          s,
          title: 'Interval bell',
          icon: Icons.restart_alt_rounded,
          sound: s.hasIntervalBell ? s.intervalSound : '',
          value: _intervalValue(s),
          apply: (v) => s.copyWith(intervalSound: v),
          above: _intervalWheels(s),
        ),
        _bellRow(
          _Part.endBell,
          s,
          title: 'Ending bell',
          icon: Icons.notifications_paused_outlined,
          sound: s.endSound,
          value: _bellName(s.endSound),
          apply: (v) => s.copyWith(endSound: v),
        ),
        _SliderRow(
          icon: Icons.volume_up_outlined,
          label: 'Bell volume',
          value: s.bellVolume,
          format: _percent,
          onChanged: (v) => _edit(s.copyWith(bellVolume: v)),
        ),
      ],
    );

    final rhythm = _Section(
      title: 'Rhythm',
      children: [
        _row(
          _Part.pulse,
          icon: Icons.monitor_heart_outlined,
          title: 'Pulse',
          value: _pulseValue(s),
          editor: () => _pulseEditor(s),
        ),
      ],
    );

    final sound = _Section(
      title: 'Sound',
      children: [
        _row(
          _Part.background,
          icon: Icons.graphic_eq_rounded,
          title: 'Background sound',
          value: _backgroundValue(s),
          editor: () => _backgroundEditor(s),
        ),
      ],
    );

    final flow = _Section(
      title: 'Flow',
      children: [
        if (!isTimer)
          _row(
            _Part.autoplay,
            icon: Icons.playlist_play_rounded,
            title: 'Autoplay',
            value: !s.autoplay
                ? 'Off'
                : s.interludeSeconds == 0
                ? 'On'
                : 'On · ${s.interludeSeconds} sec pause',
            editor: () => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Play the next session automatically'),
                  value: s.autoplay,
                  onChanged: (v) => _edit(s.copyWith(autoplay: v)),
                ),
                if (s.autoplay)
                  _WheelField<int>(
                    label: 'Interlude before the next session',
                    options: const [
                      WheelOption(0, 'None'),
                      WheelOption(5, '5 sec', semanticsLabel: '5 seconds'),
                      WheelOption(10, '10 sec', semanticsLabel: '10 seconds'),
                      WheelOption(30, '30 sec', semanticsLabel: '30 seconds'),
                    ],
                    value: s.interludeSeconds,
                    onChanged: (v) => _edit(s.copyWith(interludeSeconds: v)),
                  ),
              ],
            ),
          ),
        _SwitchRow(
          icon: Icons.visibility_off_outlined,
          title: 'Hide these settings before practice',
          value: s.hideBeforePractice,
          onChanged: (v) => _edit(s.copyWith(hideBeforePractice: v)),
        ),
      ],
    );

    // The brief's order is Bells, Rhythm, Time, Sound, Flow. A timer's
    // length is what its screen is for, so there Time leads.
    final sections = [
      if (_scope.courseId != null) _scopeCard(s),
      if (isTimer) time,
      bells,
      rhythm,
      if (!isTimer) time,
      sound,
      flow,
    ];

    return WheelSettleScope(
      group: _wheels,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          // Tall enough to breathe; fills a page (the Timer) that gives less.
          final height = math.min(
            constraints.maxHeight,
            media.size.height * 0.92,
          );
          return SafeArea(
            top: false,
            child: SizedBox(
              height: height,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    subtitle: _scopeLine,
                    finishes: widget.showFinishes
                        ? _finishes(context, s)
                        : null,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey('customize_list'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, section) in sections.indexed) ...[
                            if (i > 0) const SizedBox(height: 20),
                            section,
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (widget.onStart != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          shape: MeditejoShapes.stadium,
                        ),
                        onPressed: _start,
                        child: const Text('Start'),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Start reads the settings at once, but a wheel reports only when it
  /// comes to rest: a tap during a fling waits for the wheel to land, so the
  /// session gets the value the wheel is settling on, not the one before.
  void _start() {
    if (_startPending) return;
    if (!_wheels.moving) {
      widget.onStart?.call();
      return;
    }
    _startPending = true;
    unawaited(
      _wheels.settled().whenComplete(() {
        _startPending = false;
        // A sheet dismissed while the wheel was landing is still mounted for
        // its exit animation: starting then would pop whatever is beneath.
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
          widget.onStart?.call();
        }
      }),
    );
  }

  String get _scopeLine {
    if (_courseOverride) return 'For this $_scopeNoun';
    if (widget.isTimer) return 'Timer · all practice';
    return _practice ? 'All practice' : 'All talks';
  }

  /// "Use these only for this course": where an edit is saved.
  Widget _scopeCard(CueSettings s) => _Section(
    children: [
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text('Use these only for this $_scopeNoun'),
        subtitle: Text(
          _courseOverride
              ? 'Changes apply to this $_scopeNoun'
              : 'Changes apply to all ${_practice ? 'practice' : 'talks'}',
        ),
        value: _courseOverride,
        onChanged: (v) async {
          setState(() => _courseOverride = v);
          if (!v) {
            await ref
                .read(cueSettingsProvider(_scope).notifier)
                .clearOverride();
          } else {
            _edit(s);
          }
        },
      ),
    ],
  );

  Widget _row(
    _Part part, {
    required IconData icon,
    required String title,
    required String value,
    required Widget Function() editor,
    Widget? trailing,
  }) => _ExpandingRow(
    key: ValueKey('customize_${part.name}'),
    icon: icon,
    title: title,
    value: value,
    open: _open == part,
    onTap: () => _toggle(part),
    trailing: trailing,
    editor: _open == part ? editor() : null,
  );

  /// A bell cue: its name and a play button folded; the list of bells (tap
  /// to choose and hear) open. [above] goes before the list.
  Widget _bellRow(
    _Part part,
    CueSettings s, {
    required String title,
    required IconData icon,
    required String sound,
    required String value,
    required CueSettings Function(String) apply,
    Widget? above,
  }) => _row(
    part,
    icon: icon,
    title: title,
    value: value,
    trailing: sound.isEmpty
        ? null
        : IconButton(
            key: ValueKey('customize_play_${part.name}'),
            tooltip: 'Play $value',
            icon: const Icon(Icons.play_arrow_rounded),
            onPressed: () => _audition(sound, s.bellVolume),
          ),
    editor: () => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?above,
        BellList(
          selected: part == _Part.intervalBell ? s.intervalSound : sound,
          volume: s.bellVolume,
          onSelected: (v) {
            _edit(apply(v));
            _audition(v, s.bellVolume);
          },
        ),
      ],
    ),
  );

  /// How often the interval bell rings: off, halfway, or every N minutes
  /// (with an optional random window).
  Widget _intervalWheels(CueSettings s) {
    // 0 is Off and -1 Halfway; the rest are minutes.
    const halfway = -1;
    final every = !s.hasIntervalBell
        ? 0
        : s.intervalHalfway
        ? halfway
        : s.intervalMinutes;
    final minutes = !s.intervalHalfway && s.intervalMinutes > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _WheelPair(
        first: _WheelField<int>(
          label: 'Every',
          options: [
            const WheelOption(0, 'Off'),
            const WheelOption(
              halfway,
              'Halfway',
              semanticsLabel: 'Halfway, one bell at the midpoint',
            ),
            for (var m = 1; m <= 60; m++)
              WheelOption(m, '$m min', semanticsLabel: _spokenMinutes(m)),
          ],
          value: every,
          parse: _range(1, 60),
          hint: '1 to 60 minutes',
          onChanged: (v) {
            // The bell list's Off leaves no sound; choosing a rhythm turns
            // the bell back on with the default one, so the wheel and the
            // row never disagree.
            final sound = v != 0 && s.intervalSound.isEmpty
                ? cueBellSounds['Swell bell']!
                : s.intervalSound;
            if (v == halfway) {
              _edit(s.copyWith(intervalHalfway: true, intervalSound: sound));
            } else {
              // A shorter interval pulls the random window in with it, so
              // the saved value never exceeds what the wheel can show.
              _edit(
                s.copyWith(
                  intervalHalfway: false,
                  intervalMinutes: v,
                  intervalSound: sound,
                  randomWindowMinutes: s.randomWindowMinutes.clamp(0, v),
                ),
              );
            }
          },
        ),
        second: minutes
            ? _WheelField<int>(
                label: 'Random window',
                options: [
                  const WheelOption(0, 'Exact'),
                  for (var m = 1; m <= s.intervalMinutes; m++)
                    WheelOption(
                      m,
                      '± $m min',
                      semanticsLabel: _spokenMinutes(m),
                    ),
                ],
                value: s.randomWindowMinutes.clamp(0, s.intervalMinutes),
                parse: _range(0, s.intervalMinutes),
                hint: '0 to ${s.intervalMinutes} minutes',
                onChanged: (v) => _edit(s.copyWith(randomWindowMinutes: v)),
              )
            : null,
      ),
    );
  }

  Widget _pulseEditor(CueSettings s) {
    final bpm = [
      for (var b = 20; b <= 120; b++)
        WheelOption(
          b.toDouble(),
          '$b BPM',
          semanticsLabel: '$b beats a minute',
        ),
    ];
    double? parseBpm(String text) {
      final v = int.tryParse(text);
      return v != null && v >= 20 && v <= 120 ? v.toDouble() : null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Chips<String>(
          options: {for (final e in cuePulseSounds.entries) e.value: e.key},
          selected: s.pulseSound,
          onSelected: (v) => _edit(s.copyWith(pulseSound: v)),
        ),
        if (s.pulseSound.isNotEmpty) ...[
          const SizedBox(height: 12),
          _WheelPair(
            first: _WheelField<double>(
              label: 'Rate',
              options: bpm,
              value: s.pulseBpm.roundToDouble(),
              parse: parseBpm,
              hint: '20 to 120 BPM',
              onChanged: (v) => _edit(s.copyWith(pulseBpm: v)),
            ),
            second: _WheelField<int>(
              label: 'Slow down over',
              options: [
                const WheelOption(0, 'Off'),
                for (var m = 1; m <= 60; m++)
                  WheelOption(m, '$m min', semanticsLabel: _spokenMinutes(m)),
              ],
              value: s.pulseRampMinutes,
              parse: _range(0, 60),
              hint: '0 to 60 minutes',
              onChanged: (v) => _edit(s.copyWith(pulseRampMinutes: v)),
            ),
          ),
          if (s.pulseRampMinutes > 0)
            _WheelPair(
              first: _WheelField<double>(
                label: 'Ends at',
                options: bpm,
                value: s.pulseEndBpm.roundToDouble(),
                parse: parseBpm,
                hint: '20 to 120 BPM',
                onChanged: (v) => _edit(s.copyWith(pulseEndBpm: v)),
              ),
            ),
          _SliderRow(
            label: 'Pulse volume',
            value: s.pulseVolume,
            format: _percent,
            onChanged: (v) => _edit(s.copyWith(pulseVolume: v)),
          ),
        ],
      ],
    );
  }

  Widget _finishes(BuildContext context, CueSettings s) {
    final end = customizeFinishesAt(
      widget.clock(),
      s,
      isTimer: widget.isTimer,
      audioDurationMs: widget.audioDurationMs,
      positionMs: widget.positionMs,
      speed: widget.speed,
      timerMinutes: widget.timerMinutes,
      isActive: widget.isActive,
      extensionRemainingMs: widget.extensionRemainingMs,
      countdownRemainingMs: widget.countdownRemainingMs,
    );
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(end),
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
    );
    return _FinishesPill('Finishes at $time');
  }

  SoundscapeSessionKind get _soundscapeKind =>
      _practice ? SoundscapeSessionKind.practice : SoundscapeSessionKind.talks;

  /// What plays under this scope's sessions: its own choice, or the mixer's
  /// default for the kind (Off while that is switched off).
  SoundscapeSelection _soundscapeChoice(CueSettings s, SoundscapeState mixer) {
    final setting = SoundscapeController.sessionSetting(
      mixer.sessionDefault(_soundscapeKind),
      s.soundscapeSelection,
    );
    if (!setting.enabled) return SoundscapeSelection.none;
    // Shown as it will play: a deleted preset or a dropped sound is the
    // current mix.
    final selection = setting.selection;
    return mixer.playable(
      selection,
      // Only a single sound needs the library (loaded on demand).
      selection.kind == SoundscapeSelectionKind.sound
          ? ref.read(soundLibraryProvider).value
          : null,
    );
  }

  /// A course override keeps its choice in its own cue settings. Otherwise
  /// the choice is the kind's, and the mixer holds it (with the on/off and
  /// the volume), so the Sounds screen's switches show the same thing.
  void _chooseSoundscape(CueSettings s, SoundscapeSelection choice) {
    if (_courseOverride) {
      _edit(s.copyWith(soundscape: choice.encode()));
      return;
    }
    final mixer = ref.read(soundscapeProvider.notifier);
    final current = mixer.sessionDefault(_soundscapeKind);
    final off = choice.kind == SoundscapeSelectionKind.none;
    mixer.setSessionDefault(
      _soundscapeKind,
      current.copyWith(
        enabled: !off,
        selection: off ? current.selection : choice,
      ),
    );
    // A kind-wide choice lives in the mixer only; clear any stored here.
    if (s.soundscape.isNotEmpty) _edit(s.copyWith(soundscape: ''));
  }

  Widget _backgroundEditor(CueSettings s) {
    return Consumer(
      builder: (context, ref, _) {
        final l10n = AppLocalizations.of(context);
        final mixer = ref.watch(soundscapeProvider);
        final library =
            ref.watch(soundLibraryProvider).value ?? SoundLibrary.empty;
        final selected = _soundscapeChoice(s, mixer).encode();
        void pick(String value) =>
            _chooseSoundscape(s, SoundscapeSelection.parse(value));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Caption(
              'What plays under these sessions. Nothing is chosen until you '
              'pick it.',
            ),
            _Chips<String>(
              options: {
                SoundscapeSelection.none.encode(): 'Off',
                SoundscapeSelection.currentMix.encode(): 'Current mix',
              },
              selected: selected,
              onSelected: pick,
            ),
            _SubLabel(l10n?.soundsPresets ?? 'Presets'),
            _Chips<String>(
              options: {
                for (final p in mixer.presets)
                  SoundscapeSelection.preset(p.id).encode(): l10n == null
                      ? p.name
                      : soundPresetLabel(l10n, p),
              },
              selected: selected,
              onSelected: pick,
            ),
            for (final category in library.categories) ...[
              _SubLabel(
                l10n == null
                    ? category.name
                    : soundCategoryLabel(l10n, category),
              ),
              _Chips<String>(
                options: {
                  for (final e in library.inCategory(category))
                    SoundscapeSelection.sound(e.id).encode(): e.title,
                },
                selected: selected,
                onSelected: pick,
              ),
            ],
            if (selected != SoundscapeSelection.none.encode())
              _SliderRow(
                label: 'Volume',
                value: mixer.sessionDefault(_soundscapeKind).volume,
                format: _percent,
                onChanged: (v) => ref
                    .read(soundscapeProvider.notifier)
                    .setSessionVolume(_soundscapeKind, v),
              ),
            // The mix itself (what "Current mix" plays) is made on the
            // Sounds screen, full height over the sheet.
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                key: const ValueKey('customize_open_sounds'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: MeditejoShapes.stadium,
                ),
                onPressed: () => openSoundsPage(context),
                icon: const Icon(Icons.graphic_eq_rounded),
                label: Text(l10n?.soundsEditMix ?? 'Edit your mix in Sounds'),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _minutes(int m) {
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final rest = m % 60;
    return rest == 0 ? '$h h' : '$h h $rest min';
  }

  /// "1 minute", "6 minutes": what a screen reader says for a wheel row.
  static String _spokenMinutes(int m) => m == 1 ? '1 minute' : '$m minutes';

  static String _percent(double v) => '${(v * 100).round()}%';

  /// Typed whole numbers from [low] to [high], else null.
  static int? Function(String) _range(int low, int high) => (text) {
    final v = int.tryParse(text);
    return v != null && v >= low && v <= high ? v : null;
  };

  String _bellName(String path) {
    if (isCustomBellId(path)) {
      // A bell that was deleted rings as the default bell.
      for (final b in ref.watch(customBellsProvider)) {
        if (b.id == path) return b.name;
      }
      return _bellName(cueDefaultBell);
    }
    return cueBellSounds.entries
        .firstWhere(
          (e) => e.value == path,
          orElse: () => cueBellSounds.entries.first,
        )
        .key;
  }

  String _intervalValue(CueSettings s) {
    if (!s.hasIntervalBell) return 'Off';
    final bell = _bellName(s.intervalSound);
    if (s.intervalHalfway) return 'Halfway · $bell';
    final base = 'Every ${s.intervalMinutes} min';
    return s.randomWindowMinutes == 0
        ? '$base · $bell'
        : '$base ± ${s.randomWindowMinutes} · $bell';
  }

  String _pulseValue(CueSettings s) {
    if (s.pulseSound.isEmpty) return 'Off';
    final name = cuePulseSounds.entries
        .firstWhere((e) => e.value == s.pulseSound)
        .key;
    final bpm = s.pulseRampMinutes > 0
        ? '${s.pulseBpm.round()}→${s.pulseEndBpm.round()} BPM'
        : '${s.pulseBpm.round()} BPM';
    return '$name · $bpm';
  }

  String _backgroundValue(CueSettings s) {
    final choice = _soundscapeChoice(s, ref.watch(soundscapeProvider));
    switch (choice.kind) {
      case SoundscapeSelectionKind.none:
        return 'Off';
      case SoundscapeSelectionKind.mix:
        return 'Current mix';
      case SoundscapeSelectionKind.preset:
        final l10n = AppLocalizations.of(context);
        for (final p in ref.read(soundscapeProvider).presets) {
          if (p.id == choice.id) {
            return l10n == null ? p.name : soundPresetLabel(l10n, p);
          }
        }
        return 'Preset';
      case SoundscapeSelectionKind.sound:
        return ref.watch(soundLibraryProvider).value?[choice.id]?.title ??
            'Sound';
    }
  }
}

/// The sheet's title, whose settings these are, and when the session ends.
class _Header extends StatelessWidget {
  const _Header({required this.subtitle, this.finishes});

  final String subtitle;
  final Widget? finishes;

  @override
  Widget build(BuildContext context) {
    final type = context.typography;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text('Customize', style: type.emphasized.headlineSmall),
              ),
              Text(
                subtitle,
                style: type.baseline.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          ?finishes,
        ],
      ),
    );
  }
}

class _FinishesPill extends StatelessWidget {
  const _FinishesPill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('customize_finishes'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(MeditejoShapes.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 18,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: context.typography.emphasized.labelLarge?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A section: its name in the primary colour, its rows on one tonal 28 dp
/// surface, as on the Settings and You screens. One step up from the sheet
/// (which is surfaceContainerLow), so the card reads on it.
class _Section extends StatelessWidget {
  const _Section({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
              child: Text(
                title!,
                style: context.typography.emphasized.titleSmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ),
          ),
        Material(
          color: scheme.surfaceContainerHigh,
          clipBehavior: Clip.antiAlias,
          shape: MeditejoShapes.rounded(MeditejoShapes.extraLarge),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// A setting that shows its value folded and opens its controls in place.
class _ExpandingRow extends StatelessWidget {
  const _ExpandingRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.open,
    required this.onTap,
    this.trailing,
    this.editor,
  });

  final IconData icon;
  final String title, value;
  final bool open;
  final VoidCallback onTap;
  final Widget? trailing;
  final Widget? editor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final reduce = MediaQuery.of(context).disableAnimations;
    final header = Semantics(
      button: true,
      expanded: open,
      label: '$title, $value',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
            child: Row(
              children: [
                Icon(icon, color: scheme.onSurfaceVariant),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: type.baseline.titleMedium),
                      Text(
                        value,
                        style: type.emphasized.bodyMedium?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: reduce ? Duration.zero : MeditejoMotion.short,
                  child: Icon(
                    Icons.expand_more_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final body = editor == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: editor,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            header,
            // Kept outside the row's own semantics so it is its own button.
            if (trailing != null)
              Positioned(
                right: 44,
                top: 0,
                bottom: 0,
                child: Center(child: trailing),
              ),
          ],
        ),
        // Reduced motion opens in one step. (A zero-length AnimatedSize
        // restarts inside its own layout and asserts, so it is left out.)
        if (reduce)
          ?body
        else
          AnimatedSize(
            duration: MeditejoMotion.medium,
            curve: MeditejoMotion.emphasizedDecelerate,
            alignment: Alignment.topCenter,
            child: body ?? const SizedBox(width: double.infinity),
          ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: const EdgeInsets.fromLTRB(20, 4, 16, 4),
    secondary: Icon(icon),
    title: Text(title),
    value: value,
    onChanged: onChanged,
  );
}

/// A level (0 to 1). Volumes stay sliders: a wheel is for counts and times.
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    this.icon,
    required this.label,
    required this.value,
    required this.format,
    required this.onChanged,
  });

  final IconData? icon;
  final String label;
  final double value;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    return Padding(
      padding: EdgeInsets.fromLTRB(icon == null ? 4 : 20, 8, 12, 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: scheme.onSurfaceVariant),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(label, style: type.baseline.titleMedium),
                    ),
                    Text(
                      format(value),
                      style: type.emphasized.bodyMedium?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: value.clamp(0, 1),
                  divisions: 20,
                  label: format(value),
                  semanticFormatterCallback: format,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled [WheelPicker].
class _WheelField<T> extends StatelessWidget {
  const _WheelField({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.parse,
    this.hint,
    this.visibleItems = 5,
    this.showLabel = true,
  });

  final String label;

  /// Off where the row's own title already says it (a lone wheel).
  final bool showLabel;
  final List<WheelOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final T? Function(String)? parse;
  final String? hint;
  final int visibleItems;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLabel)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4, top: 4),
            child: ExcludeSemantics(
              child: Text(
                label,
                style: context.typography.baseline.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        WheelPicker<T>(
          key: ValueKey('wheel_$label'),
          label: label,
          options: options,
          value: value,
          onChanged: onChanged,
          parseEntry: parse,
          entryHint: hint,
          visibleItems: visibleItems,
        ),
      ],
    );
  }
}

/// Two wheels side by side, or stacked when large text needs the width.
class _WheelPair extends StatelessWidget {
  const _WheelPair({required this.first, this.second});

  final Widget first;
  final Widget? second;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 13;
    if (stacked || second == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (second == null && !stacked)
            Row(
              children: [
                Expanded(child: first),
                const Spacer(),
              ],
            )
          else
            first,
          ?second,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second!),
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      text,
      style: context.typography.baseline.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4, left: 4),
    child: Text(
      text,
      style: context.typography.baseline.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _Chips<T> extends StatelessWidget {
  const _Chips({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in options.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: e.key == selected,
            onSelected: (_) => onSelected(e.key),
          ),
      ],
    ),
  );
}
