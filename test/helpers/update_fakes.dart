import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/updates/update_providers.dart';
import 'package:medito/providers/updates/update_state.dart';
import 'package:medito/services/updates/apk_installer.dart';
import 'package:medito/services/updates/github_release_client.dart';
import 'package:medito/services/updates/update_downloader.dart';
import 'package:medito/services/updates/update_failure.dart';
import 'package:medito/services/updates/update_release.dart';
import 'package:shared_preferences/shared_preferences.dart';

final apkSha = 'a' * 64;

UpdateRelease testRelease({
  int code = 26101702,
  String name = '0.1.1',
  String notes = '- Calmer timer\n- Fixes',
}) => UpdateRelease(
  tag: 'v$name',
  versionName: name,
  versionCode: code,
  apkName: 'meditejo-$name.apk',
  apkUrl: '${kReleaseDownloadPrefix}v$name/meditejo-$name.apk',
  size: 1000,
  sha256: apkSha,
  notes: notes,
  publishedAt: DateTime.utc(2026, 10, 17),
);

/// Answers `latest()` from a script; counts calls and records the ETag asked.
class FakeReleaseClient implements GithubReleaseClient {
  FakeReleaseClient(this.answer);

  Object Function() answer;
  int calls = 0;
  final etags = <String?>[];

  @override
  Future<LatestRelease> latest({String? etag}) async {
    calls++;
    etags.add(etag);
    final result = answer();
    if (result is UpdateException) throw result;
    return result as LatestRelease;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDownloader implements UpdateDownloader {
  FakeDownloader(this.dir);

  final Directory dir;
  UpdateException? failWith;

  /// When set, a download pauses at 50% until the gate completes.
  Completer<void>? gate;
  int downloads = 0;
  int staleSweeps = 0;
  final deleted = <int>[];

  @override
  Future<File> download(
    UpdateRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    downloads++;
    final failure = failWith;
    if (failure != null) throw failure;
    onProgress?.call(0.5);
    await gate?.future;
    onProgress?.call(1);
    // No disk I/O: widget tests run in fake async, where real I/O never ends.
    return File('${dir.path}/meditejo-${release.versionCode}.apk');
  }

  @override
  Future<void> delete(UpdateRelease release) async =>
      deleted.add(release.versionCode);

  @override
  Future<void> deleteStale({required int installedVersionCode}) async =>
      staleSweeps++;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInstaller implements ApkInstaller {
  bool canInstall = true;
  bool signatureOk = true;
  bool packageOk = true;
  int? inspectedVersionCode;
  InstallOutcome outcome = const InstallSucceeded();
  int settingsOpened = 0;
  int installs = 0;

  @override
  Future<bool> canInstallPackages() async => canInstall;

  @override
  Future<void> openInstallPermissionSettings() async => settingsOpened++;

  @override
  Future<ApkInspection> inspect(String path) async => ApkInspection(
    packageMatches: packageOk,
    signatureMatchesPin: signatureOk,
    versionCode: inspectedVersionCode ?? 26101702,
  );

  @override
  Future<InstallOutcome> install(String path) async {
    installs++;
    return outcome;
  }
}

class UpdateHarness {
  UpdateHarness._({
    required this.prefs,
    required this.client,
    required this.downloader,
    required this.installer,
    required this.overrides,
    required this.clock,
  });

  final SharedPreferences prefs;
  final FakeReleaseClient client;
  final FakeDownloader downloader;
  final FakeInstaller installer;
  final List<Override> overrides;
  final DateTime Function() clock;

  static Future<UpdateHarness> create({
    Map<String, Object> prefs = const {},
    int installedCode = 26101701,
    String installedName = '0.1.0-dev',
    bool supported = true,
    Object Function()? latest,
    DateTime Function()? clock,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final preferences = await SharedPreferences.getInstance();
    final client = FakeReleaseClient(latest ?? () => const LatestNone());
    final dir = Directory.systemTemp.createTempSync('update_test');
    final downloader = FakeDownloader(dir);
    final installer = FakeInstaller();
    final now = clock ?? () => DateTime.utc(2026, 10, 17, 12);
    return UpdateHarness._(
      prefs: preferences,
      client: client,
      downloader: downloader,
      installer: installer,
      clock: now,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        updatesSupportedProvider.overrideWithValue(supported),
        updateClockProvider.overrideWithValue(now),
        githubReleaseClientProvider.overrideWithValue(client),
        updateDownloaderProvider.overrideWithValue(downloader),
        apkInstallerProvider.overrideWithValue(installer),
        installedBuildProvider.overrideWith(
          (ref) async => InstalledBuild(
            versionName: installedName,
            versionCode: installedCode,
          ),
        ),
      ],
    );
  }

  ProviderContainer container() {
    final c = ProviderContainer(overrides: overrides);
    return c;
  }
}
