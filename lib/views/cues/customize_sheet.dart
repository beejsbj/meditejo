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
import 'package:medito/providers/player/playback_speed_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/providers/timer/timer_settings_provider.dart';
import 'package:medito/services/audio/session_bell_preview.dart';
import 'package:medito/services/bells/custom_bell.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/views/cues/bell_list.dart';
import 'package:medito/views/soundscape/sounds_sheet.dart';
import 'package:medito/widgets/art/art_cover.dart';
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

/// The Timer's ∞ among the fields an Undo compares, where the dial sets it.
const _openEndedField = 'timer.openEnded';

/// What a wheel changed, kept so the Undo bar can put it back. Steps of the
/// same wheel while its bar is up (a turn, then another; a screen reader's
/// three swipes) are one change: Undo goes back to before the first.
class _WheelUndo {
  const _WheelUndo({
    required this.label,
    required this.message,
    required this.was,
    required this.set,
    required this.courseOverride,
  });

  /// The step from [before] to [after] of the wheel [label]; null when it
  /// changed nothing.
  static _WheelUndo? of(
    String label,
    String message,
    Map<String, Object?> before,
    Map<String, Object?> after, {
    required bool courseOverride,
  }) => const _WheelUndo(
    label: '',
    message: '',
    was: {},
    set: {},
    courseOverride: false,
  )._then(label, message, before, after, courseOverride: courseOverride);

  /// The wheel this is for, and where its change was saved (a course's own
  /// settings or its kind's).
  final String label;
  final bool courseOverride;
  final String message;

  /// The fields the wheel touched: as they were before its first step, and
  /// as its last step set them.
  final Map<String, Object?> was, set;

  /// Whether a step of [label] continues this change.
  bool continuedBy(String label, {required bool courseOverride}) =>
      label == this.label && courseOverride == this.courseOverride;

  /// This change followed by the step [from] to [to] of [label]; null when,
  /// all told, nothing is changed (the wheel went back).
  _WheelUndo? _then(
    String label,
    String message,
    Map<String, Object?> from,
    Map<String, Object?> to, {
    required bool courseOverride,
  }) {
    final was = {...this.was}, set = {...this.set};
    for (final key in to.keys) {
      if (to[key] == from[key]) continue;
      was.putIfAbsent(key, () => from[key]);
      set[key] = to[key];
    }
    was.removeWhere((key, value) => set[key] == value);
    set.removeWhere((key, _) => !was.containsKey(key));
    if (set.isEmpty) return null;
    return _WheelUndo(
      label: label,
      message: message,
      was: was,
      set: set,
      courseOverride: courseOverride,
    );
  }

  /// [now] with each field put back that still holds what the wheel set;
  /// null when nothing is left to put back.
  Map<String, Object?>? revert(Map<String, Object?> now) {
    final restored = {...now};
    var reverted = false;
    for (final MapEntry(:key, :value) in set.entries) {
      if (restored[key] != value) continue;
      restored[key] = was[key];
      reverted = true;
    }
    return reverted ? restored : null;
  }
}

/// The settings behind the tiles, in the order they show: the three bells
/// and the rhythm. Each opens as a card of its own, in place of the dial
/// and the tiles.
enum _Card { startBell, intervalBell, endBell, rhythm }

/// Cue settings in one place, the same sheet wherever it opens. On top, one
/// large wheel: a timer's length (∞ at its top: open-ended, counting up), or
/// the silence a recording is extended by. Under it a 2×2 grid of tiles,
/// each showing its value (filled when it differs from the defaults,
/// outlined when it does not); tapping one swaps the sheet's content for
/// that setting's card, with a back arrow. Sound is the header's button,
/// which opens the Sounds sheet. Edits are saved as the defaults for the
/// scope's kind (or as a per-course override) and picked up by the player
/// through the provider.
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

