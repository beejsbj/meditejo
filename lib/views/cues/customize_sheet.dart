import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/cues/cue_runtime_provider.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/cues/custom_bell_provider.dart';
import 'package:medito/providers/player/audio_state_provider.dart';
import 'package:medito/providers/player/playback_speed_provider.dart';
import 'package:medito/providers/presets/preset_providers.dart';
import 'package:medito/providers/timer/timer_settings_provider.dart';
import 'package:medito/services/audio/session_bell_preview.dart';
import 'package:medito/services/bells/custom_bell.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/views/cues/bell_list.dart';
import 'package:medito/views/cues/pulse_preview.dart';
import 'package:medito/views/presets/preset_picker.dart';
import 'package:medito/widgets/inputs/wheel_picker.dart';

/// When a session started or running now will end. While playing
/// ([positionMs] > 0) the countdown has already been spent, and a timer's
/// length is simply what remains of its generated file.
///
/// A guided session reads as if the recording were longer by its silence:
/// [positionMs] and [sessionDurationMs] are on that timeline (the player
/// reports them so). Of what remains, the voice plays at [speed] and the
/// silence takes as long as it takes: [silenceLeftMs] when the native clock
/// says (the tail under way), otherwise all of it is taken to be ahead.
DateTime customizeFinishesAt(
  DateTime now,
  CueSettings settings, {
  required bool isTimer,
  required int audioDurationMs,
  required int positionMs,
  double speed = 1,
  int? timerMinutes,
  bool isActive = false,
  int? sessionDurationMs,
  int? countdownRemainingMs,
  int? silenceLeftMs,
}) {
  final active = isActive || positionMs > 0;
  var end = now;
  if (!active) end = end.add(Duration(seconds: settings.countdownSeconds));
  if (active && countdownRemainingMs != null) {
    end = end.add(Duration(milliseconds: countdownRemainingMs));
  }
  if (isTimer) {
    final remaining = (audioDurationMs - positionMs).clamp(0, 1 << 40);
    return end.add(
      active
          ? Duration(milliseconds: remaining)
          : Duration(minutes: timerMinutes ?? settings.durationMinutes),
    );
  }
  final silenceMs = settings.extraMinutes * 60000;
  // A session that does not read as extended (a repeat) reports the bare
  // recording: its silence still comes, after the last pass.
  final total = math.max(sessionDurationMs ?? 0, audioDurationMs + silenceMs);
  final remaining = active
      ? (total - positionMs).clamp(0, 1 << 40)
      : audioDurationMs + silenceMs;
  final silence = active
      ? (silenceLeftMs ?? silenceMs).clamp(0, remaining)
      : silenceMs;
  final voice = remaining - silence;
  return end
      .add(Duration(microseconds: (voice * 1000 / speed).round()))
      .add(Duration(milliseconds: silence));
}

