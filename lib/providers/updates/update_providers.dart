import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/updates/update_state.dart';
import 'package:medito/services/updates/apk_installer.dart';
import 'package:medito/services/updates/github_release_client.dart';
import 'package:medito/services/updates/update_check_policy.dart';
import 'package:medito/services/updates/update_downloader.dart';
import 'package:medito/services/updates/update_failure.dart';
import 'package:medito/services/updates/update_release.dart';
import 'package:medito/services/updates/update_store.dart';
import 'package:medito/utils/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const _tag = 'UPDATES';

/// The updater is Android only; iOS hides its UI and never checks.
final updatesSupportedProvider = Provider<bool>((_) => Platform.isAndroid);

final updateClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final githubReleaseClientProvider = Provider<GithubReleaseClient>((ref) {
  final client = GithubReleaseClient();
  ref.onDispose(client.close);
  return client;
});

final updateDownloaderProvider = Provider<UpdateDownloader>((ref) {
  final downloader = UpdateDownloader(
    directory: () async {
      final support = await getApplicationSupportDirectory();
      return Directory('${support.path}/updates');
    },
  );
  ref.onDispose(downloader.close);
  return downloader;
});

final apkInstallerProvider = Provider<ApkInstaller>(
  (_) => MethodChannelApkInstaller(),
);

final updateStoreProvider = Provider<UpdateStore>(
  (ref) => UpdateStore(ref.watch(sharedPreferencesProvider)),
);

final installedBuildProvider = FutureProvider<InstalledBuild>((_) async {
  final info = await PackageInfo.fromPlatform();
  return InstalledBuild(
    versionName: info.version,
    versionCode: parseBuildNumber(info.buildNumber),
  );
});

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

/// Checks for, downloads, verifies and installs a newer Meditejo build.
class UpdateController extends Notifier<UpdateState> {
  UpdateStore get _store => ref.read(updateStoreProvider);
  bool _failedDuringUpdate = false;
  DateTime _now() => ref.read(updateClockProvider)();

  @override
  UpdateState build() {
    final store = ref.read(updateStoreProvider);
    if (ref.read(updatesSupportedProvider)) unawaited(_restore());
    return UpdateState(
      lastCheckedAt: store.lastCheckedAt,
      dismissedVersionCode: store.dismissedVersionCode,
    );
  }

  /// Shows what was learned last time, before (or without) asking again.
  Future<void> _restore() async {
    try {
      final installed = await ref.read(installedBuildProvider.future);
      if (!ref.mounted || state.phase != UpdatePhase.idle) return;
      final cached = _store.release;
      if (cached != null && cached.isNewerThan(installed.versionCode)) {
        state = state.copyWith(phase: UpdatePhase.available, release: cached);
      } else if (state.lastCheckedAt != null) {
        state = state.copyWith(phase: UpdatePhase.upToDate);
      }
    } catch (e, st) {
      AppLogger.e(_tag, 'Could not restore update state', e, st);
    }
  }

  /// Runs shortly after launch: removes leftovers of an earlier update, then
  /// checks if a day has passed. Failures are silent; the About page is where
  /// an error is worth showing.
  Future<void> checkOnLaunch() async {
    if (!ref.read(updatesSupportedProvider)) return;
    try {
      final installed = await ref.read(installedBuildProvider.future);
      await ref
          .read(updateDownloaderProvider)
          .deleteStale(installedVersionCode: installed.versionCode);
      await _restore();
      if (isAutoCheckDue(lastCheckedAt: _store.lastCheckedAt, now: _now())) {
        await check(manual: false);
      }
    } catch (e, st) {
      AppLogger.e(_tag, 'Launch check did not run', e, st);
    }
  }

  /// Asks GitHub for the latest release. [manual] checks show their errors.
  Future<void> check({bool manual = true}) async {
    if (!ref.read(updatesSupportedProvider) || state.isBusy) return;
    final before = state;
    _failedDuringUpdate = false;
    if (manual) {
      state = state.copyWith(phase: UpdatePhase.checking, clearFailure: true);
    }
    try {
      final installed = await ref.read(installedBuildProvider.future);
      final latest = await ref
          .read(githubReleaseClientProvider)
          .latest(etag: _store.etag);
      if (!ref.mounted) return;
      UpdateRelease? release;
      switch (latest) {
        case LatestUnchanged():
          release = _store.release;
        case LatestNone():
          await _store.clearRelease();
        case LatestFound(release: final found, :final etag):
          await _store.saveRelease(found, etag);
          release = found;
      }
      final checkedAt = _now();
      await _store.setLastCheckedAt(checkedAt);
      if (!ref.mounted) return;
      final newer = release != null && release.isNewerThan(installed.versionCode);
      state = UpdateState(
        phase: newer ? UpdatePhase.available : UpdatePhase.upToDate,
        release: newer ? release : null,
        lastCheckedAt: checkedAt,
        dismissedVersionCode: state.dismissedVersionCode,
      );
    } on UpdateException catch (e) {
      AppLogger.w(_tag, 'Check failed: $e');
      if (!ref.mounted) return;
      state = manual
          ? state.copyWith(
              phase: UpdatePhase.failed,
              failure: e.failure,
              failureDetail: e.detail,
            )
          : before;
    } catch (e, st) {
      AppLogger.e(_tag, 'Check failed', e, st);
      if (!ref.mounted) return;
      state = manual
          ? state.copyWith(
              phase: UpdatePhase.failed,
              failure: UpdateFailure.unavailable,
            )
          : before;
    }
  }

