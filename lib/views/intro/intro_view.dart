import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/intro/first_run_intro.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "What Meditejo is": one quiet page, never a questionnaire.
///
/// On a fresh install it is the first thing shown, over Home: Start (or
/// Back) closes it onto Home, and leaving it in any way marks it seen, so it
/// never comes back on its own. Settings › About opens it again, with a back
/// arrow instead of Start.
///
/// The guided tour (#87, after #61/#63) is not built yet. When it is, pass
/// [onTakeTour] and a "Take the tour" button appears beside Start; until
/// then there is no button that does nothing.
class IntroView extends ConsumerStatefulWidget {
  const IntroView({super.key, this.firstRun = false, this.onTakeTour});

  /// Shown at first launch: Start closes it onto Home and marks it seen.
  /// Otherwise it was opened from About and has a back arrow.
  final bool firstRun;

  /// Starts the guided tour. Null hides the button.
  final VoidCallback? onTakeTour;

  static const routeName = 'IntroView';

  /// The first-launch route: no slide in, since it is the first screen.
  static Route<void> firstRunRoute({VoidCallback? onTakeTour}) =>
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: routeName),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) =>
            IntroView(firstRun: true, onTakeTour: onTakeTour),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  @override
  ConsumerState<IntroView> createState() => _IntroViewState();
}

class _IntroViewState extends ConsumerState<IntroView> {
  late final SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _prefs = ref.read(sharedPreferencesProvider);
  }

  @override
  void dispose() {
    // However the intro is left (Start, Back, or a link that closes it), it
    // has been seen.
    if (widget.firstRun) FirstRunIntro.markSeen(_prefs).ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final body = type.baseline.bodyLarge?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: ExcludeSemantics(
            child: MeditejoMark(mark: ref.watch(homeMarkProvider), size: 128),
          ),
        ),
        const SizedBox(height: 32),
        Semantics(
          header: true,
          child: Text('Meditejo', style: type.emphasized.displaySmall),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.introLead,
          key: const ValueKey('intro_lead'),
          style: type.baseline.titleLarge,
        ),
        const SizedBox(height: 24),
        for (final line in [
          l10n.introPractice,
          l10n.introSources,
          l10n.introPrivate,
        ]) ...[Text(line, style: body), const SizedBox(height: 12)],
        const SizedBox(height: 12),
        Text(
          l10n.introMeaning,
          style: type.baseline.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: widget.firstRun
          ? null
          : AppBar(
              key: const ValueKey('intro_app_bar'),
              title: Text(l10n.aboutWhatIsMeditejo),
            ),
      body: SafeArea(
        top: widget.firstRun,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: content,
                  ),
                ),
              ),
            ),
            if (widget.firstRun)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.onTakeTour case final tour?) ...[
                        OutlinedButton(
                          key: const ValueKey('intro_tour'),
                          onPressed: tour,
                          child: Text(l10n.introTour),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                        key: const ValueKey('intro_start'),
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: Text(l10n.introStart),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