class _CustomizeSheetState extends ConsumerState<CustomizeSheet>
    with SingleTickerProviderStateMixin {
  Timer? _tick;
  late bool _courseOverride;
  late final SessionBellPreview _preview;

  /// The card open in place of the dial and the tiles; null on them.
  _Card? _card;

  /// The card on screen: [_card], and for a moment after Back the one that
  /// is leaving.
  _Card? _shown;

  /// 0 on the dial and the tiles, 1 on a card.
  late final AnimationController _cardMotion;
  final _wheels = WheelSettleGroup();
  bool _startPending = false;

  /// The last change a wheel made, offered back for a moment (#91): a thumb
  /// scrolling the sheet can land on a wheel and turn it.
  _WheelUndo? _undo;
  Timer? _undoTimer;

  /// Room under the list for the bar, kept from its first showing until a
  /// card opens or closes: taking it away when the bar goes would move the
  /// list under the thumb.
  bool _undoRoom = false;

  /// How long the Undo bar stays: a little longer than a snackbar, and
  /// longer again for a screen reader, which has to find the button.
  static const _undoFor = Duration(seconds: 5);
  static const _undoForScreenReader = Duration(seconds: 10);

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
    _cardMotion =
        AnimationController(
          vsync: this,
          duration: MeditejoMotion.medium,
          reverseDuration: MeditejoMotion.short,
        )..addStatusListener((status) {
          // The card that was left has gone: drop it.
          if (status == AnimationStatus.dismissed && mounted && _card == null) {
            setState(() => _shown = null);
          }
        });
    _tick = Timer.periodic(
      const Duration(seconds: 30),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    _undoTimer?.cancel();
    _cardMotion.dispose();
    // A bell auditioned here never rings on after the sheet closes.
    _silence();
    super.dispose();
  }

  void _edit(CueSettings value) => unawaited(
    ref
        .read(cueSettingsProvider(_scope).notifier)
        .update(value, courseOverride: _courseOverride),
  );

  /// A wheel for [label] on [card] (null: the dial); what it lands on is
  /// saved through [apply], with an Undo bar ("Slow down over: 9 min ·
  /// Undo"). [title] is the shorter word shown above it, where the row
  /// already says the rest.
  Widget _wheel<T>({
    required _Card? card,
    required String label,
    String? title,
    required List<WheelOption<T>> options,
    required T value,
    required CueSettings Function(T value) apply,
    T? Function(String)? parse,
    String? hint,
    int visibleItems = 5,
    bool showLabel = true,
    bool enabled = true,
    bool large = false,
  }) => _WheelField<T>(
    label: label,
    title: title,
    options: options,
    value: value,
    parse: parse,
    hint: hint,
    visibleItems: visibleItems,
    showLabel: showLabel,
    enabled: enabled,
    large: large,
    onChanged: (v) {
      final shown = options.firstWhere((o) => o.value == v).label;
      // A step that lands after its card has closed is saved, but brings
      // no bar up over what is shown instead.
      _turned(label, shown, apply(v), offerUndo: mounted && _card == card);
    },
  );

  /// Whether the Timer about to start is open-ended, as its dial is set.
  bool get _openEndedNow =>
      ref.read(timerSettingsProvider).mode == TimerMode.stopwatch;

  /// The settings as an Undo compares them: with the Timer's ∞, where the
  /// dial sets it.
  Map<String, Object?> _snapshot(CueSettings s, {bool? openEnded}) => {
    ...s.toJson(),
    if (_canSetDuration) _openEndedField: openEnded ?? _openEndedNow,
  };

  /// Saves what a wheel landed on and offers it back. Further steps of the
  /// same wheel while its bar is up join its change. [openEnded] is the
  /// dial's ∞, kept with the Timer rather than in [next].
  void _turned(
    String label,
    String shown,
    CueSettings next, {
    bool? openEnded,
    bool offerUndo = true,
  }) {
    if (!mounted) return;
    final before = _snapshot(ref.read(cueSettingsProvider(_scope)));
    final after = _snapshot(next, openEnded: openEnded);
    _save(next, openEnded: openEnded);
    if (!offerUndo) return _dismissUndo();
    final message = _l10n.customizeUndoChange(label, shown);
    final open = _undo;
    final undo =
        open != null && open.continuedBy(label, courseOverride: _courseOverride)
        ? open._then(
            label,
            message,
            before,
            after,
            courseOverride: _courseOverride,
          )
        : _WheelUndo.of(
            label,
            message,
            before,
            after,
            courseOverride: _courseOverride,
          );
    // Back where it started: nothing to undo.
    if (undo == null) {
      if (open != null) _dismissUndo();
      return;
    }
    _undoTimer?.cancel();
    _undoTimer = Timer(
      MediaQuery.of(context).accessibleNavigation
          ? _undoForScreenReader
          : _undoFor,
      _dismissUndo,
    );
    setState(() {
      _undo = undo;
      _undoRoom = true;
    });
  }

  void _save(CueSettings value, {bool? openEnded}) {
    if (openEnded != null) {
      ref
          .read(timerSettingsProvider.notifier)
          .setMode(openEnded ? TimerMode.stopwatch : TimerMode.countdown);
    }
    _edit(value);
  }

  /// The bar's height and the space around it, at the current text size.
  static double _undoBarRoom(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(48) + 16;

  /// The bar goes when it has been read, and as soon as a card opens or
  /// closes: the person has moved on, and it would sit over what they see
  /// next.
  void _dismissUndo() {
    _undoTimer?.cancel();
    _undoTimer = null;
    if (mounted && _undo != null) setState(() => _undo = null);
  }

  /// Puts back what the wheel changed, unless it has been changed again
  /// since (by another control, or with the "only for this course" switch
  /// flipped): those are left as they are.
  void _undoTurn() {
    final undo = _undo;
    _dismissUndo();
    if (undo == null || undo.courseOverride != _courseOverride) return;
    final restored = undo.revert(
      _snapshot(ref.read(cueSettingsProvider(_scope))),
    );
    if (restored == null) return;
    final openEnded = restored.remove(_openEndedField);
    _save(
      CueSettings.fromJson(restored, kind: _scope.kind),
      openEnded: openEnded is bool ? openEnded : null,
    );
  }

  /// Swaps the dial and the tiles for [card].
  void _openCard(_Card card) {
    _dismissUndo();
    setState(() {
      _card = card;
      _shown = card;
      _undoRoom = false;
    });
    if (MediaQuery.of(context).disableAnimations) {
      _cardMotion.value = 1;
    } else {
      unawaited(_cardMotion.forward());
    }
  }

  /// Back to the dial and the tiles, where they were left.
  void _closeCard() {
    if (_card == null) return;
    _dismissUndo();
    // Leaving a bell's card silences what it was auditioning.
    _silence();
    final reduce = MediaQuery.of(context).disableAnimations;
    setState(() {
      _card = null;
      _undoRoom = false;
      if (reduce) _shown = null;
    });
    if (reduce) {
      _cardMotion.value = 0;
    } else {
      unawaited(_cardMotion.reverse());
    }
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

  AppLocalizations get _l10n =>
      AppLocalizations.of(context) ??
      lookupAppLocalizations(const Locale('en'));

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(cueSettingsProvider(_scope));
    final reference = _reference;
    final reduce = MediaQuery.of(context).disableAnimations;
    // Large text makes the switch several lines tall: pinned, it would leave
    // the list no room, so it ends the list instead.
    final pinSwitch = MediaQuery.textScalerOf(context).scale(10) <= 13;
    final showBefore = widget.isTimer ? null : _showBeforeSwitch(s);
    // Once the Undo bar has shown, the list ends below it (until a card
    // opens or closes), so whatever it covers can be scrolled clear.
    final listPadding = EdgeInsets.fromLTRB(
      16,
      4,
      16,
      16 + (_undoRoom ? _undoBarRoom(context) : 0),
    );

    final main = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(subtitle: _scopeLine, sound: _soundButton(s, reference)),
        Flexible(
          child: SingleChildScrollView(
            key: const ValueKey('customize_list'),
            padding: listPadding,
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

    final shown = _shown;
    final card = shown == null
        ? null
        : KeyedSubtree(
            key: ValueKey('customize_card_${shown.name}'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardHeader(title: _cardTitle(shown), onBack: _closeCard),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('customize_card_list'),
                    padding: listPadding,
                    child: _cardBody(shown, s),
                  ),
                ),
              ],
            ),
          );

    // The dial and the tiles stay laid out under an open card: Back finds
    // them where they were left, and the sheet is never shorter for a card.
    final onCard = _card != null;
    final panes = AnimatedBuilder(
      animation: _cardMotion,
      builder: (context, _) {
        final t = MeditejoMotion.emphasizedDecelerate.transform(
          _cardMotion.value,
        );
        return Stack(
          children: [
            ExcludeSemantics(
              excluding: onCard,
              child: IgnorePointer(
                ignoring: onCard,
                child: _Pane(at: -t, child: main),
              ),
            ),
            if (card != null)
              IgnorePointer(
                ignoring: !onCard,
                child: _Pane(at: 1 - t, child: card),
              ),
          ],
        );
      },
    );

    return PopScope(
      // Back closes an open card before it closes the sheet.
      canPop: !onCard,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeCard();
      },
      child: WheelSettleScope(
        group: _wheels,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final media = MediaQuery.of(context);
            // As tall as what it shows, up to most of the screen.
            final height = math.min(
              constraints.maxHeight,
              media.size.height * 0.92,
            );
            // The Undo bar floats over the foot of the list, as a snackbar
            // would: one on the page's Scaffold would sit behind this sheet.
            final undo = _undo;
            final bar = undo == null
                ? const SizedBox.shrink()
                : _UndoBar(
                    key: ObjectKey(undo),
                    message: undo.message,
                    onUndo: _undoTurn,
                  );
            final area = Stack(
              fit: StackFit.passthrough,
              children: [
                // Reduced motion resizes in one step. (A zero-length
                // AnimatedSize restarts inside its own layout and asserts,
                // so it is left out.)
                if (reduce)
                  panes
                else
                  AnimatedSize(
                    duration: MeditejoMotion.medium,
                    curve: MeditejoMotion.emphasizedDecelerate,
                    alignment: Alignment.topCenter,
                    child: panes,
                  ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 8,
                  child: reduce
                      ? bar
                      : AnimatedSwitcher(
                          duration: MeditejoMotion.short,
                          child: bar,
                        ),
                ),
              ],
            );
            return SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(child: area),
                    if (pinSwitch) ?showBefore,
                    ?_startButton,
                  ],
                ),
              ),
            );
          },
        ),
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
      above: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _WheelRow([
          _wheel<int>(
            card: card,
            label: 'Countdown',
            options: const [
              WheelOption(0, 'Off'),
              WheelOption(5, '5 sec', semanticsLabel: '5 seconds'),
              WheelOption(10, '10 sec', semanticsLabel: '10 seconds'),
            ],
            value: s.countdownSeconds,
            visibleItems: 3,
            apply: (v) => s.copyWith(countdownSeconds: v),
          ),
        ]),
      ),
    ),
    _Card.intervalBell => _bellCard(
      s,
      selected: s.intervalSound,
      apply: (v) => s.copyWith(intervalSound: v),
      above: _intervalWheels(s),
    ),
    _Card.endBell => _bellCard(
      s,
      selected: s.endSound,
      apply: (v) => s.copyWith(endSound: v),
      // A timer's length is its own: silence after it is just a longer
      // timer.
      above: widget.isTimer ? null : _endSilence(s),
    ),
    _Card.rhythm => _pulseEditor(s),
  };

  /// A bell's card: what is its own ([above]), the list of bells (tap to
  /// choose and hear, "Make a bell" last), and the volume all bells share.
  Widget _bellCard(
    CueSettings s, {
    required String selected,
    required CueSettings Function(String) apply,
    Widget? above,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ?above,
      BellList(
        selected: selected,
        volume: s.bellVolume,
        onSelected: (v) {
          _edit(apply(v));
          _audition(v, s.bellVolume);
        },
      ),
      const SizedBox(height: 8),
      _SliderRow(
        icon: Icons.volume_up_outlined,
        label: 'Bell volume',
        value: s.bellVolume,
        format: _percent,
        onChanged: (v) => _edit(s.copyWith(bellVolume: v)),
      ),
    ],
  );

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
                  final now = ref.read(cueSettingsProvider(_scope));
                  _turned(
                    'Duration',
                    v == 0 ? '∞' : _minutes(v),
                    v == 0 ? now : now.copyWith(durationMinutes: v),
                    openEnded: v == 0,
                    offerUndo: mounted && _card == null,
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
          child: IconButton.filledTonal(
            key: const ValueKey('customize_infinity'),
            isSelected: openEnded,
            tooltip: l10n.timerOpenEnded,
            icon: const Icon(Icons.all_inclusive_rounded),
            onPressed: () {
              _dismissUndo();
              _save(s, openEnded: !openEnded);
            },
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
          // Where changes go moves: the bar's Undo no longer applies.
          _dismissUndo();
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
  /// Ending bell, as #72 groups it. Its own setting, apart from Extend.
  Widget _endSilence(CueSettings s) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The caption is the wheel's title.
        _Caption(_l10n.extendEndCaption, centred: true),
        _WheelRow([
          _wheel<int>(
            card: _Card.endBell,
            label: _l10n.extendEndLabel,
            showLabel: false,
            options: _extraMinuteOptions,
            value: s.endSilenceMinutes,
            parse: _range(0, 60),
            hint: '0 to 60 minutes',
            visibleItems: 3,
            apply: (v) => s.copyWith(endSilenceMinutes: v),
          ),
        ]),
      ],
    ),
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
    final sum = recording == null
        ? null
        : s.extraMinutes == 0
        ? _minutes(recording)
        : '${[recording, if (s.extendMinutes > 0) s.extendMinutes, if (s.endSilenceMinutes > 0) s.endSilenceMinutes].map(_minutes).join(' + ')}'
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
            card: null,
            label: _l10n.extendTitle,
            showLabel: false,
            large: _largeDial,
            visibleItems: 3,
            options: _extraMinuteOptions,
            value: s.extendMinutes,
            parse: _range(0, 60),
            hint: '0 to 60 minutes',
            apply: (v) => s.copyWith(extendMinutes: v),
          ),
        ], hero: _largeDial),
        if (sum != null || widget.showFinishes) ...[
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              if (sum != null)
                Text(
                  sum,
                  key: const ValueKey('customize_total'),
                  style: type.baseline.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (widget.showFinishes) _finishes(context, s),
            ],
          ),
        ],
      ],
    );
  }

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
      child: _WheelRow([
        _wheel<int>(
          card: _Card.intervalBell,
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
            card: _Card.intervalBell,
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
      ]),
    );
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
          // (#73). Ends at waits, dimmed, until there is a ramp to end.
          _WheelRow([
            _wheel<double>(
              card: _Card.rhythm,
              label: l10n.customizeRhythmRate,
              options: bpm,
              value: s.pulseBpm.roundToDouble(),
              parse: parseBpm,
              hint: '20 to 120 BPM',
              apply: (v) => s.copyWith(pulseBpm: v),
            ),
            _wheel<int>(
              card: _Card.rhythm,
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
              card: _Card.rhythm,
              label: l10n.customizeRhythmEndsAt,
              options: bpm,
              value: s.pulseEndBpm.roundToDouble(),
              parse: parseBpm,
              hint: '20 to 120 BPM',
              enabled: s.pulseRampMinutes > 0,
              apply: (v) => s.copyWith(pulseEndBpm: v),
            ),
          ]),
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

  SoundscapeSessionKind get _soundscapeKind => soundscapeKindFor(_scope.kind);

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
      // Only a single sound, or a mix of its own, needs the library
      // (loaded on demand).
      selection.kind == SoundscapeSelectionKind.sound ||
              selection.kind == SoundscapeSelectionKind.layers
          ? ref.read(soundLibraryProvider).value
          : null,
    );
  }

  /// Opens the Sounds sheet on what plays under these sessions; what is
  /// left in it is kept: for the course when it has its own settings,
  /// otherwise for the kind (the Sounds sheet's "Plays under" line shows the
  /// same). During a session it plays at once.
  Future<void> _chooseSound() async {
    _dismissUndo();
    _silence();
    // Taken now: the sheet may be gone by the time the Sounds sheet closes.
    final container = ProviderScope.containerOf(context);
    final scope = _scope;
    final courseOverride = _courseOverride;
    final inSession = widget.isActive;
    final choice = await showSoundsSheetFor(
      context,
      kind: _soundscapeKind,
      current: _soundscapeChoice(
        ref.read(cueSettingsProvider(scope)),
        ref.read(soundscapeProvider),
      ),
      inSession: inSession,
      // A course's own choice, made away from its session, is not what a
      // running sit of the kind plays.
      playsNow: inSession || !courseOverride,
      // Its messenger's snackbars would sit under this sheet.
      announce: false,
    );
    if (choice == null) return;
    chooseScopeSound(
      container,
      scope,
      choice,
      courseOverride: courseOverride,
      inSession: inSession,
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

  /// Whether what plays under these sessions differs from the defaults:
  /// for a course, from its kind's choice; for a kind, from nothing.
  bool _soundDiffers(CueSettings s, CueSettings reference) {
    final mixer = ref.watch(soundscapeProvider);
    final choice = _soundscapeChoice(s, mixer).encode();
    if (_courseOverride) {
      return choice != _soundscapeChoice(reference, mixer).encode();
    }
    return choice != SoundscapeSelection.none.encode();
  }

  /// The header's Sound button: what plays under these sessions, by name,
  /// with the chosen sound's art as on the Sounds screen. Filled when it
  /// differs from the defaults. It opens the Sounds sheet (#66).
  Widget _soundButton(CueSettings s, CueSettings reference) {
    final mixer = ref.watch(soundscapeProvider);
    final subject = soundChoiceArt(mixer, _soundscapeChoice(s, mixer));
    return _SoundButton(
      key: const ValueKey('customize_sound'),
      art: subject == null
          ? null
          : ClipRRect(
              key: const ValueKey('customize_sound_art'),
              borderRadius: BorderRadius.circular(MeditejoShapes.small),
              child: SizedBox.square(
                dimension: 28,
                child: ArtCover(subject: subject),
              ),
            ),
      label: _l10n.customizeSlotSound,
      value: _backgroundValue(s),
      changed: _soundDiffers(s, reference),
      onTap: _chooseSound,
    );
  }

  String _backgroundValue(CueSettings s) {
    final mixer = ref.watch(soundscapeProvider);
    return soundChoiceLabel(
      _l10n,
      mixer,
      ref.watch(soundLibraryProvider).value ?? SoundLibrary.empty,
      _soundscapeChoice(s, mixer),
    );
  }
}

/// The dial and the tiles, or a card: faded and slid a little aside by how
/// far it is from being the one shown ([at]: 0 shown, -1 gone to the left,
/// 1 waiting on the right).
class _Pane extends StatelessWidget {
  const _Pane({required this.at, required this.child});

  final double at;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: (1 - at.abs()).clamp(0.0, 1.0),
    child: Transform.translate(
      offset: Directionality.of(context) == TextDirection.rtl
          ? Offset(-at * 40, 0)
          : Offset(at * 40, 0),
      child: child,
    ),
  );
}

