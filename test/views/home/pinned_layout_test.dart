import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/views/home/widgets/pinned/pinned_section.dart';
import 'package:medito/widgets/cards/card_actions.dart';

import '../../helpers/library_app.dart';

final _pack = PackModel(
  id: 'lib-course-a',
  title: 'Practising the Jhānas',
  items: [
    for (var i = 0; i < 32; i++)
      PackItemsModel(
        type: 'track',
        id: 'a-$i',
        title: 'Session $i',
        path: '/tracks/a-$i',
        isCompleted: false,
      ),
  ],
);

class _FakePack extends Pack {
  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(_pack);
}

void main() {
  // #92: "0 of 32" was reported clipped by the pin control. A long real title,
  // 32 sessions, at the narrowest phone width and at large text.
  for (final width in [411.0, 360.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('the progress count is whole at ${width.round()} dp, '
          '${scale}x text', (tester) async {
        final app = await LibraryTestApp.create(tester);
        await app.prefs.setStringList('pinned_course_ids', [_pack.id]);
        await app.pump(
          tester,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(body: PinnedSection()),
            ),
          ),
          overrides: [
            packProvider(packId: _pack.id).overrideWith(_FakePack.new),
          ],
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 600);
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
        final count = find.text('0 of 32');
        expect(count, findsOneWidget);
        final menu = find.byType(CardMenuButton);
        final tile = tester.getRect(find.byType(PinnedCourseTile));
        final countRect = tester.getRect(count);
        // Inside the tile, and clear of the ⋮ control when it sits beside it.
        expect(countRect.right, lessThanOrEqualTo(tile.right));
        if (menu.evaluate().isNotEmpty) {
          final menuRect = tester.getRect(menu);
          expect(
            countRect.overlaps(menuRect),
            isFalse,
            reason: 'the count must not sit under the menu button',
          );
        }
      });
    }
  }
}
