import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/updates/update_providers.dart';
import 'package:medito/providers/updates/update_state.dart';
import 'package:medito/services/updates/update_failure.dart';

/// "Up to date" or "Update available", with the controls for each state. Shows
/// nothing where in-app updates are not supported (iOS).
class UpdateSection extends ConsumerStatefulWidget {
  const UpdateSection({super.key});

  @override
  ConsumerState<UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends ConsumerState<UpdateSection>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(updateControllerProvider.notifier).onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(updatesSupportedProvider)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final release = state.release;

    final children = <Widget>[];

    switch (state.phase) {
      case UpdatePhase.idle:
      case UpdatePhase.upToDate:
        children.add(
          _Headline(
            state.phase == UpdatePhase.upToDate
                ? l10n.updateUpToDate
                : l10n.updateCheck,
          ),
        );
        final last = state.lastCheckedAt;
        if (last != null) {
          final when = DateFormat.yMMMd(
            Localizations.localeOf(context).toLanguageTag(),
          ).add_jm().format(last.toLocal());
          children.add(_Caption(l10n.updateLastChecked(when)));
        }
        children.add(_checkButton(l10n, controller));
      case UpdatePhase.checking:
        children
          ..add(_Headline(l10n.updateChecking))
          ..add(const _Progress());
      case UpdatePhase.available:
      case UpdatePhase.needsPermission:
      case UpdatePhase.failed:
        if (release != null) {
          children.add(_Headline(l10n.updateAvailable(release.versionName)));
        } else {
          children.add(_Headline(l10n.updateCheck));
        }
        if (state.phase == UpdatePhase.needsPermission) {
          children
            ..add(
              _Caption(
                state.explainPermission
                    ? l10n.updatePermissionExplanation
                    : l10n.updatePermissionWaiting,
              ),
            )
            ..add(
              _button(
                label: l10n.updateOpenSettings,
                onPressed: controller.openPermissionSettings,
              ),
            );
        } else if (state.phase == UpdatePhase.failed) {
          children
            ..add(_Caption(_errorText(l10n, state.failure), isError: true))
            ..add(
              _button(
                label: l10n.updateTryAgain,
                onPressed: controller.retry,
              ),
            );
        } else {
          children.add(
            _button(label: l10n.updateAction, onPressed: controller.startUpdate),
          );
        }
      case UpdatePhase.downloading:
        children
          ..add(_Headline(l10n.updateDownloading((state.progress * 100).round())))
          ..add(_Progress(value: state.progress));
      case UpdatePhase.verifying:
        children
          ..add(_Headline(l10n.updateVerifying))
          ..add(const _Progress());
      case UpdatePhase.installing:
        children
          ..add(_Headline(l10n.updateInstalling))
          ..add(const _Progress());
    }

    final notes = release?.notes ?? '';
    if (release != null && notes.isNotEmpty && state.phase != UpdatePhase.idle) {
      children
        ..add(const SizedBox(height: padding16))
        ..add(
          Text(
            l10n.updateWhatsNew,
            style: theme.textTheme.titleSmall,
          ),
        )
        ..add(const SizedBox(height: padding8))
        ..add(
          MarkdownBody(
            data: notes,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyMedium,
            ),
          ),
        );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: padding16,
        vertical: padding12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _checkButton(AppLocalizations l10n, UpdateController controller) =>
      _button(label: l10n.updateCheck, onPressed: controller.check, quiet: true);

  Widget _button({
    required String label,
    required Future<void> Function() onPressed,
    bool quiet = false,
  }) {
    final style = quiet
        ? OutlinedButton.styleFrom(minimumSize: const Size(0, 44))
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: padding12),
      child: quiet
          ? OutlinedButton(
              style: style,
              onPressed: () => onPressed(),
              child: Text(label),
            )
          : FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => onPressed(),
              child: Text(label),
            ),
    );
  }

  String _errorText(AppLocalizations l10n, UpdateFailure? failure) =>
      switch (failure) {
        UpdateFailure.offline => l10n.updateErrorOffline,
        UpdateFailure.rateLimited => l10n.updateErrorRateLimited,
        UpdateFailure.unavailable || null => l10n.updateErrorUnavailable,
        UpdateFailure.downloadFailed => l10n.updateErrorDownload,
        UpdateFailure.hashMismatch => l10n.updateErrorHash,
        UpdateFailure.signatureMismatch => l10n.updateErrorSignature,
        UpdateFailure.notMeditejo => l10n.updateErrorNotMeditejo,
        UpdateFailure.installFailed => l10n.updateErrorInstall,
      };
}

class _Headline extends StatelessWidget {
  const _Headline(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleMedium);
}

class _Caption extends StatelessWidget {
  const _Caption(this.text, {this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(
            alpha: isError ? 0.9 : 0.65,
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({this.value});

  final double? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: padding12),
    child: LinearProgressIndicator(value: value),
  );
}
