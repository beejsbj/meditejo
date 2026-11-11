import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/hermes_amara/hermes_amara_flag.dart';
import 'package:medito/services/hermes_amara/hermes_amara_source.dart';

import 'package:medito/services/library/library_store.dart';

import '../../helpers/library_fixtures.dart';

/// Hermes Amāra's site states no licence and permission is still pending, so
/// the adapter must be off in every build we ship (DECISIONS.md, 2026-10-27).
void main() {
  test('the flag is off unless a build asks for it', () {
    expect(hermesAmaraEnabled, isFalse);
  });

  test('with the flag off the source is not registered', () {
    final container = ProviderContainer(
      overrides: [
        libraryStoreProvider.overrideWithValue(LibraryStore(memoryLibraryDb())),
      ],
    );
    addTearDown(container.dispose);
    final prefixes = [
      for (final s in container.read(contentSourcesProvider)) s.prefix,
    ];
    expect(prefixes, isNot(contains('ha-')));
    expect(prefixes, containsAll(['ds-', 'dt-']));
  });

  test('a disabled adapter fetches nothing and lists nothing', () async {
    var fetches = 0;
    final source = HermesAmaraSource(
      enabled: false,
      fetchListing: () async {
        fetches++;
        return '';
      },
    );
    await source.catchUp(force: true);
    expect((await source.explore()).isEmpty, isTrue);
    expect((await source.search('metta')).isEmpty, isTrue);
    expect(fetches, 0);
  });

  test('no workflow or release script turns the flag on', () {
    final files = [
      ...Directory('.github/workflows').listSync().whereType<File>(),
      ...Directory(
        'tools/meditejo',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.sh')),
      File('build_apk.sh'),
      File('build_android.sh'),
      File('build_all.sh'),
      File('build_ios.sh'),
      File('prepare_release.sh'),
    ].where((f) => f.existsSync());
    for (final file in files) {
      expect(
        file.readAsStringSync(),
        isNot(contains('MEDITEJO_HERMES_AMARA')),
        reason: '${file.path} must not enable Hermes Amāra',
      );
    }
  });
}