/// The one sheet Customize opens as: before a recording, during a session,
/// for the Timer and from Settings.
Future<T?> showCustomizeModal<T>(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      builder: builder,
    );

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
  final result = await showCustomizeModal<bool>(
    context,
    (sheetContext) => Consumer(
      builder: (context, ref, _) {
        var positionMs = 0;
        var sessionDurationMs = 0;
        // Before the start, the speed the session will start at.
        var speed = sessionPlaybackSpeed(
          (kind) => ref.watch(playbackSpeedProvider(kind)),
          kind: scope.kind,
          isTimer: request.isTimer,
        );
        if (!beforeStart) {
          // Coarse so the line is not rebuilt on every position tick.
          positionMs =
              ref.watch(audioStateProvider.select((s) => s.position ~/ 1000)) *
              1000;
          speed = ref.watch(audioStateProvider.select((s) => s.speed.speed));
          // The session's length: the recording and its Extend.
          sessionDurationMs = ref.watch(
            audioStateProvider.select((s) => s.duration),
          );
        }
        final runtime = ref.watch(
          cueRuntimeProvider.select(
            (s) => (s.phase, s.countdownMs ~/ 1000, s.extensionMs ~/ 1000),
          ),
        );
        return CustomizeSheet(
          scope: scope,
          isActive: !beforeStart,
          sessionDurationMs: sessionDurationMs,
          silenceLeftMs: !beforeStart && runtime.$1 == 'extension'
              ? runtime.$3 * 1000
              : null,
          countdownRemainingMs: !beforeStart && runtime.$1 == 'countdown'
              ? runtime.$2 * 1000
              : null,
          isTimer: request.isTimer,
          openEnded:
              request.isTimer && request.timerMode == TimerMode.stopwatch,
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

/// The settings behind the tiles, in the order they show: the three bells
/// and the rhythm. Each opens as a sheet of its own over Customize.
enum _Card { startBell, intervalBell, endBell, rhythm }

/// Cue settings in one place, the same sheet wherever it opens. On top, one
/// large wheel: a timer's length (∞ at its top: open-ended, counting up), or
/// the silence a recording is extended by. Under it a 2×2 grid of tiles,
/// each showing its value (filled when it differs from the defaults,
/// outlined when it does not); tapping one opens that setting as a sheet
/// over this one. (Sounds has its own floating button.) Edits are saved as
/// the defaults for the scope's kind (or as a per-course override) and
/// picked up by the player through the provider.
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
    this.openEnded = false,
    this.clock = DateTime.now,
    this.isActive = false,
    this.sessionDurationMs = 0,
    this.silenceLeftMs,
    this.countdownRemainingMs,
  });

  final CueScope scope;
  final bool isTimer;
  final int audioDurationMs;
  final int positionMs;
  final double speed;
  final bool isActive;
  final int? countdownRemainingMs;

  /// The session's length as the player reports it (the recording and its
  /// Extend); 0 before it has said.
  final int sessionDurationMs;

  /// Silence still to come by the native clock (the tail under way); null
  /// takes all of it to be ahead.
  final int? silenceLeftMs;

  /// Shows a Start button; pressing it hands control back to the caller. A
  /// timer with one sets its length here, on the dial.
  final VoidCallback? onStart;

  /// The "Finishes at" line; Settings, with no session, has none to show.
  final bool showFinishes;

  /// A timer already running that counts up: it has no length and no end to
  /// show. (Before the start, the dial's own ∞ says so.)
  final bool openEnded;
  final DateTime Function() clock;

  @override
  ConsumerState<CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends ConsumerState<CustomizeSheet> {
  Timer? _tick;
  late bool _courseOverride;
  late final SessionBellPreview _preview;

  /// The tile whose sheet is open over this one; null when none is.
  _Card? _card;
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
    _silence();
    super.dispose();
  }

  void _edit(CueSettings value) => unawaited(
    ref
        .read(cueSettingsProvider(_scope).notifier)
        .update(value, courseOverride: _courseOverride),
  );

  /// A wheel for [label]; what it lands on is saved through [apply]. No
  /// Undo bar: it pushed the sheet about, and a wheel turned by mistake is
  /// turned back as easily. [title] is the shorter word shown above it,
  /// where the row already says the rest.
  Widget _wheel<T>({
    required String label,
    String? title,
    required List<WheelOption<T>> options,
    required T value,
    required CueSettings Function(T value) apply,
    T? Function(String)? parse,
    String? hint,
    bool showLabel = true,
    bool enabled = true,
    int? rows,
  }) => _WheelField<T>(
    label: label,
    title: title,
    options: options,
    value: value,
    parse: parse,
    hint: hint,
    // Every wheel here is the main dial's size (Burooj, 14 Nov).
    visibleItems: rows ?? _mainDialRows,
    large: _largeDial,
    showLabel: showLabel,
    enabled: enabled,
    onChanged: (v) {
      if (mounted) _save(apply(v));
    },
  );

  void _save(CueSettings value, {bool? openEnded}) {
    if (openEnded != null) {
      ref
          .read(timerSettingsProvider.notifier)
          .setMode(openEnded ? TimerMode.stopwatch : TimerMode.countdown);
    }
    _edit(value);
  }

  /// Opens [card] as a sheet over this one; closing it comes back here,
  /// where it was left.
  Future<void> _openCard(_Card card) async {
    if (_card != null) return;
    setState(() => _card = card);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      builder: (sheetContext) => WheelSettleScope(
        group: _wheels,
        child: Consumer(
          builder: (context, ref, _) {
            final s = ref.watch(cueSettingsProvider(_scope));
            final body = _cardBody(card, s);
            return _CardSheet(
              key: ValueKey('customize_card_${card.name}'),
              title: _cardTitle(card),
              child: card == _Card.rhythm
                  ? PulseAudition(settings: s, child: body)
                  : body,
            );
          },
        ),
      ),
    );
    // Leaving a bell's sheet silences what it was auditioning.
    _silence();
    if (mounted) setState(() => _card = null);
  }

  void _silence() => unawaited(_preview.stop().catchError((Object _) {}));

  /// Rings [asset] once at [volume], as a session would. Best effort: a tap
  /// that interrupts a still-loading bell, or a sound the platform will not
  /// play, is not an error worth surfacing.
  void _audition(String asset, double volume) => unawaited(
    (asset.isEmpty ? _preview.stop() : _preview.play(volume, asset: asset))
        .catchError((Object _) {}),
  );

  /// The dial sets a timer's length before it starts. A recording owns its
  /// length (its dial is Extend), and a timer under way cannot change its.
  bool get _canSetDuration => widget.isTimer && widget.onStart != null;

  /// Where presets are picked and saved from here: the Timer about to
  /// start holds all four slots; a recording, or a timer under way, owns
  /// its length.
  PresetContext get _presetPlace => _canSetDuration
      ? const PresetContext.timer()
      : PresetContext.session(
          _scope,
          courseOverride: _courseOverride,
          inSession: widget.isActive,
        );

  AppLocalizations get _l10n =>
      AppLocalizations.of(context) ??
      lookupAppLocalizations(const Locale('en'));

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(cueSettingsProvider(_scope));
    final reference = _reference;
    // Large text makes the switch several lines tall: pinned, it would leave
    // the list no room, so it ends the list instead.
    final pinSwitch = MediaQuery.textScalerOf(context).scale(10) <= 13;
    final showBefore = widget.isTimer ? null : _showBeforeSwitch(s);

    final main = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(subtitle: _scopeLine),
        Flexible(
          child: SingleChildScrollView(
            key: const ValueKey('customize_list'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyedSubtree(
                  key: const ValueKey('customize_dial'),
                  child: _dial(s),
                ),
                const SizedBox(height: 16),
                _TileGrid(
                  tiles: [
                    for (final card in _Card.values) _tile(card, s, reference),
                  ],
                ),
                // Under the tiles, so the dial stays on top: what all of
                // this was loaded from, the list of presets, and Save.
                const SizedBox(height: 8),
                PresetRow(place: _presetPlace),
                if (_scope.courseId != null) ...[
                  const SizedBox(height: 16),
                  // Compact with large text, where its second line would
                  // crowd a small screen.
                  _scopeCard(s, compact: !pinSwitch),
                ],
                if (!pinSwitch && showBefore != null) ...[
                  const SizedBox(height: 16),
                  showBefore,
                ],
              ],
            ),
          ),
        ),
      ],
    );

    return WheelSettleScope(
      group: _wheels,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          // As tall as what it shows, up to most of the screen.
          final height = math.min(
            constraints.maxHeight,
            media.size.height * 0.92,
          );
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: height),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(child: main),
                  if (pinSwitch) ?showBefore,
                  ?_startButton,
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Whether this sheet opens before each recorded session. The sheet's own
  /// setting, so not a tile: it sits under the list, by Start. A timer, which
  /// always opens on this sheet, has no use for it.
  Widget _showBeforeSwitch(CueSettings s) => _SwitchRow(
    key: const ValueKey('customize_show_before'),
    icon: Icons.visibility_outlined,
    title: _l10n.customizeShowBeforeSession,
    value: s.showBeforeSession,
    onChanged: (v) => _edit(s.copyWith(hideBeforePractice: !v)),
  );

  Widget? get _startButton => widget.onStart == null
      ? null
      : Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: MeditejoShapes.stadium,
            ),
            onPressed: _start,
            child: const Text('Start'),
          ),
        );

  /// What "changed" is measured against: the defaults this scope falls back
  /// on. A course's own settings against its kind's; the kind's against the
  /// app's.
  CueSettings get _reference => _courseOverride
      ? ref.watch(cueSettingsProvider(CueScope(_scope.kind)))
      : CueSettings.defaults(_scope.kind);

  /// The tile for [card]: its name, its value at a glance, filled when it
  /// differs from the defaults. What belongs to a bell (its countdown, its
  /// silence) is its second line.
  Widget _tile(_Card card, CueSettings s, CueSettings reference) {
    final l10n = _l10n;
    final (icon, value, detail, changed) = switch (card) {
      _Card.startBell => (
        Icons.notifications_active_outlined,
        _bellValue(s.startSound),
        s.countdownSeconds == 0
            ? null
            : l10n.customizeCountdownDetail(s.countdownSeconds),
        _startKey(s) != _startKey(reference),
      ),
      _Card.intervalBell => (
        Icons.restart_alt_rounded,
        _intervalValue(s),
        s.hasIntervalBell ? _bellName(s.intervalSound) : null,
        _intervalKey(s) != _intervalKey(reference),
      ),
      _Card.endBell => (
        Icons.notifications_paused_outlined,
        _bellValue(s.endSound),
        _endSilenceMinutes(s) == 0
            ? null
            : l10n.customizeSilenceDetail(_endSilenceMinutes(s)),
        _endKey(s) != _endKey(reference),
      ),
      _Card.rhythm => (
        Icons.monitor_heart_outlined,
        _pulseName(s),
        s.pulseSound.isEmpty ? null : _pulseRateSpoken(s),
        _pulseKey(s) != _pulseKey(reference),
      ),
    };
    return _SettingTile(
      key: ValueKey('customize_tile_${card.name}'),
      icon: icon,
      label: _cardTitle(card),
      value: value,
      detail: detail,
      detailView: card == _Card.rhythm ? _pulseRateView(s) : null,
      changed: changed,
      state: changed ? l10n.customizeSlotChanged : l10n.customizeSlotDefault,
      onTap: () => _openCard(card),
    );
  }

  String _cardTitle(_Card card) => switch (card) {
    _Card.startBell => _l10n.customizeStartingBell,
    _Card.intervalBell => _l10n.customizeIntervalBell,
    _Card.endBell => _l10n.customizeEndingBell,
    _Card.rhythm => _l10n.customizeSlotRhythm,
  };

  /// What a tile opens. Each bell comes with what belongs to it: the
  /// countdown before the starting bell, how often the interval bell rings,
  /// and the silence after the audio before the ending bell.
  Widget _cardBody(_Card card, CueSettings s) => switch (card) {
    _Card.startBell => _bellCard(
      s,
      selected: s.startSound,
      apply: (v) => s.copyWith(startSound: v),
      wheels: [
        _wheel<int>(
          label: 'Countdown',
          options: const [
            WheelOption(0, 'Off'),
            WheelOption(5, '5 sec', semanticsLabel: '5 seconds'),
            WheelOption(10, '10 sec', semanticsLabel: '10 seconds'),
          ],
          value: s.countdownSeconds,
          apply: (v) => s.copyWith(countdownSeconds: v),
        ),
      ],
    ),
    _Card.intervalBell => _bellCard(
      s,
      selected: s.intervalSound,
      apply: (v) => s.copyWith(intervalSound: v),
      wheels: _intervalWheels(s),
    ),
    _Card.endBell => _bellCard(
      s,
      selected: s.endSound,
      apply: (v) => s.copyWith(endSound: v),
      // A timer's length is its own: silence after it is just a longer
      // timer.
      // The caption is the wheel's title.
      caption: widget.isTimer ? null : _l10n.extendEndCaption,
      labelled: false,
      wheels: widget.isTimer ? const [] : [_endSilence(s)],
    ),
    _Card.rhythm => _pulseEditor(s),
  };

  /// A bell's sheet: its own wheels with the volume all bells share on
  /// their right, in one row; under them the list of bells (tap to choose
  /// and hear, "Make a bell" last).
  Widget _bellCard(
    CueSettings s, {
    required String selected,
    required CueSettings Function(String) apply,
    required List<Widget> wheels,
    String? caption,
    bool labelled = true,
  }) {
    final volume = _VolumeColumn(
      key: const ValueKey('customize_volume_bell'),
      label: 'Bell volume',
      // Level with the wheels' own titles, or with none.
      title: labelled ? 'Volume' : null,
      value: s.bellVolume,
      height: _wheelHeight,
      format: _percent,
      onChanged: (v) => _edit(s.copyWith(bellVolume: v)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (caption != null) _Caption(caption, centred: true),
        if (wheels.isEmpty)
          _SliderRow(
            icon: Icons.volume_up_outlined,
            label: 'Bell volume',
            value: s.bellVolume,
            format: _percent,
            onChanged: (v) => _edit(s.copyWith(bellVolume: v)),
          )
        else
          _WheelRow(wheels, trailing: volume),
        const SizedBox(height: 8),
        BellList(
          selected: selected,
          volume: s.bellVolume,
          onSelected: (v) {
            _edit(apply(v));
            _audition(v, s.bellVolume);
          },
        ),
      ],
    );
  }

  /// The sheet's one large control: a timer's length, set before it starts
  /// and shown once it runs; for a recording, Extend.
  Widget _dial(CueSettings s) {
    if (_canSetDuration) return _lengthDial(s);
    if (widget.isTimer) return _lengthReadout(s);
    return _extendDial(s);
  }

  /// The dial stands taller on a tall screen; with large text it is an
  /// ordinary wheel, which is already large.
  bool get _largeDial => MediaQuery.textScalerOf(context).scale(10) <= 13;
  int get _dialRows =>
      _largeDial && MediaQuery.sizeOf(context).height >= 780 ? 5 : 3;

  /// How many rows the sheet's main dial shows: a timer's length stands
  /// taller on a tall screen; Extend keeps to three.
  int get _mainDialRows => _canSetDuration ? _dialRows : 3;

  /// How tall a wheel of [_mainDialRows] stands, as [WheelPicker] lays it
  /// out: what a volume beside it is drawn to.
  double get _wheelHeight {
    final extent = _largeDial ? 56.0 : 40.0;
    return MediaQuery.textScalerOf(
          context,
        ).scale(extent).clamp(extent, double.infinity) *
        _mainDialRows;
  }

  /// A timer's length. ∞ is the wheel's first place, above 1 min: open-ended,
  /// counting up until it is ended (the stopwatch engine underneath). The
  /// button at its top right turns the wheel there, and back to the length
  /// it left.
  Widget _lengthDial(CueSettings s) {
    final l10n = _l10n;
    final openEnded = ref.watch(
      timerSettingsProvider.select((t) => t.mode == TimerMode.stopwatch),
    );
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WheelRow([
              _WheelField<int>(
                label: 'Duration',
                showLabel: false,
                large: _largeDial,
                visibleItems: _dialRows,
                followAnimated: true,
                options: [
                  WheelOption(
                    0,
                    '∞',
                    semanticsLabel: l10n.timerOpenEnded,
                    scale: 1.7,
                  ),
                  for (var m = 1; m <= _maxDurationMinutes; m++)
                    WheelOption(
                      m,
                      _minutes(m),
                      semanticsLabel: _spokenMinutes(m),
                    ),
                ],
                value: openEnded ? 0 : s.durationMinutes.clamp(1, 299),
                parse: _range(1, _maxDurationMinutes),
                hint: '1 to $_maxDurationMinutes minutes',
                // The length it leaves for ∞ is kept, to come back to.
                onChanged: (v) {
                  if (!mounted) return;
                  final now = ref.read(cueSettingsProvider(_scope));
                  _save(
                    v == 0 ? now : now.copyWith(durationMinutes: v),
                    openEnded: v == 0,
                  );
                },
              ),
            ], hero: _largeDial),
            if (widget.showFinishes) ...[
              const SizedBox(height: 12),
              Center(
                child: openEnded
                    ? _Pill(
                        l10n.customizeLengthCountsUp,
                        icon: Icons.all_inclusive_rounded,
                      )
                    : _finishes(context, s),
              ),
            ],
          ],
        ),
        PositionedDirectional(
          top: 0,
          end: 0,
          // Filled in the primary colour while on, outlined while off:
          // "you can't tell whether it's on" (Burooj, 14 Nov).
          child: _InfinityToggle(
            on: openEnded,
            tooltip: l10n.timerOpenEnded,
            onPressed: () => _save(s, openEnded: !openEnded),
          ),
        ),
      ],
    );
  }

  /// A timer under way: its length, which it cannot change now.
  Widget _lengthReadout(CueSettings s) {
    final scheme = Theme.of(context).colorScheme;
    final minutes = widget.audioDurationMs > 0
        ? math.max(1, (widget.audioDurationMs / 60000).round())
        : s.durationMinutes;
    return Column(
      children: [
        Text(
          widget.openEnded ? '∞' : _minutes(minutes),
          key: const ValueKey('customize_length'),
          semanticsLabel: widget.openEnded ? _l10n.timerOpenEnded : null,
          style: context.typography.emphasized.displaySmall?.copyWith(
            color: scheme.onSurface,
          ),
        ),
        if (widget.showFinishes && !widget.openEnded) ...[
          const SizedBox(height: 8),
          _finishes(context, s),
        ],
      ],
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
  /// Compact with large text, where its second line would crowd a small
  /// screen: the header's line already says whose settings these are.
  Widget _scopeCard(CueSettings s, {required bool compact}) => _Section(
    children: [
      SwitchListTile(
        key: const ValueKey('customize_scope_card'),
        dense: compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text('Use these only for this $_scopeNoun'),
        subtitle: compact
            ? null
            : Text(
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

  /// Off, then +1 to +60 minutes: Extend, and the Ending bell's silence.
  List<WheelOption<int>> get _extraMinuteOptions => [
    const WheelOption(0, 'Off'),
    for (var m = 1; m <= 60; m++)
      WheelOption(m, '+$m min', semanticsLabel: _spokenMinutes(m)),
  ];

  /// The silence after the recording, before the ending bell: part of the
  /// Ending bell, as #72 groups it. Its own setting, apart from Extend. The
  /// caption over its sheet is its title.
  Widget _endSilence(CueSettings s) => _wheel<int>(
    label: _l10n.extendEndLabel,
    showLabel: false,
    options: _extraMinuteOptions,
    value: s.endSilenceMinutes,
    parse: _range(0, 60),
    hint: '0 to 60 minutes',
    apply: (v) => s.copyWith(endSilenceMinutes: v),
  );

  /// Extend: silence added to a recording's session. Under the wheel, the
  /// recording's length and what the session comes to with all its silence
  /// ("20 min + 5 min = 25 min"), and when it ends.
  Widget _extendDial(CueSettings s) {
    final type = context.typography;
    final scheme = Theme.of(context).colorScheme;
    final recording = widget.audioDurationMs <= 0
        ? null
        : math.max(1, (widget.audioDurationMs / 60000).round());
    // Short, as plain numbers when they are all under an hour: "43 + 2 =
    // 45 min".
    final parts = [
      ?recording,
      if (s.extendMinutes > 0) s.extendMinutes,
      if (s.endSilenceMinutes > 0) s.endSilenceMinutes,
    ];
    final sum = recording == null
        ? null
        : s.extraMinutes == 0
        ? _minutes(recording)
        : '${parts.map((m) => parts.every((p) => p < 60) ? '$m' : _minutes(m)).join(' + ')}'
              ' = ${_minutes(recording + s.extraMinutes)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The wheel says its own name to a screen reader.
        ExcludeSemantics(
          child: Text(
            _l10n.extendTitle,
            textAlign: TextAlign.center,
            style: type.emphasized.titleMedium?.copyWith(
              color: scheme.onSurface,
            ),
          ),
        ),
        _Caption(_l10n.extendCaption, centred: true),
        _WheelRow([
          _wheel<int>(
            label: _l10n.extendTitle,
            showLabel: false,
            options: _extraMinuteOptions,
            value: s.extendMinutes,
            parse: _range(0, 60),
            hint: '0 to 60 minutes',
            apply: (v) => s.copyWith(extendMinutes: v),
          ),
        ], hero: _largeDial),
        if (sum != null || widget.showFinishes) ...[
          const SizedBox(height: 12),
          // One line of a fixed height, shrunk rather than wrapped: a longer
          // sum never moves the sheet ("the whole sheet jumps", 14 Nov).
          SizedBox(
            key: const ValueKey('customize_summary'),
            height: MediaQuery.textScalerOf(context).scale(40),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (sum != null)
                    Text(
                      sum,
                      key: const ValueKey('customize_total'),
                      maxLines: 1,
                      style: type.baseline.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (sum != null && widget.showFinishes)
                    const SizedBox(width: 12),
                  if (widget.showFinishes) _finishes(context, s),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// How often the interval bell rings: off, halfway, or every N minutes
  /// (with an optional random window).
  List<Widget> _intervalWheels(CueSettings s) {
    // 0 is Off and -1 Halfway; the rest are minutes.
    const halfway = -1;
    final every = !s.hasIntervalBell
        ? 0
        : s.intervalHalfway
        ? halfway
        : s.intervalMinutes;
    final minutes = !s.intervalHalfway && s.intervalMinutes > 0;
    return [
      _wheel<int>(
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
        apply: (v) {
          // The bell list's Off leaves no sound; choosing a rhythm turns
          // the bell back on with the default one, so the wheel and the
          // row never disagree.
          final sound = v != 0 && s.intervalSound.isEmpty
              ? cueDefaultBell
              : s.intervalSound;
          if (v == halfway) {
            return s.copyWith(intervalHalfway: true, intervalSound: sound);
          }
          // A shorter interval pulls the random window in with it, so the
          // saved value never exceeds what the wheel can show.
          return s.copyWith(
            intervalHalfway: false,
            intervalMinutes: v,
            intervalSound: sound,
            randomWindowMinutes: s.randomWindowMinutes.clamp(0, v),
          );
        },
      ),
      if (minutes)
        _wheel<int>(
          label: 'Random window',
          options: [
            const WheelOption(0, 'Exact'),
            for (var m = 1; m <= s.intervalMinutes; m++)
              WheelOption(m, '± $m min', semanticsLabel: _spokenMinutes(m)),
          ],
          value: s.randomWindowMinutes.clamp(0, s.intervalMinutes),
          parse: _range(0, s.intervalMinutes),
          hint: '0 to ${s.intervalMinutes} minutes',
          apply: (v) => s.copyWith(randomWindowMinutes: v),
        ),
    ];
  }

  Widget _pulseEditor(CueSettings s) {
    final l10n = _l10n;
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
          // Rate · over · Ends at, read as one line like a date's wheels
          // (#73), and the pulse's volume as a fourth column. Ends at
          // waits, dimmed, until there is a ramp to end.
          _WheelRow(
            [
              _wheel<double>(
                label: l10n.customizeRhythmRate,
                options: bpm,
                value: s.pulseBpm.roundToDouble(),
                parse: parseBpm,
                hint: '20 to 120 BPM',
                apply: (v) => s.copyWith(pulseBpm: v),
              ),
              _wheel<int>(
                label: l10n.customizeRhythmSlowDownOver,
                title: l10n.customizeRhythmOver,
                options: [
                  const WheelOption(0, 'Off'),
                  for (var m = 1; m <= 60; m++)
                    WheelOption(m, '$m min', semanticsLabel: _spokenMinutes(m)),
                ],
                value: s.pulseRampMinutes,
                parse: _range(0, 60),
                hint: '0 to 60 minutes',
                apply: (v) => s.copyWith(pulseRampMinutes: v),
              ),
              _wheel<double>(
                label: l10n.customizeRhythmEndsAt,
                options: bpm,
                value: s.pulseEndBpm.roundToDouble(),
                parse: parseBpm,
                hint: '20 to 120 BPM',
                enabled: s.pulseRampMinutes > 0,
                apply: (v) => s.copyWith(pulseEndBpm: v),
              ),
            ],
            trailing: _VolumeColumn(
              key: const ValueKey('customize_volume_pulse'),
              label: 'Pulse volume',
              title: 'Volume',
              value: s.pulseVolume,
              height: _wheelHeight,
              format: _percent,
              onChanged: (v) => _edit(s.copyWith(pulseVolume: v)),
            ),
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
      isActive: widget.isActive,
      sessionDurationMs: widget.sessionDurationMs,
      countdownRemainingMs: widget.countdownRemainingMs,
      silenceLeftMs: widget.silenceLeftMs,
    );
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(end),
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
    );
    return _Pill(
      'Finishes at $time',
      key: const ValueKey('customize_finishes'),
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

  /// A bell by name, or Off.
  String _bellValue(String sound) =>
      sound.isEmpty ? _l10n.customizeOff : _bellName(sound);

  /// The Interval bell tile: how often it rings ("Every 30 min ± 20").
  String _intervalValue(CueSettings s) {
    if (!s.hasIntervalBell) return _l10n.customizeOff;
    if (s.intervalHalfway) return _l10n.customizeBellsHalfway;
    final every = _l10n.customizeBellsEvery(s.intervalMinutes);
    return s.randomWindowMinutes == 0
        ? every
        : '$every ± ${s.randomWindowMinutes}';
  }

  /// The ending bell's own silence; a timer has none.
  int _endSilenceMinutes(CueSettings s) =>
      widget.isTimer ? 0 : s.endSilenceMinutes;

  /// What each bell's tile holds, as a value to compare: the countdown and
  /// the silence belong to their bells. An interval bell that is off is off,
  /// whatever its stored rhythm. The volume all bells share marks no tile.
  Object _startKey(CueSettings s) => (s.startSound, s.countdownSeconds);
  Object _endKey(CueSettings s) => (s.endSound, _endSilenceMinutes(s));
  Object? _intervalKey(CueSettings s) => !s.hasIntervalBell
      ? null
      : s.intervalHalfway
      ? (s.intervalSound, -1, 0)
      : (s.intervalSound, s.intervalMinutes, s.randomWindowMinutes);

  /// What the Rhythm slot holds: nothing while the pulse is off.
  Object? _pulseKey(CueSettings s) => s.pulseSound.isEmpty
      ? null
      : (
          s.pulseSound,
          s.pulseBpm.round(),
          s.pulseRampMinutes,
          s.pulseRampMinutes > 0 ? s.pulseEndBpm.round() : 0,
          s.pulseVolume,
        );

  String _pulseName(CueSettings s) => s.pulseSound.isEmpty
      ? _l10n.customizeOff
      : cuePulseSounds.entries
            .firstWhere(
              (e) => e.value == s.pulseSound,
              orElse: () => cuePulseSounds.entries.first,
            )
            .key;

  /// The Rhythm tile's second line, as a screen reader says it.
  String _pulseRateSpoken(CueSettings s) => s.pulseRampMinutes > 0
      ? _l10n.customizeRhythmRampSpoken(
          s.pulseBpm.round(),
          s.pulseEndBpm.round(),
          s.pulseRampMinutes,
        )
      : '${s.pulseBpm.round()} BPM';

  /// The Rhythm tile's second line as shown: "60 ⟶ 40 BPM" with "over
  /// 20 min" set small above the arrow (#73). Null without a ramp (the
  /// plain rate) or a pulse.
  Widget? _pulseRateView(CueSettings s) =>
      s.pulseSound.isEmpty || s.pulseRampMinutes == 0
      ? null
      : _RampSummary(
          from: '${s.pulseBpm.round()}',
          to: '${s.pulseEndBpm.round()} BPM',
          over: _l10n.customizeRhythmOverMinutes(s.pulseRampMinutes),
        );
}

/// The sheet's title and whose settings these are. (Sounds has its own
/// floating button, reachable from everywhere.)
class _Header extends StatelessWidget {
  const _Header({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final type = context.typography;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
      child: Column(
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
    );
  }
}

/// A tile's sheet over Customize: its name, and what it sets.
class _CardSheet extends StatelessWidget {
  const _CardSheet({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: context.typography.emphasized.headlineSmall,
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            key: const ValueKey('customize_card_list'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: child,
          ),
        ),
      ],
    ),
  );
}

/// The Timer's ∞: filled in the primary colour while the timer is
/// open-ended, outlined while it is not, so either state reads at a glance.
class _InfinityToggle extends StatelessWidget {
  const _InfinityToggle({
    required this.on,
    required this.tooltip,
    required this.onPressed,
  });

  final bool on;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const icon = Icon(Icons.all_inclusive_rounded);
    return on
        ? IconButton.filled(
            key: const ValueKey('customize_infinity'),
            isSelected: true,
            tooltip: tooltip,
            icon: icon,
            onPressed: onPressed,
          )
        : IconButton.outlined(
            key: const ValueKey('customize_infinity'),
            isSelected: false,
            tooltip: tooltip,
            icon: icon,
            onPressed: onPressed,
          );
  }
}

/// A quiet pill under the dial: when the session ends, or that it has no
/// end.
class _Pill extends StatelessWidget {
  const _Pill(this.text, {super.key, this.icon = Icons.schedule_rounded});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(MeditejoShapes.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.onTertiaryContainer),
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

/// Rows on one tonal 28 dp surface, as on the Settings and You screens. One
/// step up from the sheet (which is surfaceContainerLow), so it reads on it.
class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    clipBehavior: Clip.antiAlias,
    shape: MeditejoShapes.rounded(MeditejoShapes.extraLarge),
    child: Column(children: children),
  );
}

/// The tiles as a 2×2 grid; each row's tiles share the taller one's height.
/// With large text they stand one under another, each the sheet's width.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(10) > 13) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, tile) in tiles.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            tile,
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 12),
                Expanded(
                  child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One setting: its name, its value and a second line. Filled when it
/// differs from the defaults, outlined when it does not (the language of
/// the preset picker and the save sheet). Tapping it opens its card.
class _SettingTile extends StatelessWidget {
  const _SettingTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
    this.detailView,
    required this.changed,
    required this.state,
    required this.onTap,
  });

  final IconData icon;
  final String label, value;

  /// The second line; [detailView], when given, shows it instead (this
  /// stays what a screen reader says).
  final String? detail;
  final Widget? detailView;

  /// Read after the value: "changed" or "default", what the fill shows.
  final String state;
  final bool changed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final muted = changed
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final detailStyle = type.baseline.bodySmall?.copyWith(color: muted);
    final tile = Material(
      color: changed ? scheme.secondaryContainer : Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MeditejoShapes.large),
        side: changed
            ? BorderSide.none
            : BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      icon,
                      size: MediaQuery.textScalerOf(context).scale(18),
                      color: muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: type.baseline.labelLarge?.copyWith(color: muted),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 20, color: muted),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: type.emphasized.titleMedium?.copyWith(
                    color: changed
                        ? scheme.onSecondaryContainer
                        : scheme.onSurface,
                  ),
                ),
                if (detailView != null)
                  DefaultTextStyle.merge(style: detailStyle, child: detailView!)
                else if (detail != null)
                  Text(
                    detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: detailStyle,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: [label, value, ?detail, state].join(', '),
      excludeSemantics: true,
      onTap: onTap,
      child: tile,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
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
    contentPadding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
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
    this.title,
    required this.options,
    required this.value,
    required this.onChanged,
    this.parse,
    this.hint,
    this.visibleItems = 5,
    this.showLabel = true,
    this.enabled = true,
    this.large = false,
    this.followAnimated = false,
  });

  /// What the wheel sets: for a screen reader, the typing dialog and the
  /// Undo bar.
  final String label;

  /// The word shown above the wheel, when shorter than [label].
  final String? title;
  final bool enabled;

  /// The sheet's dial: larger values on taller rows.
  final bool large;

  /// Turns to a value set by a button beside it, rather than jumping.
  final bool followAnimated;

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
    final labelStyle = context.typography.baseline.labelLarge?.copyWith(
      color: enabled
          ? scheme.onSurfaceVariant
          : scheme.onSurfaceVariant.withValues(alpha: 0.38),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, top: 4),
            child: ExcludeSemantics(
              // Over a narrow wheel a long word shrinks rather than wraps,
              // in a line of its full height, so the wheels in a row stay
              // level.
              child: SizedBox(
                height: MediaQuery.textScalerOf(context).scale(
                  (labelStyle?.fontSize ?? 14) * (labelStyle?.height ?? 1.43),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title ?? label,
                    maxLines: 1,
                    softWrap: false,
                    style: labelStyle,
                  ),
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
          itemExtent: large ? 56 : 40,
          enabled: enabled,
          large: large,
          followAnimated: followAnimated,
        ),
      ],
    );
  }
}

