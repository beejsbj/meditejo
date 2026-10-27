import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/providers/background_sounds/background_sounds_notifier.dart';
import 'package:medito/providers/soundscape/sound_pack_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';

import 'sound_cards.dart';
import 'sound_credits_view.dart';
import 'sound_labels.dart';
import 'sound_mix_panel.dart';
import 'sound_pack_widgets.dart';

/// Opens the Sounds screen as a page of its own, over whatever is open (the
/// player, its Customize sheet), so a session stays where it was. Home opens
/// the Sounds tab instead.
Future<void> openSoundsPage(BuildContext context) {
  retryLegacySounds(ProviderScope.containerOf(context));
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const SoundsView(standalone: true),
    ),
  );
}

/// A failed fetch of the legacy background sounds is kept (keepAlive); retry
/// it whenever Sounds opens, so coming back online brings them back.
void retryLegacySounds(ProviderContainer container) {
  if (container.read(backgroundSoundsProvider).hasError) {
    container.invalidate(backgroundSoundsProvider);
  }
}

/// Windows at least this wide show the mix beside the library rather than
/// docked under it.
const kSoundsTwoPaneWidth = 840.0;

/// The Sounds tab: presets to start in one tap, the library shelf by shelf
/// as cards, whether the mix plays under sessions, and the credits. The
/// current mix is docked at the foot (a bar with play/pause that opens into
/// a panel) or, on a wide window, a panel beside the library.
///
/// Bells are not here: the cue scheduler owns them, set in Customize.
class SoundsView extends ConsumerStatefulWidget {
  const SoundsView({super.key, this.standalone = false});

  /// Pushed as a page of its own (from the player or Customize): it closes
  /// with a button, and back folds an open mix first.
  final bool standalone;

  @override
  ConsumerState<SoundsView> createState() => SoundsViewState();
}

