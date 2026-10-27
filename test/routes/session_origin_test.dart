import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/routes/routes.dart';

import '../helpers/memory_session_store.dart';

/// Where a session is opened from is written by the router: a course surface
/// names its course, every other surface forgets the last one.
void main() {
  late MemorySessionStore store;

  setUp(() => store = MemorySessionStore());

  Future<void> open(
    WidgetTester tester, {
    String? courseId,
    String trackId = 'x-1',
  }) async {
    late BuildContext context;
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Consumer(
            builder: (c, r, _) {
              context = c;
              ref = r;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await handleNavigation(
      TypeConstants.track,
      [trackId, '/tracks/$trackId'],
      context,
      ref: ref,
      courseId: courseId,
    );
    await tester.pump();
  }

  testWidgets('a course surface writes the course it opened from', (
    tester,
  ) async {
    await open(tester, courseId: 'my-course-a');
    expect(store.contexts, {'x-1': 'my-course-a'});
  });

  testWidgets('a surface with no course forgets the last one', (tester) async {
    store.contexts['x-1'] = 'my-course-a';
    store.contexts['x-2'] = 'my-course-a';

    await open(tester); // search, a library row, a teacher page, a link

    expect(store.contexts, {'x-2': 'my-course-a'});
  });

  testWidgets('the legacy timer is not a library session', (tester) async {
    store.contexts['x-1'] = 'my-course-a';
    await open(tester, trackId: kLegacyTimerTrackId);
    expect(store.contexts, {'x-1': 'my-course-a'});
  });
}