/// Wheels side by side (one to three), narrow and centred, with a gutter
/// each side and a gap between them (#91): a thumb scrolling the sheet lands
/// there and scrolls it, rather than turning a wheel. [trailing], a narrow
/// column (a volume), ends the row. When large text needs the width they
/// stack, each still centred between gutters.
class _WheelRow extends StatelessWidget {
  const _WheelRow(this.wheels, {this.hero = false, this.trailing});

  final List<Widget> wheels;
  final Widget? trailing;

  /// The sheet's dial: one wheel, wider.
  final bool hero;

  /// A wheel's widest, at 1× text (it grows with the text); narrower when
  /// three share a row, to leave the gutters room.
  static const wheelWidth = 120.0;
  static const narrowWheelWidth = 80.0;
  static const heroWheelWidth = 208.0;

  /// The width of [trailing].
  static const trailingWidth = 56.0;

  /// The least room left free each side of the wheels.
  static const gutter = 28.0;
  static const gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final trailing = this.trailing;
    final columns = wheels.length + (trailing == null ? 0 : 1);
    final stacked = columns > 1 && scaler.scale(10) > 13;
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = math.max(0.0, constraints.maxWidth - 2 * gutter);
        final cap = hero
            ? heroWheelWidth
            : wheels.length >= 3
            ? narrowWheelWidth
            : wheelWidth;
        final widest = math.min(math.max(scaler.scale(cap), cap), room);
        if (stacked) {
          return Column(
            children: [
              for (final wheel in wheels)
                Center(
                  child: SizedBox(width: widest, child: wheel),
                ),
              if (trailing != null)
                Center(
                  child: SizedBox(width: trailingWidth, child: trailing),
                ),
            ],
          );
        }
        final forWheels =
            room - gap * (columns - 1) - (trailing == null ? 0 : trailingWidth);
        final each = math.min(widest, forWheels / wheels.length);
        // Centred: the spare room goes evenly to both sides (Burooj, 14 Nov:
        // "the three wheels sit left of centre").
        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, wheel) in wheels.indexed) ...[
                if (i > 0) const SizedBox(width: gap),
                SizedBox(width: each, child: wheel),
              ],
              if (trailing != null) ...[
                const SizedBox(width: gap),
                SizedBox(width: trailingWidth, child: trailing),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A volume (0 to 1) standing as a column beside wheels: its title level
/// with theirs, a vertical slider as tall as they are, and the level under
/// it.
class _VolumeColumn extends StatelessWidget {
  const _VolumeColumn({
    super.key,
    required this.label,
    this.title,
    required this.value,
    required this.height,
    required this.format,
    required this.onChanged,
  });

  /// What a screen reader calls it.
  final String label;

  /// The word above it; none where the wheels beside it show none.
  final String? title;
  final double value;

  /// The wheels' height.
  final double height;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final labelStyle = type.baseline.labelLarge?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final title = this.title;
    return Semantics(
      label: label,
      child: Column(
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, top: 4),
              child: ExcludeSemantics(
                child: SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(
                    (labelStyle?.fontSize ?? 14) * (labelStyle?.height ?? 1.43),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(title, maxLines: 1, style: labelStyle),
                  ),
                ),
              ),
            ),
          SizedBox(
            height: math.max(0, height - 24),
            child: RotatedBox(
              quarterTurns: 3,
              child: Slider(
                value: value.clamp(0, 1),
                divisions: 20,
                label: format(value),
                semanticFormatterCallback: format,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            height: 24,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ExcludeSemantics(
                child: Text(
                  format(value),
                  style: type.emphasized.bodyMedium?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "60 ⟶ 40 BPM" with [over] ("over 20 min") set small above the arrow:
/// the pulse's ramp at a glance. Shrinks to fit a narrow tile.
class _RampSummary extends StatelessWidget {
  const _RampSummary({
    required this.from,
    required this.to,
    required this.over,
  });

  final String from, to, over;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final small = context.typography.baseline.labelSmall?.copyWith(
      color: style.color,
    );
    return ExcludeSemantics(
      child: FittedBox(
        key: const ValueKey('customize_rhythm_ramp'),
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(from),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(over, style: small, textAlign: TextAlign.center),
                    SizedBox(
                      height: (style.fontSize ?? 12) * (style.height ?? 1.3),
                      child: CustomPaint(
                        painter: _ArrowPainter(style.color ?? Colors.black),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(to),
          ],
        ),
      ),
    );
  }
}

/// A long arrow across its box, at the middle of the line: "⟶".
class _ArrowPainter extends CustomPainter {
  const _ArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final y = size.height * 0.55;
    final end = size.width - 1;
    canvas
      ..drawLine(Offset(1, y), Offset(end, y), paint)
      ..drawPath(
        Path()
          ..moveTo(end - 5, y - 4)
          ..lineTo(end, y)
          ..lineTo(end - 5, y + 4),
        paint,
      );
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) => oldDelegate.color != color;
}

class _Caption extends StatelessWidget {
  const _Caption(this.text, {this.centred = false});
  final String text;
  final bool centred;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      text,
      textAlign: centred ? TextAlign.center : null,
      style: context.typography.baseline.bodyMedium?.copyWith(
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
