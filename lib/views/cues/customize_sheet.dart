import 'package:medito/providers/cues/cue_runtime_provider.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/player/audio_state_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/audio/session_bell_preview.dart';
import 'package:medito/views/soundscape/sounds_panel.dart';

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

/// Cue settings in one place: every row shows its value and opens a small
/// sub-sheet. Edits are saved as the defaults for the scope's kind (or as a
/// per-course override) and picked up by the player through the provider.
class CustomizeSheet extends ConsumerStatefulWidget {
  const CustomizeSheet({
    super.key,
    required this.scope,
    this.isTimer = false,
    this.audioDurationMs = 0,
    this.positionMs = 0,
    this.speed = 1,
    this.onStart,
    this.embedded = false,
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

  /// Rendered inline in a page (no title, no inner scrolling).
  final bool embedded;

  /// The "Finishes at" line; a stopwatch has no end to show.
  final bool showFinishes;

  /// A timer length chosen elsewhere (the wheels); the sheet's own Duration
  /// row is hidden when this is set.
  final int? timerMinutes;
  final DateTime Function() clock;

  @override
  ConsumerState<CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends ConsumerState<CustomizeSheet> {
  Timer? _tick;
  late bool _courseOverride;

  CueScope get _scope => widget.scope;

  @override
  void initState() {
    super.initState();
    _courseOverride = ref.read(cueSettingsStoreProvider).hasOverride(_scope);
    _tick = Timer.periodic(
      const Duration(seconds: 30),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _edit(CueSettings value) => unawaited(
    ref
        .read(cueSettingsProvider(_scope).notifier)
        .update(value, courseOverride: _courseOverride),
  );

  /// Opens a sub-sheet whose body rebuilds with the live settings.
  Future<void> _open(
    String title,
    Widget Function(CueSettings s, void Function(CueSettings) change) body,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final s = ref.watch(cueSettingsProvider(_scope));
          return _SubSheet(title: title, child: body(s, _edit));
        },
      ),
    );
    // A bell auditioned in a picker never rings on after its sheet closes.
    if (mounted) unawaited(ref.read(sessionBellPreviewProvider).stop());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = ref.watch(cueSettingsProvider(_scope));
    final isTimer = widget.isTimer;
    final canSetDuration =
        isTimer && widget.timerMinutes == null && widget.onStart != null;
    final practice = _scope.kind == CueKind.practice;
    final media = MediaQuery.of(context);

    final rows = <Widget>[
      if (widget.showFinishes) _finishes(context, s),
      if (canSetDuration)
        _CueRow(
          title: 'Duration',
          value: '${s.durationMinutes} min',
          onTap: () => _open(
            'Duration',
            (s, change) => _SliderTile(
              label: 'Minutes',
              value: s.durationMinutes.toDouble().clamp(1, 299),
              min: 1,
              max: 299,
              divisions: 298,
              format: (v) => '${v.round()} min',
              onChanged: (v) => change(s.copyWith(durationMinutes: v.round())),
            ),
          ),
        )
      else if (!isTimer)
        _CueRow(
          title: 'Extend',
          value: s.extendMinutes == 0 ? 'Off' : '+${s.extendMinutes} min',
          onTap: () => _open(
            'Extend with silence',
            (s, change) => Column(
              children: [
                const _Caption(
                  'Keep going in silence (with any background sound) after the audio ends, then ring the ending bell.',
                ),
                _SliderTile(
                  label: 'Extra minutes',
                  value: s.extendMinutes.toDouble(),
                  min: 0,
                  max: 60,
                  divisions: 60,
                  format: (v) => v.round() == 0 ? 'Off' : '+${v.round()} min',
                  onChanged: (v) =>
                      change(s.copyWith(extendMinutes: v.round())),
                ),
              ],
            ),
          ),
        ),
      _CueRow(
        title: 'Countdown',
        value: s.countdownSeconds == 0 ? 'Off' : '${s.countdownSeconds} sec',
        onTap: () => _open(
          'Countdown',
          (s, change) => _ChoiceWrap<int>(
            options: const {0: 'Off', 5: '5 sec', 10: '10 sec'},
            selected: s.countdownSeconds,
            onSelected: (v) => change(s.copyWith(countdownSeconds: v)),
          ),
        ),
      ),
      _CueRow(
        title: 'Starting bell',
        value: _bellName(s.startSound),
        onTap: () => _open(
          'Starting bell',
          (s, change) => _bellBody(
            s,
            change,
            s.startSound,
            (v) => s.copyWith(startSound: v),
          ),
        ),
      ),
      _CueRow(
        title: 'Interval bell',
        value: _intervalValue(s),
        onTap: () => _open(
          'Interval bell',
          (s, change) => Column(
            children: [
              _SliderTile(
                label: 'Every',
                value: s.intervalMinutes.toDouble(),
                min: 0,
                max: 60,
                divisions: 60,
                format: (v) => v.round() == 0 ? 'Off' : '${v.round()} min',
                // A shorter interval pulls the random window in with it, so
                // the saved value never exceeds what the slider can show.
                onChanged: (v) => change(
                  s.copyWith(
                    intervalMinutes: v.round(),
                    randomWindowMinutes: s.randomWindowMinutes.clamp(
                      0,
                      v.round(),
                    ),
                  ),
                ),
              ),
              if (s.intervalMinutes > 0)
                _SliderTile(
                  label: 'Random window ±',
                  value: s.randomWindowMinutes.toDouble().clamp(
                    0,
                    s.intervalMinutes.toDouble(),
                  ),
                  min: 0,
                  max: s.intervalMinutes.toDouble().clamp(1, 60),
                  divisions: s.intervalMinutes.clamp(1, 60),
                  format: (v) =>
                      v.round() == 0 ? 'Exact' : '± ${v.round()} min',
                  onChanged: (v) =>
                      change(s.copyWith(randomWindowMinutes: v.round())),
                ),
              const SizedBox(height: 8),
              _BellList(
                selected: s.intervalSound,
                volume: s.bellVolume,
                onSelected: (v) => change(s.copyWith(intervalSound: v)),
              ),
              _volume(s, change),
            ],
          ),
        ),
      ),
      _CueRow(
        title: 'Pulse',
        value: _pulseValue(s),
        onTap: () => _open(
          'Pulse',
          (s, change) => Column(
            children: [
              _ChoiceWrap<String>(
                options: {
                  for (final e in cuePulseSounds.entries) e.value: e.key,
                },
                selected: s.pulseSound,
                onSelected: (v) => change(s.copyWith(pulseSound: v)),
              ),
              if (s.pulseSound.isNotEmpty) ...[
                _SliderTile(
                  label: 'Rate',
                  value: s.pulseBpm,
                  min: 20,
                  max: 120,
                  divisions: 100,
                  format: (v) => '${v.round()} BPM',
                  onChanged: (v) =>
                      change(s.copyWith(pulseBpm: v.roundToDouble())),
                ),
                _SliderTile(
                  label: 'Slow down over',
                  value: s.pulseRampMinutes.toDouble(),
                  min: 0,
                  max: 60,
                  divisions: 60,
                  format: (v) => v.round() == 0 ? 'Off' : '${v.round()} min',
                  onChanged: (v) =>
                      change(s.copyWith(pulseRampMinutes: v.round())),
                ),
                if (s.pulseRampMinutes > 0)
                  _SliderTile(
                    label: 'Ends at',
                    value: s.pulseEndBpm,
                    min: 20,
                    max: 120,
                    divisions: 100,
                    format: (v) => '${v.round()} BPM',
                    onChanged: (v) =>
                        change(s.copyWith(pulseEndBpm: v.roundToDouble())),
                  ),
                _SliderTile(
                  label: 'Volume',
                  value: s.pulseVolume,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  format: (v) => '${(v * 100).round()}%',
                  onChanged: (v) => change(s.copyWith(pulseVolume: v)),
                ),
              ],
            ],
          ),
        ),
      ),
      _CueRow(
        title: 'Ending bell',
        value: _bellName(s.endSound),
        onTap: () => _open(
          'Ending bell',
          (s, change) =>
              _bellBody(s, change, s.endSound, (v) => s.copyWith(endSound: v)),
        ),
      ),
      _CueRow(
        title: 'Background sound',
        value: _backgroundValue(s),
        onTap: () => _open('Background sound', _backgroundBody),
      ),
      if (!isTimer)
        _CueRow(
          title: 'Autoplay',
          value: !s.autoplay
              ? 'Off'
              : s.interludeSeconds == 0
              ? 'On'
              : 'On · ${s.interludeSeconds} sec pause',
          onTap: () => _open(
            'Autoplay',
            (s, change) => Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Play the next session automatically'),
                  value: s.autoplay,
                  onChanged: (v) => change(s.copyWith(autoplay: v)),
                ),
                if (s.autoplay) ...[
                  const _Caption('Interlude before the next session'),
                  _ChoiceWrap<int>(
                    options: const {
                      0: 'None',
                      5: '5 sec',
                      10: '10 sec',
                      30: '30 sec',
                    },
                    selected: s.interludeSeconds,
                    onSelected: (v) => change(s.copyWith(interludeSeconds: v)),
                  ),
                ],
              ],
            ),
          ),
        ),
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: const Text('Hide these settings before practice'),
        value: s.hideBeforePractice,
        onChanged: (v) => _edit(s.copyWith(hideBeforePractice: v)),
      ),
      if (_scope.courseId != null)
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text('Use these only for this course'),
          subtitle: Text(
            _courseOverride
                ? 'Changes apply to this course'
                : 'Changes apply to all ${practice ? 'practice' : 'talks'}',
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
    ];

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );

    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: list,
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Customize',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: list,
              ),
            ),
            if (widget.onStart != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: widget.onStart,
                    child: const Text('Start'),
                  ),
                ),
              ),
          ],
        ),
      ),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        'Finishes at $time',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _volume(CueSettings s, void Function(CueSettings) change) =>
      _SliderTile(
        label: 'Bell volume',
        value: s.bellVolume,
        min: 0,
        max: 1,
        divisions: 20,
        format: (v) => '${(v * 100).round()}%',
        onChanged: (v) => change(s.copyWith(bellVolume: v)),
      );

  Widget _bellBody(
    CueSettings s,
    void Function(CueSettings) change,
    String selected,
    CueSettings Function(String) apply,
  ) => Column(
    children: [
      _BellList(
        selected: selected,
        volume: s.bellVolume,
        onSelected: (v) => change(apply(v)),
      ),
      _volume(s, change),
    ],
  );

  SoundscapeSessionKind get _soundscapeKind => _scope.kind == CueKind.practice
      ? SoundscapeSessionKind.practice
      : SoundscapeSessionKind.talks;

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
  /// the volume), so the Sounds sheet's switches show the same thing.
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

  Widget _backgroundBody(CueSettings s, void Function(CueSettings) change) {
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
            _Caption(
              _scope.kind == CueKind.practice
                  ? 'On by default for practice'
                  : 'Off by default for talks',
            ),
            _ChoiceWrap<String>(
              options: {
                SoundscapeSelection.none.encode(): 'Off',
                SoundscapeSelection.currentMix.encode(): 'Current mix',
              },
              selected: selected,
              onSelected: pick,
            ),
            _SectionLabel(l10n?.soundsPresets ?? 'Presets'),
            _ChoiceWrap<String>(
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
              _SectionLabel(
                l10n == null
                    ? category.name
                    : soundCategoryLabel(l10n, category),
              ),
              _ChoiceWrap<String>(
                options: {
                  for (final e in library.inCategory(category))
                    SoundscapeSelection.sound(e.id).encode(): e.title,
                },
                selected: selected,
                onSelected: pick,
              ),
            ],
            if (selected != SoundscapeSelection.none.encode())
              _SliderTile(
                label: 'Volume',
                value: mixer.sessionDefault(_soundscapeKind).volume * 100,
                min: 0,
                max: 100,
                divisions: 20,
                format: (v) => '${v.round()}%',
                onChanged: (v) => ref
                    .read(soundscapeProvider.notifier)
                    .setSessionVolume(_soundscapeKind, v / 100),
              ),
          ],
        );
      },
    );
  }

  String _bellName(String path) => cueBellSounds.entries
      .firstWhere(
        (e) => e.value == path,
        orElse: () => cueBellSounds.entries.first,
      )
      .key;

  String _intervalValue(CueSettings s) {
    if (s.intervalMinutes == 0 || s.intervalSound.isEmpty) return 'Off';
    final base = 'Every ${s.intervalMinutes} min';
    return s.randomWindowMinutes == 0
        ? base
        : '$base ± ${s.randomWindowMinutes}';
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

class _SubSheet extends StatelessWidget {
  const _SubSheet({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _CueRow extends StatelessWidget {
  const _CueRow({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$title, $value',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.brandAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          height: 1.4,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// The bells a cue can ring. Tapping one selects it and rings it once at the
/// bell [volume], so what is heard is what a session will play.
class _BellList extends ConsumerWidget {
  const _BellList({
    required this.selected,
    required this.volume,
    required this.onSelected,
  });

  final String selected;
  final double volume;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    void pick(String asset) {
      onSelected(asset);
      final preview = ref.read(sessionBellPreviewProvider);
      unawaited(
        asset.isEmpty ? preview.stop() : preview.play(volume, asset: asset),
      );
    }

    return Column(
      children: [
        for (final e in cueBellSounds.entries)
          Semantics(
            button: true,
            selected: e.value == selected,
            label: e.value.isEmpty ? e.key : '${e.key}, plays a preview',
            excludeSemantics: true,
            onTap: () => pick(e.value),
            child: InkWell(
              onTap: () => pick(e.value),
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        e.value == selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: e.value == selected
                            ? context.brandAccent
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          e.key,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: e.value == selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (e.value.isNotEmpty)
                        Icon(
                          Icons.volume_up_rounded,
                          size: 20,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChoiceWrap<T> extends StatelessWidget {
  const _ChoiceWrap({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
              selectedColor: context.brandAccent,
              labelStyle: TextStyle(
                color: e.key == selected
                    ? context.onBrandAccent
                    : Theme.of(context).colorScheme.onSurface,
              ),
              showCheckmark: false,
            ),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value, min, max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                format(value),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.brandAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: context.brandAccent,
              inactiveTrackColor: onSurface.withValues(alpha: 0.15),
              thumbColor: context.brandAccent,
              overlayColor: context.brandAccent.withValues(alpha: 0.12),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: format(value),
              semanticFormatterCallback: format,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