  /// Download, verify, and hand the APK to Android.
  Future<void> startUpdate() async {
    final release = state.release;
    if (release == null || state.isBusy) return;
    final installer = ref.read(apkInstallerProvider);
    final downloader = ref.read(updateDownloaderProvider);
    _failedDuringUpdate = true;

    try {
      if (!await installer.canInstallPackages()) {
        // Explained once; after that the settings page opens straight away.
        final explain = !_store.permissionExplained;
        state = state.copyWith(
          phase: UpdatePhase.needsPermission,
          explainPermission: explain,
          clearFailure: true,
        );
        if (!explain) await openPermissionSettings();
        return;
      }

      state = state.copyWith(
        phase: UpdatePhase.downloading,
        progress: 0,
        clearFailure: true,
      );
      final file = await downloader.download(
        release,
        onProgress: (p) {
          if (ref.mounted) state = state.copyWith(progress: p);
        },
      );

      // The hash was checked as it was saved; Android checks who signed it.
      state = state.copyWith(phase: UpdatePhase.verifying);
      final inspection = await installer.inspect(file.path);
      if (!inspection.signatureMatchesPin) {
        await downloader.delete(release);
        throw const UpdateException(UpdateFailure.signatureMismatch);
      }
      if (!inspection.packageMatches ||
          inspection.versionCode != release.versionCode) {
        await downloader.delete(release);
        throw const UpdateException(UpdateFailure.notMeditejo);
      }

      state = state.copyWith(phase: UpdatePhase.installing);
      final outcome = await installer.install(file.path);
      if (!ref.mounted) return;
      switch (outcome) {
        case InstallSucceeded():
          await downloader.delete(release);
          state = state.copyWith(phase: UpdatePhase.upToDate, clearRelease: true);
        case InstallCancelled():
          // Closing the prompt is a choice, not an error.
          state = state.copyWith(phase: UpdatePhase.available);
        case InstallRejected(:final message):
          throw UpdateException(UpdateFailure.installFailed, message);
      }
    } on UpdateException catch (e) {
      AppLogger.w(_tag, 'Update failed: $e');
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: UpdatePhase.failed,
        failure: e.failure,
        failureDetail: e.detail,
      );
    } catch (e, st) {
      AppLogger.e(_tag, 'Update failed', e, st);
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: UpdatePhase.failed,
        failure: UpdateFailure.installFailed,
        failureDetail: '$e',
      );
    }
  }

  /// Sends the person to "Install unknown apps" for Meditejo.
  Future<void> openPermissionSettings() async {
    await _store.markPermissionExplained();
    await ref.read(apkInstallerProvider).openInstallPermissionSettings();
  }

  /// Coming back from Android's settings: carry on if the switch is on.
  Future<void> onAppResumed() async {
    if (state.phase != UpdatePhase.needsPermission) return;
    if (await ref.read(apkInstallerProvider).canInstallPackages()) {
      state = state.copyWith(phase: UpdatePhase.available);
      await startUpdate();
    }
  }

  /// Try again after a failure: the update if that is what failed, else the
  /// check.
  Future<void> retry() async {
    if (_failedDuringUpdate && state.release != null) {
      state = state.copyWith(phase: UpdatePhase.available, clearFailure: true);
      await startUpdate();
    } else {
      await check();
    }
  }

  /// Hides Home's line for this version. About still shows the update.
  Future<void> dismissHomeNotice() async {
    final code = state.release?.versionCode;
    if (code == null) return;
    await _store.dismissNotice(code);
    state = state.copyWith(dismissedVersionCode: code);
  }
}

/// Called once from the app shell after launch. Waits a little so it never
/// competes with startup or the first Dharma Seed requests.
Future<void> startUpdateCheck(
  WidgetRef ref, {
  Duration delay = const Duration(seconds: 10),
}) async {
  if (!ref.read(updatesSupportedProvider)) return;
  await Future<void>.delayed(delay);
  await ref.read(updateControllerProvider.notifier).checkOnLaunch();
}
