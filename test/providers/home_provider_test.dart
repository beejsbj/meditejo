import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/home/home_model.dart';
import 'package:medito/providers/home/home_provider.dart';
import 'package:medito/providers/locale_provider.dart';
import 'package:medito/repositories/home/home_repository.dart';

class _FakeHomeRepository implements HomeRepositoryImpl {
  _FakeHomeRepository(this.home);
  final HomeModel home;
  int calls = 0;

  @override
  Future<HomeModel> fetchHome() async {
    calls++;
    return home;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'an empty local catalogue stays empty for Spanish device locales',
    () async {
      final container = ProviderContainer(
        overrides: [
          deviceLocalesProvider.overrideWithValue(const [Locale('es', 'MX')]),
        ],
      );
      addTearDown(container.dispose);
      final home = await container.read(fetchHomeProvider.future);
      expect(home.carousel, isEmpty);
      expect(home.shortcuts, isEmpty);
      expect(home.todayQuote, isNull);
    },
  );

  test(
    'returns source content unchanged and refreshes it on request',
    () async {
      const home = HomeModel(
        carousel: [
          HomeCarouselModel(
            id: 'lib-course',
            title: 'My course',
            subtitle: '',
            coverUrl: '',
            path: 'packs/lib-course',
            type: 'pack',
          ),
        ],
      );
      final repository = _FakeHomeRepository(home);
      final container = ProviderContainer(
        overrides: [homeRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      expect(await container.read(fetchHomeProvider.future), home);
      await container.read(refreshHomeAPIsProvider.future);
      expect(await container.read(fetchHomeProvider.future), home);
      expect(repository.calls, 2);
    },
  );
}