/// The sheet's title and whose settings these are, with the Sound button
/// at the end of the row: the same place wherever the sheet opens.
class _Header extends StatelessWidget {
  const _Header({required this.subtitle, required this.sound});

  final String subtitle;
  final Widget sound;

  @override
  Widget build(BuildContext context) {
    final type = context.typography;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
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
          sound,
        ],
      ),
    );
  }
}

/// A card's own header: Back, and the name of the tile that opened it.
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('customize_card_back'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onBack,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: context.typography.emphasized.headlineSmall,
            ),
          ),
        ),
      ],
    ),
  );
}

/// What plays under the session, as a button: its art (or the Sounds
/// symbol) and its name. Filled when a sound is chosen that the defaults
/// do not have, outlined otherwise.
class _SoundButton extends StatelessWidget {
  const _SoundButton({
    super.key,
    required this.art,
    required this.label,
    required this.value,
    required this.changed,
    required this.onTap,
  });

  final Widget? art;
  final String label, value;
  final bool changed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onColor = changed ? scheme.onSecondaryContainer : scheme.onSurface;
    return Semantics(
      button: true,
      label: '$label, $value',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: changed ? scheme.secondaryContainer : Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: StadiumBorder(
          side: changed
              ? BorderSide.none
              : BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 16, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 28,
                    child: Center(
                      child:
                          art ??
                          Icon(
                            Icons.graphic_eq_rounded,
                            size: 22,
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.textScalerOf(context).scale(132),
                      ),
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.typography.emphasized.labelLarge
                            ?.copyWith(color: onColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
/// there and scrolls it, rather than turning a wheel. When large text needs
/// the width they stack, each still centred between gutters.
class _WheelRow extends StatelessWidget {
  const _WheelRow(this.wheels, {this.hero = false});

  final List<Widget> wheels;

  /// The sheet's dial: one wheel, wider.
  final bool hero;

  /// A wheel's widest, at 1× text (it grows with the text); narrower when
  /// three share a row, to leave the gutters room.
  static const wheelWidth = 120.0;
  static const narrowWheelWidth = 80.0;
  static const heroWheelWidth = 208.0;

  /// The least room left free each side of the wheels.
  static const gutter = 28.0;
  static const gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final stacked = wheels.length > 1 && scaler.scale(10) > 13;
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
            ],
          );
        }
        final each = math.min(
          widest,
          (room - gap * (wheels.length - 1)) / wheels.length,
        );
        final row = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, wheel) in wheels.indexed) ...[
              if (i > 0) const SizedBox(width: gap),
              SizedBox(width: each, child: wheel),
            ],
          ],
        );
        if (wheels.length == 1) return Center(child: row);
        // Spare room beyond the 28 dp gutters goes 1 : 4, the larger share
        // on the right, where a right thumb scrolls: about 50 dp there for
        // three wheels at 411 dp. Where there is no spare room (360 dp),
        // both gutters stay at 28 dp.
        final used = each * wheels.length + gap * (wheels.length - 1);
        final spare = math.max(0.0, constraints.maxWidth - used - 2 * gutter);
        return Padding(
          padding: EdgeInsetsDirectional.only(start: gutter + spare * 0.2),
          child: Align(alignment: AlignmentDirectional.centerStart, child: row),
        );
      },
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

/// The bar a wheel's change brings up: what it set, and Undo. Styled as
/// the app's snackbars; announced to a screen reader as it appears.
class _UndoBar extends StatelessWidget {
  const _UndoBar({super.key, required this.message, required this.onUndo});

  final String message;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('en'));
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        key: const ValueKey('customize_undo'),
        color: scheme.inverseSurface,
        shape: MeditejoShapes.rounded(MeditejoShapes.medium),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    message,
                    style: context.typography.baseline.bodyMedium?.copyWith(
                      color: scheme.onInverseSurface,
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('customize_undo_button'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.inversePrimary,
                  ),
                  onPressed: onUndo,
                  child: Text(l10n.undo),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
