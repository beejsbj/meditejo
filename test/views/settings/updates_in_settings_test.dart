import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/providers/updates/update_providers.dart';
import 'package:medito/services/updates/apk_installer.dart';
import 'package:medito/services/updates/github_release_client.dart';
import 'package:medito/services/updates/update_failure.dart';
import 'package:medito/views/home/widgets/update_notice.dart';
import 'package:medito/views/you/you_view.dart';

import '../../helpers/update_fakes.dart';

Widget _app(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

Future<ProviderContainer> _pump(
  WidgetTester tester,
  UpdateHarness h, {
  Widget home = const YouView(),
}) async {
  final container = h.container();
  addTearDown(container.dispose);
  // Tall enough that the whole You page is built, About at the bottom.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 4000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(container, home));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('Check for updates, in Settings › About', () {
    testWidgets('shows the installed version and a way to check', (
      tester,
    ) async {
      final h = await UpdateHarness.create();
      await _pump(tester, h);

      expect(find.text('Version 0.1.0-dev (26101701)'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Check for updates'),
        findsOneWidget,
      );
      expect(find.text('Check for updates'), findsOneWidget);
      expect(find.text('Up to date'), findsNothing);
      expect(find.text('Update'), findsNothing);
    });

    testWidgets('"Check for updates" says "Up to date" when nothing is newer', (
      tester,
    ) async {
      final h = await UpdateHarness.create(latest: () => const LatestNone());
      await _pump(tester, h);

      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Check for updates'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Up to date'), findsOneWidget);
      expect(find.textContaining('Last checked'), findsOneWidget);
      expect(h.client.calls, 1);
    });

    testWidgets('the check that found an update is the last checked time', (
      tester,
    ) async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), null),
      );
      await _pump(tester, h);
      expect(find.textContaining('Last checked'), findsNothing);

      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Check for updates'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update available: 0.1.1'), findsOneWidget);
      expect(find.textContaining('Last checked'), findsOneWidget);
      expect(find.textContaining('Oct 17, 2026'), findsOneWidget);
    });

    testWidgets('a newer release shows its version, Update and the notes', (
      tester,
    ) async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(notes: '- Calmer timer'), null),
      );
      await _pump(tester, h);

      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Check for updates'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update available: 0.1.1'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
      expect(find.text("What's new"), findsOneWidget);
      expect(find.text('Calmer timer'), findsOneWidget);
    });

    testWidgets('shows the download progress, then hands over to Android', (
      tester,
    ) async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), null),
      );
      h.downloader.gate = Completer<void>();
      final container = await _pump(tester, h);
      await container.read(updateControllerProvider.notifier).check();
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Downloading… 50%'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.5);

      h.downloader.gate!.complete();
      await tester.pumpAndSettle();
      expect(h.installer.installs, 1);
    });

    testWidgets(
      'explains "Install unknown apps" once and opens Android settings',
      (tester) async {
        final h = await UpdateHarness.create(
          latest: () => LatestFound(testRelease(), null),
        );
        h.installer.canInstall = false;
        final container = await _pump(tester, h);
        await container.read(updateControllerProvider.notifier).check();
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Update'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Install unknown apps'), findsOneWidget);
        expect(h.installer.settingsOpened, 0);

        await tester.tap(find.widgetWithText(FilledButton, 'Open settings'));
        await tester.pumpAndSettle();
        expect(h.installer.settingsOpened, 1);
      },
    );

    for (final (failure, text) in [
      (UpdateFailure.offline, 'Couldn’t reach GitHub'),
      (UpdateFailure.rateLimited, 'GitHub is asking for a pause'),
    ]) {
      testWidgets('a check that fails with $failure says so plainly', (
        tester,
      ) async {
        final h = await UpdateHarness.create(
          latest: () => UpdateException(failure),
        );
        await _pump(tester, h);

        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Check for updates'),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining(text), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
      });
    }

    for (final (failure, text) in [
      (UpdateFailure.hashMismatch, 'doesn’t match what was published'),
      (UpdateFailure.signatureMismatch, 'wasn’t signed with Meditejo’s key'),
    ]) {
      testWidgets(
        'a refused download ($failure) is explained and not installed',
        (tester) async {
          final h = await UpdateHarness.create(
            latest: () => LatestFound(testRelease(), null),
          );
          h.downloader.failWith = UpdateException(failure);
          if (failure == UpdateFailure.signatureMismatch) {
            h.downloader.failWith = null;
            h.installer.signatureOk = false;
          }
          final container = await _pump(tester, h);
          await container.read(updateControllerProvider.notifier).check();
          await tester.pumpAndSettle();

          await tester.tap(find.widgetWithText(FilledButton, 'Update'));
          await tester.pumpAndSettle();

          expect(find.textContaining(text), findsOneWidget);
          expect(h.installer.installs, 0);
        },
      );
    }

    testWidgets(
      'closing Android\'s prompt returns to "Update available" without an error',
      (tester) async {
        final h = await UpdateHarness.create(
          latest: () => LatestFound(testRelease(), null),
        );
        h.installer.outcome = const InstallCancelled();
        final container = await _pump(tester, h);
        await container.read(updateControllerProvider.notifier).check();
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Update'));
        await tester.pumpAndSettle();

        expect(find.text('Update available: 0.1.1'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
        expect(find.text('Try again'), findsNothing);
      },
    );

    testWidgets('has no update controls where updates are unsupported (iOS)', (
      tester,
    ) async {
      final h = await UpdateHarness.create(supported: false);
      await _pump(tester, h);

      expect(find.text('Check for updates'), findsNothing);
      expect(find.text('Up to date'), findsNothing);
      expect(find.textContaining('Version '), findsOneWidget);
    });
  });

  group('Home notice', () {
    testWidgets('is absent until an update is known', (tester) async {
      final h = await UpdateHarness.create();
      await _pump(tester, h, home: const Scaffold(body: UpdateNotice()));
      expect(find.textContaining('is available'), findsNothing);
    });

    testWidgets('is one line with View and a dismiss that sticks', (
      tester,
    ) async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), null),
      );
      final container = await _pump(
        tester,
        h,
        home: const Scaffold(body: UpdateNotice()),
      );
      await container.read(updateControllerProvider.notifier).check();
      await tester.pumpAndSettle();

      expect(find.text('Meditejo 0.1.1 is available'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.textContaining('is available'), findsNothing);
    });

    testWidgets('View opens You, with the update on offer', (
      tester,
    ) async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), null),
      );
      final container = await _pump(
        tester,
        h,
        home: const Scaffold(body: UpdateNotice()),
      );
      await container.read(updateControllerProvider.notifier).check();
      await tester.pumpAndSettle();

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(container.read(mainTabProvider), MainTab.you);
    });

    testWidgets('About leads Settings while an update is waiting', (
      tester,
    ) async {
      final h = await UpdateHarness.create(
        latest: () => LatestFound(testRelease(), null),
      );
      final container = await _pump(tester, h);
      double top(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
      // Nothing known yet: About is last.
      expect(top('settings_about'), greaterThan(top('settings_reminders')));

      await container.read(updateControllerProvider.notifier).check();
      await tester.pumpAndSettle();

      expect(find.text('Update available: 0.1.1'), findsOneWidget);
      expect(top('settings_about'), lessThan(top('settings_practice')));
    });

    testWidgets('is hidden on iOS', (tester) async {
      final h = await UpdateHarness.create(supported: false);
      await _pump(tester, h, home: const Scaffold(body: UpdateNotice()));
      expect(find.byType(Row), findsNothing);
    });
  });
}
