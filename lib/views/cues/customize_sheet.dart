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
import 'package:medito/providers/player/audio_state_provider.dart';
import 'package:medito/providers/player/playback_speed_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/audio/session_bell_preview.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/views/soundscape/sound_drawer.dart';
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
    CueSettings before,
    CueSettings after, {
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

  /// This change followed by the step [before] to [after] of [label];
  /// null when, all told, nothing is changed (the wheel went back).
  _WheelUndo? _then(
    String label,
    String message,
    CueSettings before,
    CueSettings after, {
    required bool courseOverride,
  }) {
    final from = before.toJson(), to = after.toJson();
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

  /// [current] with each field put back that still holds what the wheel
  /// set; null when nothing is left to put back.
  CueSettings? revert(CueSettings current, CueKind kind) {
    final now = current.toJson();
    var reverted = false;
    for (final MapEntry(:key, :value) in set.entries) {
      if (now[key] != value) continue;
      now[key] = was[key];
      reverted = true;
    }
    return reverted ? CueSettings.fromJson(now, kind: kind) : null;
  }
}

/// The four things a sit is made of, in the order the sheet's tiles show
/// them: what plays under it, its bells, its rhythm and its length. The same
/// four slots a preset holds (#64), so Customize, presets and saving read as
/// one system.
enum _Slot { sound, bells, rhythm, length }

/// Which bell row of the Bells section is open. One at a time, so the
/// section never turns into a wall of controls.
enum _Part { startBell, intervalBell, endBell }

/// Cue settings in one place. The sheet opens on a 2×2 grid of the slots,
/// each tile showing its value (filled when it differs from the defaults,
/// outlined when it does not); tapping one opens its section under its row.
/// Edits are saved as the defaults for the scope's kind (or as a per-course
/// override) and picked up by the player through the provider.
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

  /// A timer length chosen elsewhere; the Length tile then shows it rather
  /// than setting it (a stopwatch passes 0).
  final int? timerMinutes;
  final DateTime Function() clock;

  @override
  ConsumerState<CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends ConsumerState<CustomizeSheet> {
  Timer? _tick;
  late bool _courseOverride;
  late final SessionBellPreview _preview;
  _Slot? _slot;

  /// A slot just opened, to bring into view once its section is laid out.
  _Slot? _reveal;
  final _tileKeys = {for (final slot in _Slot.values) slot: GlobalKey()};
  _Part? _open;
  final _wheels = WheelSettleGroup();
  bool _startPending = false;

  /// The last change a wheel made, offered back for a moment (#91): a thumb
  /// scrolling the sheet can land on a wheel and turn it.
  _WheelUndo? _undo;
  Timer? _undoTimer;

  /// Room under the list for the bar, kept from its first showing until the
  /// open section or row folds: taking it away when the bar goes would move
  /// the list under the thumb.
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
    _tick = Timer.periodic(
      const Duration(seconds: 30),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    _undoTimer?.cancel();
    // A bell auditioned here never rings on after the sheet closes.
    _silence();
    super.dispose();
  }

  void _edit(CueSettings value) => unawaited(
    ref
        .read(cueSettingsProvider(_scope).notifier)
        .update(value, courseOverride: _courseOverride),
  );

  /// A wheel for [label]; what it lands on is saved through [apply], with
  /// an Undo bar ("Slow down over: 9 min · Undo"). [title] is the shorter
  /// word shown above it, where the row already says the rest.
  Widget _wheel<T>({
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
  }) {
    // Where this wheel is: a step that lands after its section or row has
    // closed is saved, but brings no bar up over what opened instead.
    final slot = _slot, part = _open;
    return _WheelField<T>(
      label: label,
      title: title,
      options: options,
      value: value,
      parse: parse,
      hint: hint,
      visibleItems: visibleItems,
      showLabel: showLabel,
      enabled: enabled,
      onChanged: (v) {
        final shown = options.firstWhere((o) => o.value == v).label;
        _turned(
          label,
          shown,
          apply(v),
          offerUndo: mounted && _slot == slot && _open == part,
        );
      },
    );
  }

  /// Saves what a wheel landed on and offers it back. Further steps of the
  /// same wheel while its bar is up join its change.
  void _turned(
    String label,
    String shown,
    CueSettings next, {
    bool offerUndo = true,
  }) {
    if (!mounted) return;
    final before = ref.read(cueSettingsProvider(_scope));
    _edit(next);
    if (!offerUndo) return _dismissUndo();
    final message = _l10n.customizeUndoChange(label, shown);
    final open = _undo;
    final undo =
        open != null && open.continuedBy(label, courseOverride: _courseOverride)
        ? open._then(
            label,
            message,
            before,
            next,
            courseOverride: _courseOverride,
          )
        : _WheelUndo.of(
            label,
            message,
            before,
            next,
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

  /// The bar's height and the space around it, at the current text size.
  static double _undoBarRoom(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(48) + 16;

  /// The bar goes when it has been read, and as soon as a section or row
  /// opens or folds: the person has moved on, and it would sit over what
  /// they open next.
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
      ref.read(cueSettingsProvider(_scope)),
      _scope.kind,
    );
    if (restored != null) _edit(restored);
  }

  /// Opens [slot]'s section under its row of tiles, or folds it.
  void _toggleSlot(_Slot slot) {
    _dismissUndo();
    final leaving = _slot;
    setState(() {
      _slot = _slot == slot ? null : slot;
      _reveal = _slot;
      _undoRoom = false;
      _open = null;
    });
    // Leaving the bells silences what they were auditioning.
    if (leaving == _Slot.bells) _silence();
    // Without motion the section is there on the next frame; otherwise once
    // it has grown (AnimatedSize.onEnd), when there is room to scroll to.
    if (MediaQuery.of(context).disableAnimations) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealOpen());
    }
  }

  /// Scrolls the open tile to the top of the list, so its section sits
  /// under it in view, with the tile still saying what the section is.
  void _revealOpen() {
    final slot = _reveal;
    _reveal = null;
    if (slot == null || !mounted || _slot != slot) return;
    final tile = _tileKeys[slot]!.currentContext;
    if (tile == null) return;
    final reduce = MediaQuery.of(context).disableAnimations;
    unawaited(
      Scrollable.ensureVisible(
        tile,
        duration: reduce ? Duration.zero : MeditejoMotion.short,
        curve: MeditejoMotion.emphasizedDecelerate,
      ),
    );
  }

  void _toggle(_Part part) {
    _dismissUndo();
    final closing = _open;
    setState(() {
      _open = _open == part ? null : part;
      _undoRoom = false;
    });
    // Folding a bell list silences what it was auditioning.
    if (closing != null) _silence();
  }

  void _silence() => unawaited(_preview.stop().catchError((Object _) {}));

  /// Rings [asset] once at [volume], as a session would. Best effort: a tap
  /// that interrupts a still-loading bell, or a sound the platform will not
  /// play, is not an error worth surfacing.
  void _audition(String asset, double volume) => unawaited(
    (asset.isEmpty ? _preview.stop() : _preview.play(volume, asset: asset))
        .catchError((Object _) {}),
  );

  /// The sheet sets a timer's length itself only where nothing else does:
  /// a recording owns its length, and a stopwatch has none.
  bool get _canSetDuration =>
      widget.isTimer && widget.timerMinutes == null && widget.onStart != null;

  AppLocalizations get _l10n =>
      AppLocalizations.of(context) ??
      lookupAppLocalizations(const Locale('en'));

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(cueSettingsProvider(_scope));
    final reference = _reference;
    final open = _slot;
    final reduce = MediaQuery.of(context).disableAnimations;
    // Large text makes the switch several lines tall: pinned, it would leave
    // the list no room, so it ends the list instead.
    final pinSwitch = MediaQuery.textScalerOf(context).scale(10) <= 13;
    final showBefore = widget.isTimer ? null : _showBeforeSwitch(s);

    final section = open == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 12),
            child: KeyedSubtree(
              key: ValueKey('customize_section_${open.name}'),
              child: _section(open, s),
            ),
          );

    final list = SingleChildScrollView(
      key: const ValueKey('customize_list'),
      // Once the Undo bar has shown, the list ends below it (until the
      // section folds), so whatever it covers can be scrolled clear.
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + (_undoRoom ? _undoBarRoom(context) : 0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // With large text the course card follows the tiles, so a small
          // phone opens on the tiles and not on the card.
          if (_scope.courseId != null && pinSwitch) ...[
            _scopeCard(s, compact: false),
            const SizedBox(height: 16),
          ],
          // A section opens right under its tile's row, so the two read
          // together.
          _SlotGrid(
            tiles: [for (final slot in _Slot.values) _tile(slot, s, reference)],
            below: (row) {
              final here = open != null && open.index ~/ 2 == row
                  ? section
                  : null;
              // Reduced motion opens in one step. (A zero-length
              // AnimatedSize restarts inside its own layout and asserts, so
              // it is left out.)
              if (reduce) return here;
              return AnimatedSize(
                duration: MeditejoMotion.medium,
                curve: MeditejoMotion.emphasizedDecelerate,
                alignment: Alignment.topCenter,
                onEnd: _revealOpen,
                child: here ?? const SizedBox(width: double.infinity),
              );
            },
          ),
          if (_scope.courseId != null && !pinSwitch) ...[
            const SizedBox(height: 16),
            _scopeCard(s, compact: true),
          ],
          if (!pinSwitch && showBefore != null) ...[
            const SizedBox(height: 16),
            showBefore,
          ],
        ],
      ),
    );

    return WheelSettleScope(
      group: _wheels,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          // A page that gives the sheet its height (the Timer) is filled,
          // with Start at its foot. As a sheet it is as tall as what is open,
          // up to most of the screen, so the folded grid is not a tall
          // empty card.
          final fill = constraints.hasTightHeight;
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
          final listArea = Stack(
            fit: StackFit.passthrough,
            children: [
              list,
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
          final body = Column(
            mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                subtitle: _scopeLine,
                finishes: widget.showFinishes ? _finishes(context, s) : null,
              ),
              if (fill)
                Expanded(child: listArea)
              else
                Flexible(child: listArea),
              if (pinSwitch) ?showBefore,
              ?_startButton,
            ],
          );
          return SafeArea(
            top: false,
            child: fill
                ? SizedBox(height: height, child: body)
                : ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: height),
                    child: body,
                  ),
          );
        },
      ),
    );
  }

  /// Whether this sheet opens before each recorded session. The sheet's own
  /// setting, so not a slot: it sits under the list, by Start. A timer,
  /// whose screen is this sheet, has no use for it.
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

  /// The tile for [slot]: its name, its value at a glance, filled when it
  /// differs from the defaults. Length is shown, not set, where the
  /// recording or the screen owns it.
  Widget _tile(_Slot slot, CueSettings s, CueSettings reference) {
    final l10n = _l10n;
    final scheme = Theme.of(context).colorScheme;
    Widget icon(IconData data) => Icon(data, color: scheme.onSurfaceVariant);
    final (label, leading, value, detail, changed, enabled) = switch (slot) {
      _Slot.sound => (
        l10n.customizeSlotSound,
        _soundArt(s) ?? icon(Icons.graphic_eq_rounded),
        _backgroundValue(s),
        null,
        _soundDiffers(s, reference),
        true,
      ),
      _Slot.bells => (
        l10n.customizeSlotBells,
        icon(Icons.notifications_none_rounded),
        _bellsValue(s),
        _bellsDetail(s),
        _bellsKey(s) != _bellsKey(reference),
        true,
      ),
      _Slot.rhythm => (
        l10n.customizeSlotRhythm,
        icon(Icons.monitor_heart_outlined),
        _pulseName(s),
        s.pulseSound.isEmpty ? null : _pulseRateSpoken(s),
        _pulseKey(s) != _pulseKey(reference),
        true,
      ),
      _Slot.length => (
        l10n.customizeSlotLength,
        icon(Icons.timer_outlined),
        _lengthValue(s),
        _lengthDetail(s),
        _canSetDuration && s.durationMinutes != reference.durationMinutes,
        _canSetDuration,
      ),
    };
    return KeyedSubtree(
      key: _tileKeys[slot],
      child: _SlotTile(
        key: ValueKey('customize_slot_${slot.name}'),
        leading: leading,
        label: label,
        value: value,
        detail: detail,
        detailView: slot == _Slot.rhythm ? _pulseRateView(s) : null,
        changed: changed,
        open: _slot == slot,
        // Sound is the mixer itself, in its drawer (#66), not a section.
        opensDrawer: slot == _Slot.sound,
        state: !enabled
            ? null
            : changed
            ? _l10n.customizeSlotChanged
            : _l10n.customizeSlotDefault,
        onTap: !enabled
            ? null
            : slot == _Slot.sound
            ? _chooseSound
            : () => _toggleSlot(slot),
      ),
    );
  }

  /// The controls behind a tile. Sound has none here: its tile opens the
  /// mixer drawer.
  Widget _section(_Slot slot, CueSettings s) => switch (slot) {
    _Slot.sound => const SizedBox.shrink(),
    _Slot.bells => _bellsSection(s),
    _Slot.rhythm => _Section(children: [_Inset(_pulseEditor(s))]),
    _Slot.length => _Section(children: [_Inset(_durationWheel(s))]),
  };

  /// Each bell with what belongs to it: the countdown before the starting
  /// bell, and the silence after the audio before the ending bell.
  Widget _bellsSection(CueSettings s) => _Section(
    children: [
      _bellRow(
        _Part.startBell,
        s,
        title: 'Starting bell',
        icon: Icons.notifications_active_outlined,
        sound: s.startSound,
        value: _startValue(s),
        apply: (v) => s.copyWith(startSound: v),
        above: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _WheelRow([
            _wheel<int>(
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
        value: _endValue(s),
        apply: (v) => s.copyWith(endSound: v),
        // A timer's length is its own: silence after it is just a longer
        // timer.
        above: widget.isTimer
            ? null
            : Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Caption(
                      'Keep going in silence (with any background sound) '
                      'after the audio ends, then ring the ending bell.',
                    ),
                    _WheelRow([
                      _wheel<int>(
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
                        apply: (v) => s.copyWith(extendMinutes: v),
                      ),
                    ]),
                  ],
                ),
              ),
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

  Widget _durationWheel(CueSettings s) => _WheelRow([
    _wheel<int>(
      label: 'Duration',
      showLabel: false,
      options: [
        for (var m = 1; m <= _maxDurationMinutes; m++)
          WheelOption(m, _minutes(m), semanticsLabel: _spokenMinutes(m)),
      ],
      value: s.durationMinutes.clamp(1, _maxDurationMinutes),
      parse: _range(1, _maxDurationMinutes),
      hint: '1 to $_maxDurationMinutes minutes',
      apply: (v) => s.copyWith(durationMinutes: v),
    ),
  ]);

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
            tooltip: 'Play ${_bellName(sound)}',
            icon: const Icon(Icons.play_arrow_rounded),
            onPressed: () => _audition(sound, s.bellVolume),
          ),
    editor: () => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?above,
        _BellList(
          selected: part == _Part.intervalBell ? s.intervalSound : sound,
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
      child: _WheelRow([
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
                ? cueBellSounds['Swell bell']!
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

  /// Opens the mixer drawer on what plays under these sessions; what is
  /// left in it is kept: for the course when it has its own settings,
  /// otherwise for the kind (the Sounds tab's "Plays under" line shows the
  /// same). During a session it plays at once.
  Future<void> _chooseSound() async {
    _dismissUndo();
    _silence();
    // Taken now: the sheet may be gone by the time the drawer closes.
    final container = ProviderScope.containerOf(context);
    final scope = _scope;
    final courseOverride = _courseOverride;
    final inSession = widget.isActive;
    final choice = await showSoundDrawer(
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

  String _bellName(String path) => cueBellSounds.entries
      .firstWhere(
        (e) => e.value == path,
        orElse: () => cueBellSounds.entries.first,
      )
      .key;

  String _intervalValue(CueSettings s) {
    if (!s.hasIntervalBell) return 'Off';
    final bell = _bellName(s.intervalSound);
    if (s.intervalHalfway) return 'Halfway · $bell';
    final base = 'Every ${s.intervalMinutes} min';
    return s.randomWindowMinutes == 0
        ? '$base · $bell'
        : '$base ± ${s.randomWindowMinutes} · $bell';
  }

  /// The starting bell, after its countdown when there is one.
  String _startValue(CueSettings s) {
    final bell = _bellName(s.startSound);
    return s.countdownSeconds == 0
        ? bell
        : _l10n.customizeCountdownThenBell(s.countdownSeconds, bell);
  }

  /// The ending bell, after its silence when there is one.
  String _endValue(CueSettings s) {
    final bell = _bellName(s.endSound);
    return widget.isTimer || s.extendMinutes == 0
        ? bell
        : _l10n.customizeSilenceThenBell(s.extendMinutes, bell);
  }

  /// The Bells tile: the first bell heard, by name.
  String _bellsValue(CueSettings s) {
    for (final sound in [
      s.startSound,
      if (s.hasIntervalBell) s.intervalSound,
      s.endSound,
    ]) {
      if (sound.isNotEmpty) return _bellName(sound);
    }
    return _l10n.customizeOff;
  }

  /// The Bells tile's second line: when bells ring ("Start · Halfway · End").
  String? _bellsDetail(CueSettings s) {
    final l10n = _l10n;
    final parts = [
      if (s.startSound.isNotEmpty) l10n.customizeBellsAtStart,
      if (s.hasIntervalBell)
        s.intervalHalfway
            ? l10n.customizeBellsHalfway
            : l10n.customizeBellsEvery(s.intervalMinutes),
      if (s.endSound.isNotEmpty) l10n.customizeBellsAtEnd,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// What the Bells slot holds, as a value to compare: the countdown and the
  /// silence belong to their bells. An interval bell that is off is off,
  /// whatever its stored rhythm.
  Object _bellsKey(CueSettings s) => (
    s.startSound,
    s.endSound,
    s.countdownSeconds,
    widget.isTimer ? 0 : s.extendMinutes,
    s.bellVolume,
    !s.hasIntervalBell
        ? null
        : s.intervalHalfway
        ? (s.intervalSound, -1, 0)
        : (s.intervalSound, s.intervalMinutes, s.randomWindowMinutes),
  );

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

  /// The Length tile: the timer's length, or the recording's, which the
  /// sheet shows but does not set.
  String _lengthValue(CueSettings s) {
    final audioMinutes = math.max(1, (widget.audioDurationMs / 60000).round());
    if (_canSetDuration) return _minutes(s.durationMinutes);
    if (widget.isTimer) {
      final minutes = widget.timerMinutes;
      if (minutes == 0) return _l10n.customizeLengthCountsUp;
      if (minutes != null) return _minutes(minutes);
      return widget.audioDurationMs > 0
          ? _minutes(audioMinutes)
          : _minutes(s.durationMinutes);
    }
    return widget.audioDurationMs > 0
        ? _minutes(audioMinutes)
        : _l10n.customizeLengthSetByEachSession;
  }

  String? _lengthDetail(CueSettings s) {
    if (widget.isTimer || widget.audioDurationMs <= 0) return null;
    return s.extendMinutes > 0
        ? _l10n.customizeLengthPlusSilence(s.extendMinutes)
        : _l10n.customizeLengthSetBySession;
  }

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

  /// The Sound tile carries the chosen sound's art, as on the Sounds
  /// screen; null when nothing plays.
  Widget? _soundArt(CueSettings s) {
    final mixer = ref.watch(soundscapeProvider);
    final subject = soundChoiceArt(mixer, _soundscapeChoice(s, mixer));
    if (subject == null) return null;
    return ClipRRect(
      key: const ValueKey('customize_sound_art'),
      borderRadius: BorderRadius.circular(MeditejoShapes.medium),
      child: SizedBox.square(dimension: 40, child: ArtCover(subject: subject)),
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

/// A slot's section: its rows on one tonal 28 dp surface, as on the Settings
/// and You screens. One step up from the sheet (which is
/// surfaceContainerLow), so the card reads on it. Its name is on the open
/// tile above it.
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

/// The slots as a 2×2 grid; each row's tiles share the taller one's height.
/// [below] gives what goes under each row (an open section).
class _SlotGrid extends StatelessWidget {
  const _SlotGrid({required this.tiles, required this.below});

  final List<Widget> tiles;
  final Widget? Function(int row) below;

  @override
  Widget build(BuildContext context) => Column(
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
        ?below(i ~/ 2),
      ],
    ],
  );
}

/// One slot: its name, its value and a second line. Filled when it differs
/// from the defaults, outlined when it does not (the language of the preset
/// picker and the save sheet); a wider primary edge while its section is
/// open. Without [onTap] it only shows its value, dimmed.
class _SlotTile extends StatelessWidget {
  const _SlotTile({
    super.key,
    required this.leading,
    required this.label,
    required this.value,
    this.detail,
    this.detailView,
    required this.changed,
    required this.open,
    this.opensDrawer = false,
    this.state,
    this.onTap,
  });

  final Widget leading;

  /// Opens a drawer over the sheet rather than a section under its row.
  final bool opensDrawer;
  final String label, value;

  /// The second line; [detailView], when given, shows it instead (this
  /// stays what a screen reader says).
  final String? detail;
  final Widget? detailView;

  /// Read after the value: "changed" or "default", what the fill shows.
  final String? state;
  final bool changed, open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final enabled = onTap != null;
    final filled = changed && enabled;
    // A tile that only shows its value is quieter in its colours (not by
    // fading it, which took its text under 3:1 on the light sheet).
    final onColor = filled
        ? scheme.onSecondaryContainer
        : enabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant;
    final detailStyle = type.baseline.bodySmall?.copyWith(
      color: filled ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
    );
    final side = open
        ? BorderSide(color: scheme.primary, width: 2)
        : filled
        ? BorderSide.none
        : BorderSide(color: scheme.outlineVariant);
    final tile = Material(
      color: filled ? scheme.secondaryContainer : Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MeditejoShapes.large),
        side: side,
      ),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 112),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox.square(
                      dimension: 40,
                      child: Center(child: leading),
                    ),
                    const Spacer(),
                    if (enabled && opensDrawer)
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant,
                      )
                    else if (enabled)
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: MediaQuery.of(context).disableAnimations
                            ? Duration.zero
                            : MeditejoMotion.short,
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: type.baseline.labelLarge?.copyWith(
                    color: filled
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: type.emphasized.titleMedium?.copyWith(color: onColor),
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
      button: enabled,
      expanded: enabled && !opensDrawer ? open : null,
      label: [label, value, ?detail, ?state].join(', '),
      excludeSemantics: true,
      onTap: onTap,
      child: tile,
    );
  }
}

/// A section's single control, inset on its card.
class _Inset extends StatelessWidget {
  const _Inset(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(16), child: child);
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
    this.title,
    required this.options,
    required this.value,
    required this.onChanged,
    this.parse,
    this.hint,
    this.visibleItems = 5,
    this.showLabel = true,
    this.enabled = true,
  });

  /// What the wheel sets: for a screen reader, the typing dialog and the
  /// Undo bar.
  final String label;

  /// The word shown above the wheel, when shorter than [label].
  final String? title;
  final bool enabled;

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
          enabled: enabled,
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
  const _WheelRow(this.wheels);

  final List<Widget> wheels;

  /// A wheel's widest, at 1× text (it grows with the text); narrower when
  /// three share a row, to leave the gutters room.
  static const wheelWidth = 120.0;
  static const narrowWheelWidth = 80.0;

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
        final cap = wheels.length >= 3 ? narrowWheelWidth : wheelWidth;
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

/// The bells a cue can ring, each with its icon (the bell's figure,
/// drawn from its sound). Tapping one selects it and rings it once, so what
/// is heard is what a session will play, and its icon is struck with it.
class _BellList extends StatefulWidget {
  const _BellList({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  State<_BellList> createState() => _BellListState();
}

class _BellListState extends State<_BellList> {
  final _strikes = <String, ValueNotifier<int>>{
    for (final asset in cueBellSounds.values)
      if (asset.isNotEmpty) asset: ValueNotifier(0),
  };

  @override
  void dispose() {
    for (final n in _strikes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _pick(String asset) {
    widget.onSelected(asset);
    _strikes[asset]?.value++;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final selected = widget.selected;
    return Material(
      color: scheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      shape: MeditejoShapes.rounded(MeditejoShapes.largeIncreased),
      child: Column(
        children: [
          for (final e in cueBellSounds.entries)
            Semantics(
              button: true,
              selected: e.value == selected,
              label: e.value.isEmpty ? e.key : '${e.key}, plays a preview',
              excludeSemantics: true,
              onTap: () => _pick(e.value),
              child: InkWell(
                onTap: () => _pick(e.value),
                child: Ink(
                  color: e.value == selected ? scheme.secondaryContainer : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 40,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: e.value.isEmpty
                                  ? ColoredBox(
                                      color: scheme.surfaceContainerLow,
                                      child: Icon(
                                        Icons.notifications_off_outlined,
                                        size: 20,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    )
                                  : ArtCover(
                                      key: ValueKey('bell_icon_${e.value}'),
                                      subject: ArtSubject.bell(
                                        e.value,
                                        icon: true,
                                      ),
                                      strike: _strikes[e.value],
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              e.key,
                              style:
                                  (e.value == selected
                                          ? type.emphasized.bodyLarge
                                          : type.baseline.bodyLarge)
                                      ?.copyWith(
                                        color: e.value == selected
                                            ? scheme.onSecondaryContainer
                                            : scheme.onSurface,
                                      ),
                            ),
                          ),
                          if (e.value == selected)
                            Icon(Icons.check_rounded, color: scheme.primary)
                          else if (e.value.isNotEmpty)
                            Icon(
                              Icons.volume_up_rounded,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                        ],
                      ),
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