class SoundsViewState extends ConsumerState<SoundsView>
    with SingleTickerProviderStateMixin {
  /// 0 docked, 1 open. Unbounded: the spring may overshoot a little.
  late final AnimationController _dock = AnimationController.unbounded(
    vsync: this,
  );
  bool _open = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context)!;
    ref
        .read(soundscapeProvider.notifier)
        .setNotificationText(
          SoundscapeNotificationText(
            title: l10n.backgroundSoundsSection,
            text: l10n.soundsNotificationText,
            stop: l10n.soundsStop,
          ),
        );
  }

  @override
  void dispose() {
    _dock.dispose();
    super.dispose();
  }

  /// Folds an open mix panel. True when there was one to fold, so Android's
  /// back is spent on it.
  bool collapseMix() {
    if (!_open) return false;
    _settle(false);
    return true;
  }

  void _toggle() {
    // An empty mix stays docked: there is nothing in it to adjust.
    if (!_open && ref.read(soundscapeProvider).mix.isEmpty) return;
    _settle(!_open);
  }

  void _settle(bool open, {double velocity = 0}) {
    if (_open != open) setState(() => _open = open);
    final target = open ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _dock.value = target;
      return;
    }
    _dock
        .animateWith(
          SpringSimulation(
            MeditejoMotion.expressiveSpatial.spring,
            _dock.value,
            target,
            velocity,
          ),
        )
        // The spring settles within a hair of its target; land on it, so a
        // folded dock's scrim stops taking touches.
        .whenComplete(() {
          if (mounted && !_dock.isAnimating) _dock.value = target;
        });
  }

  void _drag(DragUpdateDetails details, double travel) {
    if (!_open && ref.read(soundscapeProvider).mix.isEmpty) return;
    _dock.value = (_dock.value - details.primaryDelta! / travel).clamp(0, 1);
  }

  void _release(DragEndDetails details, double travel) {
    if (!_open && ref.read(soundscapeProvider).mix.isEmpty) return;
    final velocity = -(details.primaryVelocity ?? 0) / travel;
    final open = velocity.abs() > 1.5 ? velocity > 0 : _dock.value > 0.5;
    _settle(open, velocity: velocity);
  }

  /// The docked bar's height: its handle, the header (whose text grows with
  /// the user's text size) and the safe area beneath.
  double _barHeight(BuildContext context) =>
      20 +
      math.max(56, MediaQuery.textScalerOf(context).scale(44)) +
      16 +
      MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final page = Scaffold(
      appBar: AppBar(
        title: Text(l10n.backgroundSoundsSection),
        actions: [
          IconButton(
            key: const ValueKey('sound_credits'),
            tooltip: l10n.soundsCredits,
            onPressed: () => _openCredits(context),
            icon: const Icon(Symbols.info_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= kSoundsTwoPaneWidth
            ? _twoPane(context)
            : _docked(context, box),
      ),
    );
    if (!widget.standalone) return page;
    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) collapseMix();
      },
      child: page,
    );
  }

  Widget _twoPane(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _SoundsLibrary(bottomPadding: bottom + 24)),
        SizedBox(
          width: 400,
          child: Padding(
            padding: EdgeInsets.fromLTRB(0, 8, 16, bottom + 16),
            child: Material(
              color: scheme.surfaceContainer,
              shape: MeditejoShapes.rounded(MeditejoShapes.extraLarge),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: SoundsMixHeader(),
                  ),
                  Expanded(
                    child: SoundsMixBody(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _docked(BuildContext context, BoxConstraints box) {
    final scheme = Theme.of(context).colorScheme;
    final bar = _barHeight(context);
    final full = math.max(bar, box.maxHeight - 32);
    final travel = math.max(1.0, full - bar);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        Positioned.fill(child: _SoundsLibrary(bottomPadding: bar + 24)),
        // A scrim over the library while the mix is open; tap it to fold.
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _dock,
            builder: (context, _) {
              final t = _dock.value.clamp(0.0, 1.0);
              return IgnorePointer(
                ignoring: !_open || t < 0.01,
                child: GestureDetector(
                  onTap: () => _settle(false),
                  child: ColoredBox(
                    color: scheme.scrim.withValues(alpha: 0.32 * t),
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedBuilder(
            animation: _dock,
            builder: (context, child) {
              final t = _dock.value;
              return SizedBox(
                height: lerpDouble(bar, full, t)!.clamp(bar, box.maxHeight),
                child: child,
              );
            },
            child: Material(
              key: const ValueKey('sounds_dock'),
              color: scheme.surfaceContainerHigh,
              elevation: 3,
              shadowColor: scheme.shadow.withValues(alpha: 0.4),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(MeditejoShapes.extraLarge),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    onVerticalDragUpdate: (d) => _drag(d, travel),
                    onVerticalDragEnd: (d) => _release(d, travel),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                      child: Column(
                        children: [
                          const _DragHandle(),
                          SizedBox(
                            height: bar - 20 - 16 - bottom,
                            child: SoundsMixHeader(
                              expanded: _open,
                              onToggle: _toggle,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _dock,
                      builder: (context, child) {
                        final t = _dock.value.clamp(0.0, 1.0);
                        if (t < 0.01) return const SizedBox.shrink();
                        return Opacity(
                          opacity: Curves.easeOut.transform(
                            ((t - 0.2) / 0.8).clamp(0.0, 1.0),
                          ),
                          child: child,
                        );
                      },
                      child: SoundsMixBody(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openCredits(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SoundCreditsView()));
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 20,
    child: Center(
      child: Container(
        width: 32,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}

/// Presets, then the library shelf by shelf, then sessions and credits.
class _SoundsLibrary extends ConsumerWidget {
  const _SoundsLibrary({required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final library = ref.watch(soundLibraryProvider).value;
    final state = ref.watch(soundscapeProvider);
    final pack = ref.watch(soundPackProvider);
    final mixer = ref.read(soundscapeProvider.notifier);
    final full = !mixer.canAddLayer;
    final grid = SoundGridMetrics.of(context);

    Widget card(String id, String title) {
      final layer = state.mix.layers.where((l) => l.soundId == id).firstOrNull;
      final inMix = layer != null;
      // A sound of the pack that is not on the phone: its card offers the
      // download instead of the mix.
      final offer = SoundOffer.of(library?[id], pack);
      return SoundCard(
        key: ValueKey('sound_$id'),
        soundId: id,
        title: title,
        params: layer?.params ?? defaultSynthParams(id),
        selected: inMix,
        sounding: inMix && offer == null && state.playing && layer.volume > 0,
        enabled: inMix || !full,
        offer: offer,
        onTap: offer == null
            ? () => mixer.toggleSound(id)
            : () => offer.act(ref),
      );
    }

    List<Widget> shelf(
      String key,
      String title,
      IconData icon,
      List<Widget> cards,
    ) => [
      SliverToBoxAdapter(
        child: _ShelfTitle(key: ValueKey('shelf_$key'), title, icon: icon),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        // Square tiles, as many across as fit at up to [maxCardWidth]
        // each: three on a phone, fewer once large text needs the room,
        // and never shorter than the title needs.
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.crossAxisExtent;
            final columns = math.max(
              1,
              ((width + kSoundGridGap) / (grid.maxCardWidth + kSoundGridGap))
                  .ceil(),
            );
            final cell = (width - kSoundGridGap * (columns - 1)) / columns;
            return SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: math.max(cell, grid.cardHeight),
                mainAxisSpacing: kSoundGridGap,
                crossAxisSpacing: kSoundGridGap,
              ),
              delegate: SliverChildListDelegate(cards),
            );
          },
        ),
      ),
    ];

    return CustomScrollView(
      key: const PageStorageKey('sounds_library'),
      slivers: [
        SliverToBoxAdapter(child: _SectionTitle(l10n.soundsPresets)),
        const SliverToBoxAdapter(child: _PresetRow()),
        const SliverToBoxAdapter(child: SoundPackBanner()),
        if (full)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(
                l10n.soundsLayerLimit(SoundMix.kMaxLayers),
                style: context.typography.baseline.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        if (library == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else ...[
          ...shelf(
            'generated',
            l10n.soundCategoryGenerated,
            SoundLook.forCategory(null).icon,
            [for (final id in kSynthIds) card(id, synthTitle(l10n, id))],
          ),
          for (final category in library.categories)
            ...shelf(
              category.name,
              soundCategoryLabel(l10n, category),
              SoundLook.forCategory(category).icon,
              [
                for (final sound in library.inCategory(category))
                  card(sound.id, sound.title),
              ],
            ),
        ],
        SliverToBoxAdapter(child: _SectionTitle(l10n.soundsUnderSessions)),
        const SliverToBoxAdapter(child: SoundsSessionDefaults()),
        const SliverToBoxAdapter(child: _CreditsLink()),
        SliverPadding(padding: EdgeInsets.only(bottom: bottomPadding)),
      ],
    );
  }
}

/// The presets as a row of large cards, the user's after the built-in
/// ones, with Save mix at the end while the mix is not one of them.
class _PresetRow extends ConsumerWidget {
  const _PresetRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(soundscapeProvider);
    final library = ref.watch(soundLibraryProvider).value ?? SoundLibrary.empty;
    final mixer = ref.read(soundscapeProvider.notifier);
    final pack = ref.watch(soundPackProvider);
    final current = state.matchingPreset;
    final size = presetCardSize(context);
    final canSave = !state.mix.isEmpty && current == null;
    List<String> titles(SoundPreset preset) {
      final layers = [...preset.mix.layers]
        ..sort((a, b) => b.volume.compareTo(a.volume));
      return [
        for (final layer in layers) ?soundTitle(l10n, layer.soundId, library),
      ];
    }

    final cards = <Widget>[
      for (final preset in state.presets)
        PresetCard(
          key: ValueKey('preset_${preset.id}'),
          presetId: preset.id,
          label: soundPresetLabel(l10n, preset),
          layers: preset.mix.layers,
          layerTitles: titles(preset),
          builtIn: preset.builtIn,
          missing: [
            for (final layer in preset.mix.layers)
              if (SoundOffer.of(library[layer.soundId], pack) != null)
                layer.soundId,
          ].length,
          playing: state.playing && current?.id == preset.id,
          onTap: () => mixer.applyPreset(preset.id),
          onDelete: preset.builtIn
              ? null
              : () => confirmDeletePreset(context, ref, preset),
        ),
      if (canSave)
        Padding(
          padding: const EdgeInsets.only(bottom: kPresetStackDepth),
          child: SavePresetCard(
            key: const ValueKey('preset_save'),
            onTap: () => saveMixAsPreset(context, ref),
          ),
        ),
    ];
    return SizedBox(
      height: size.height + kPresetStackDepth,
      child: ListView.separated(
        key: const PageStorageKey('sounds_presets'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(
          // Save mix is a square beside the wide prints.
          width: i < state.presets.length ? size.width : size.height,
          child: cards[i],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 16, 12),
      child: Text(title, style: context.typography.emphasized.titleLarge),
    ),
  );
}

class _ShelfTitle extends StatelessWidget {
  const _ShelfTitle(this.title, {super.key, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 16, 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: context.typography.emphasized.titleMedium,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Whether the mix plays under Practice and under Talks (decisions 8 and
/// 17). The player's Customize sheet offers the full per-kind choice.
class SoundsSessionDefaults extends ConsumerWidget {
  const SoundsSessionDefaults({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(soundscapeProvider);
    final controller = ref.read(soundscapeProvider.notifier);
    Widget row(SoundscapeSessionKind kind, String label) {
      final value = state.sessionDefault(kind);
      return SwitchListTile(
        key: ValueKey('under_${kind.name}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(label),
        value: value.enabled,
        onChanged: (on) =>
            controller.setSessionDefault(kind, value.copyWith(enabled: on)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: MeditejoShapes.rounded(MeditejoShapes.extraLarge),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row(SoundscapeSessionKind.practice, l10n.soundsUnderPractice),
              row(SoundscapeSessionKind.talks, l10n.soundsUnderTalks),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  l10n.soundsUnderSessionsHint,
                  style: context.typography.baseline.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditsLink extends StatelessWidget {
  const _CreditsLink();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
    child: ListTile(
      key: const ValueKey('sound_credits_footer'),
      shape: MeditejoShapes.rounded(MeditejoShapes.large),
      leading: const Icon(Symbols.info_rounded),
      title: Text(AppLocalizations.of(context)!.soundsCredits),
      trailing: const Icon(Symbols.chevron_right_rounded),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const SoundCreditsView())),
    ),
  );
}
