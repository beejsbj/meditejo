import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/updates/update_providers.dart';
import 'package:medito/providers/updates/update_state.dart';
import 'package:medito/services/updates/apk_installer.dart';
import 'package:medito/services/updates/github_release_client.dart';
import 'package:medito/services/updates/update_failure.dart';
import 'package:medito/services/updates/update_store.dart';

import '../../helpers/update_fakes.dart';

void main() {
  group('checking', () {
    test('a newer release becomes "available" and is remembered with its ETag', () async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), 'W/"1"'),
      );
      final c = h.container();
      addTearDown(c.dispose);

      await c.read(updateControllerProvider.notifier).check();

      final state = c.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.available);
      expect(state.release?.versionName, '0.1.1');
      expect(state.lastCheckedAt, h.clock());
      final store = UpdateStore(h.prefs);
      expect(store.etag, 'W/"1"');
      expect(store.release?.versionCode, 26101702);
    });

    test('the installed build or a lower release is "up to date"', () async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(code: 26101701), null),
      );
      final c = h.container();
      addTearDown(c.dispose);

      await c.read(updateControllerProvider.notifier).check();

      final state = c.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.upToDate);
      expect(state.release, isNull);
    });

    test('a 304 reuses the stored release and sends its ETag', () async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), 'W/"1"'),
      );
      final c = h.container();
      addTearDown(c.dispose);
      final controller = c.read(updateControllerProvider.notifier);
      await controller.check();

      h.client.answer = () => const LatestUnchanged();
      await controller.check();

      expect(h.client.etags, [null, 'W/"1"']);
      expect(c.read(updateControllerProvider).phase, UpdatePhase.available);
      expect(c.read(updateControllerProvider).release?.versionCode, 26101702);
    });

    test('no release at all is "up to date" and clears the cache', () async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), 'W/"1"'),
      );
      final c = h.container();
      addTearDown(c.dispose);
      final controller = c.read(updateControllerProvider.notifier);
      await controller.check();
      h.client.answer = () => const LatestNone();

      await controller.check();

      expect(c.read(updateControllerProvider).phase, UpdatePhase.upToDate);
      expect(UpdateStore(h.prefs).release, isNull);
    });

    test('a manual check that fails says why; the cached release stays', () async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), 'W/"1"'),
      );
      final c = h.container();
      addTearDown(c.dispose);
      final controller = c.read(updateControllerProvider.notifier);
      await controller.check();
      h.client.answer = () => const UpdateException(UpdateFailure.offline);

      await controller.check();

      final state = c.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.failed);
      expect(state.failure, UpdateFailure.offline);
      expect(state.release, isNotNull);
    });

    test('a failed launch check stays silent', () async {
      final h = await UpdateHarness.create(
        latest: () => const UpdateException(UpdateFailure.rateLimited),
      );
      final c = h.container();
      addTearDown(c.dispose);

      await c.read(updateControllerProvider.notifier).check(manual: false);

      expect(c.read(updateControllerProvider).phase, UpdatePhase.idle);
      expect(c.read(updateControllerProvider).failure, isNull);
      expect(UpdateStore(h.prefs).lastCheckedAt, isNull);
    });

    test('nothing happens where updates are unsupported (iOS)', () async {
      final h = await UpdateHarness.create(supported: false);
      final c = h.container();
      addTearDown(c.dispose);

      final controller = c.read(updateControllerProvider.notifier);
      await controller.check();
      await controller.checkOnLaunch();

      expect(h.client.calls, 0);
      expect(h.downloader.staleSweeps, 0);
      expect(c.read(updateControllerProvider).phase, UpdatePhase.idle);
    });
  });

  group('launch check', () {
    test('asks GitHub on the first launch and sweeps old downloads', () async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), null),
      );
      final c = h.container();
      addTearDown(c.dispose);

      await c.read(updateControllerProvider.notifier).checkOnLaunch();

      expect(h.client.calls, 1);
      expect(h.downloader.staleSweeps, 1);
      expect(c.read(updateControllerProvider).phase, UpdatePhase.available);
    });

    test('does not ask again within a day, but still shows the cached release', () async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), 'W/"1"'),
      );
      final first = h.container();
      await first.read(updateControllerProvider.notifier).checkOnLaunch();
      first.dispose();
      expect(h.client.calls, 1);

      final second = h.container();
      addTearDown(second.dispose);
      await second.read(updateControllerProvider.notifier).checkOnLaunch();

      expect(h.client.calls, 1);
      expect(second.read(updateControllerProvider).phase, UpdatePhase.available);
      expect(second.read(updateControllerProvider).release?.versionName, '0.1.1');
    });

    test('asks again once a day has passed', () async {
      var now = DateTime.utc(2026, 10, 17, 12);
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), null),
        clock: () => now,
      );
      final first = h.container();
      await first.read(updateControllerProvider.notifier).checkOnLaunch();
      first.dispose();

      now = now.add(const Duration(hours: 25));
      final second = h.container();
      addTearDown(second.dispose);
      await second.read(updateControllerProvider.notifier).checkOnLaunch();

      expect(h.client.calls, 2);
    });
  });

  group('installing', () {
    Future<UpdateHarness> available() => UpdateHarness.create(
      latest: () => LatestFound(testRelease(), null),
    );

    test('downloads, checks the signature and hands the file over', () async {
      final h = await available();
      final c = h.container();
      addTearDown(c.dispose);
      final controller = c.read(updateControllerProvider.notifier);
      await controller.check();

      await controller.startUpdate();

      expect(h.downloader.downloads, 1);
      expect(h.installer.installs, 1);
      expect(h.downloader.deleted, [26101702]); // removed after success
      expect(c.read(updateControllerProvider).phase, UpdatePhase.upToDate);
    });

    test('a signature that is not the pinned one is refused and the file removed', () async {
      final h = await available();
      h.installer.signatureOk = false;
      final c = h.container();
      addTearDown(c.dispose);
      final controller = c.read(updateControllerProvider.notifier);
      await controller.check();

      await controller.startUpdate();

      final state = c.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.failed);
      expect(state.failure, UpdateFailure.signatureMismatch);
      expect(h.installer.installs, 0);
      expect(h.downloader.deleted, [26101702]);
    });

    test('a file that is not Meditejo, or not the announced version, is refused', () async {
      for (final mutate in <void Function(FakeInstaller)>[
        (i) => i.packageOk = false,
        (i) => i.inspectedVersionCode = 26101799,
      ]) {
        final h = await available();
        mutate(h.installer);
        final c = h.container();
        addTearDown(c.dispose);
        final controller = c.read(updateControllerProvider.notifier);
        await controller.check();

        await controller.startUpdate();

        expect(c.read(updateControllerProvider).failure, UpdateFailure.notMeditejo);
        expect(h.installer.installs, 0);
      }
    });

    test('a hash mismatch from the downloader is reported and nothing installs', () async {
      final h = await available();
      h.downloader.failWith = const UpdateException(UpdateFailure.hashMismatch);
      final c = h.container();
      addTearDown(c.dispose);
      final controller = c.read(updateControllerProvider.notifier);
      await controller.check();

      await controller.startUpdate();

      expect(c.read(updateControllerProvider).failure, UpdateFailure.hashMismatch);
      expect(h.installer.installs, 0);
    });

    test('retry after a failed download tries the update again, not the check', () async {
      final h = await available();
      h.downloader.failWith = const UpdateException(UpdateFailure.downloadFailed);
      final c = h.container();
      addTearDown(c.dispose);
      final controller = c.read(updateControllerProvider.notifier);
      await controller.check();
      await controller.startUpdate();
      h.downloader.failWith = null;

      await controller.retry();

      expect(h.client.calls, 1);
      expect(h.installer.installs, 1);
    });

    test('closing the Android prompt is not an error and keeps the update on offer', () async {
      final h = await available();
      h.installer.outcome = const InstallCancelled();
      final c = h.container();
      addTearDown(c.dispose);
      final controller = c.read(updateControllerProvider.notifier);
      await controller.check();

      await controller.startUpdate();

      final state = c.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.available);
      expect(state.failure, isNull);
      expect(h.downloader.deleted, isEmpty);
    });

    test('an install that never reports back returns to "available"', () async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), null),
        installTimeout: const Duration(milliseconds: 50),
      );
      h.installer.hangInstall = true;
      final c = h.container();
      addTearDown(c.dispose);
      final controller = c.read(updateControllerProvider.notifier);
      await controller.check();

      await controller.startUpdate();

      final state = c.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.available);
      expect(state.isBusy, isFalse);
      expect(state.failure, isNull);
    });

    test('an install Android rejects is reported', () async {
      final h = await available();
      h.installer.outcome = const InstallRejected('INSTALL_FAILED_UPDATE_INCOMPATIBLE');
      final c = h.container();
      addTearDown(c.dispose);
      final controller = c.read(updateControllerProvider.notifier);
      await controller.check();

      await controller.startUpdate();

      final state = c.read(updateControllerProvider);
      expect(state.failure, UpdateFailure.installFailed);
      expect(state.failureDetail, contains('INCOMPATIBLE'));
    });
  });

  group('install permission', () {
    test('is explained once, then resumes by itself when the switch is on', () async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), null),
      );
      h.installer.canInstall = false;
      final c = h.container();
      addTearDown(c.dispose);
      final controller = c.read(updateControllerProvider.notifier);
      await controller.check();

      await controller.startUpdate();
      var state = c.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.needsPermission);
      expect(state.explainPermission, isTrue);
      expect(h.installer.settingsOpened, 0);
      expect(h.downloader.downloads, 0);

      await controller.openPermissionSettings();
      expect(h.installer.settingsOpened, 1);

      // Back from Android's settings with the switch still off: keep waiting.
      await controller.onAppResumed();
      expect(c.read(updateControllerProvider).phase, UpdatePhase.needsPermission);

      h.installer.canInstall = true;
      await controller.onAppResumed();
      expect(h.installer.installs, 1);
      expect(c.read(updateControllerProvider).phase, UpdatePhase.upToDate);
    });

    test('the second time it opens settings straight away', () async {
      final h = await UpdateHarness.create(
        prefs: {'update_permission_explained': true},
        latest: () => LatestFound(testRelease(), null),
      );
      h.installer.canInstall = false;
      final c = h.container();
      addTearDown(c.dispose);
      final controller = c.read(updateControllerProvider.notifier);
      await controller.check();

      await controller.startUpdate();

      expect(c.read(updateControllerProvider).explainPermission, isFalse);
      expect(h.installer.settingsOpened, 1);
    });
  });

  group('Home notice', () {
    test('is shown once per version and stays dismissed after a relaunch', () async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), null),
      );
      final c = h.container();
      final controller = c.read(updateControllerProvider.notifier);
      await controller.check();
      expect(c.read(updateControllerProvider).showHomeNotice, isTrue);

      await controller.dismissHomeNotice();
      expect(c.read(updateControllerProvider).showHomeNotice, isFalse);
      expect(c.read(updateControllerProvider).phase, UpdatePhase.available);
      c.dispose();

      final relaunched = h.container();
      addTearDown(relaunched.dispose);
      await relaunched.read(updateControllerProvider.notifier).check();
      expect(relaunched.read(updateControllerProvider).showHomeNotice, isFalse);

      // A newer version speaks up again.
      h.client.answer = () => LatestFound(testRelease(code: 26101803, name: '0.1.2'), null);
      await relaunched.read(updateControllerProvider.notifier).check();
      expect(relaunched.read(updateControllerProvider).showHomeNotice, isTrue);
    });
  });
}
