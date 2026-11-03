import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/pack/widgets/pack_complete_badge.dart';
import 'package:medito/views/pack/widgets/pack_item_widget.dart';

import '../../helpers/art_finders.dart';
import '../../helpers/library_app.dart';

/// Course rows (#82): the date in the row, a retreat's days as groups, the
/// course's own teacher not repeated, and kind only where kinds are mixed.

class _FakePack extends Pack {
  _FakePack(this.model);
  final PackModel model;

  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(model);
}

const _credit = SourceAttribution(
  source: 'Dharma Seed',
  url: 'https://dharmaseed.org/retreats/7012/',
  licenseName: 'CC BY-NC-ND 4.0',
  licenseUrl: 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
);

/// A nine-day retreat led by Joseph Goldstein, three sessions a day, with
/// talks, guided meditations and one Q & A, and a teaching team.
final _retreat = PackModel(
  id: 'ds-retreat-7012',
  title: 'Spring Insight Meditation Retreat',
  teacher: const PackTeacher(id: 'ds-teacher-96', name: 'Joseph Goldstein'),
  attribution: _credit,
  items: [
    for (var i = 0; i < 27; i++)
      PackItemsModel(
        type: 'track',
        id: 'ds-talk-$i',
        title: 'Retreat session ${i + 1}',
        path: '/tracks/ds-talk-$i',
        kind: i == 5
            ? 'Q & A'
            : i % 3 == 0
            ? 'Guided meditation'
            : 'Talk',
        teacher: i % 3 == 2 ? 'Sharon Salzberg' : 'Joseph Goldstein',
        durationMs: 45 * 60000,
        date: '2023-04-${14 + i ~/ 3}',
        // The whole of the first day played.
        isCompleted: i < 3,
      ),
  ],
);

/// A weekly series of talks only, over [weeks] weeks from September 2024.
PackModel _series({int weeks = 16, String id = 'ds-retreat-8000'}) => PackModel(
  id: id,
  title: 'Sunday Talks',
  teacher: const PackTeacher(id: 'ds-teacher-12', name: 'Gil Fronsdal'),
  attribution: _credit,
  items: [
    for (var i = 0; i < weeks; i++)
      PackItemsModel(
        type: 'track',
        id: 'ds-talk-s$i',
        title: 'Sunday talk ${i + 1}',
        path: '/tracks/ds-talk-s$i',
        kind: 'Talk',
        teacher: i == 2 ? 'Andrea Fella' : 'Gil Fronsdal',
        durationMs: 50 * 60000,
        date: DateTime.utc(
          2024,
          9,
          1,
        ).add(Duration(days: 7 * i)).toIso8601String().substring(0, 10),
      ),
  ],
);

/// A podcast: no teacher record, its author as the subtitle, no kinds.
final _podcast = PackModel(
  id: 'lib-course-ad',
  title: 'Audio Dharma',
  subtitle: 'Gil Fronsdal',
  attribution: _credit,
  items: [
    for (var i = 0; i < 3; i++)
      PackItemsModel(
        type: 'track',
        id: 'lib-ad-$i',
        title: 'Episode ${i + 1}',
        subtitle: i == 1 ? 'Ines Freedman' : 'Gil Fronsdal',
        teacher: i == 1 ? 'Ines Freedman' : 'Gil Fronsdal',
        path: '/tracks/lib-ad-$i',
        durationMs: 40 * 60000,
        date: '2025-01-0${i + 1}',
      ),
  ],
);

/// The meta line of the row titled [title], with plain spaces.
String _meta(WidgetTester tester, String title) {
  final row = find.ancestor(
    of: find.text(title),
    matching: find.byType(PackItemWidget),
  );
  final meta = find.descendant(
    of: row,
    matching: find.byKey(const ValueKey('session_meta')),
  );
  return tester.widget<Text>(meta).data!.replaceAll(' ', ' ');
}

/// The kind chip of the row titled [title], or null.
String? _chip(WidgetTester tester, String title) {
  final row = find.ancestor(
    of: find.text(title),
    matching: find.byType(PackItemWidget),
  );
  final texts = tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .where((t) => t != title && !t.contains('min') && t.isNotEmpty)
      .toList();
  return texts.isEmpty ? null : texts.single;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(holdCuratedArt);

  Future<void> open(WidgetTester tester, PackModel pack) async {
    final app = await LibraryTestApp.create(tester);
    await app.pump(
      tester,
      PackView(id: pack.id),
      overrides: [
        packProvider(packId: pack.id).overrideWith(() => _FakePack(pack)),
      ],
    );
    // A tall phone, so a retreat's first days are on screen.
    tester.view.devicePixelRatio = 2.625;
    tester.view.physicalSize = const Size(1080, 4000);
    addTearDown(tester.view.reset);
    await tester.pump();
  }

  testWidgets('a retreat\'s days are bordered groups with a small day label', (
    tester,
  ) async {
    await open(tester, _retreat);

    final day1 = find.byKey(const ValueKey('day_2023-04-14'));
    final day2 = find.byKey(const ValueKey('day_2023-04-15'));
    expect(day1, findsOneWidget);
    expect(day2, findsOneWidget);
    // Inside the group: its label, then its own three sessions.
    expect(
      find.descendant(of: day1, matching: find.text('Day 1 · Fri, Apr 14')),
      findsOneWidget,
    );
    for (final title in [
      'Retreat session 1',
      'Retreat session 2',
      'Retreat session 3',
    ]) {
      expect(find.descendant(of: day1, matching: find.text(title)), findsOne);
    }
    expect(
      find.descendant(of: day1, matching: find.text('Retreat session 4')),
      findsNothing,
    );
    expect(
      find.descendant(of: day2, matching: find.text('Day 2 · Sat, Apr 15')),
      findsOneWidget,
    );

    // A box with a border, not a heading over the list.
    final box = tester.widget<Material>(
      find.descendant(of: day1, matching: find.byType(Material)).first,
    );
    expect(box.shape, isA<RoundedRectangleBorder>());
    expect(
      (box.shape! as RoundedRectangleBorder).side.style,
      BorderStyle.solid,
    );
    // A label, not a big heading.
    final label = tester.widget<Text>(find.text('Day 1 · Fri, Apr 14'));
    expect(label.style!.fontSize, lessThanOrEqualTo(13));

    // The day played through is ticked; the next is not.
    expect(
      find.descendant(of: day1, matching: find.byType(PackCompleteBadge)),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Day 2 · Sat, Apr 15'),
          matching: find.byType(Row),
        ),
        matching: find.byType(PackCompleteBadge),
      ),
      findsNothing,
    );
  });

  testWidgets('a retreat\'s rows leave the date to their day', (tester) async {
    await open(tester, _retreat);
    // Joseph Goldstein leads: his own sessions say only their length.
    expect(_meta(tester, 'Retreat session 1'), '45 min');
    // Another teacher's session names them.
    expect(_meta(tester, 'Retreat session 3'), 'Sharon Salzberg · 45 min');
  });

  testWidgets('a mixed course shows each session\'s kind as a chip', (
    tester,
  ) async {
    await open(tester, _retreat);
    expect(_chip(tester, 'Retreat session 1'), 'Guided meditation');
    expect(_chip(tester, 'Retreat session 2'), 'Talk');
    expect(_chip(tester, 'Retreat session 6'), 'Q & A');
    // Not the loud capitals of before.
    expect(find.text('GUIDED MEDITATION'), findsNothing);
    expect(find.text('TALK'), findsNothing);
  });

  testWidgets('a course of one kind says no kind, and dates its rows', (
    tester,
  ) async {
    await open(tester, _series());
    expect(_chip(tester, 'Sunday talk 1'), isNull);
    expect(find.text('Talk'), findsNothing);
    // Months of talks: no day groups, the date in each row. One year in
    // all, so the header's year is not repeated.
    expect(find.byKey(const ValueKey('day_2024-09-01')), findsNothing);
    expect(find.textContaining('Day 1'), findsNothing);
    expect(_meta(tester, 'Sunday talk 1'), 'Sep 1 · 50 min');
    expect(_meta(tester, 'Sunday talk 3'), 'Andrea Fella · Sep 15 · 50 min');
  });

  testWidgets('a series across years writes the year in its dates', (
    tester,
  ) async {
    await open(tester, _series(weeks: 20, id: 'ds-retreat-8001'));
    expect(_meta(tester, 'Sunday talk 1'), 'Sep 1, 2024 · 50 min');
  });

  testWidgets('a retreat listed out of date order is not split into days', (
    tester,
  ) async {
    final shuffled = _retreat.copyWith(
      id: 'ds-retreat-7013',
      // The first session moved to the end: Apr 14 comes round twice.
      items: [..._retreat.items.skip(1), _retreat.items.first],
    );
    await open(tester, shuffled);
    expect(find.byKey(const ValueKey('day_2023-04-14')), findsNothing);
    expect(_meta(tester, 'Retreat session 4'), 'Apr 15 · 45 min');
  });

  testWidgets('a podcast drops its author from rows, not its guests', (
    tester,
  ) async {
    await open(tester, _podcast);
    expect(_meta(tester, 'Episode 1'), 'Jan 1 · 40 min');
    expect(_meta(tester, 'Episode 2'), 'Ines Freedman · Jan 2 · 40 min');
    // A short course is not grouped.
    expect(find.byKey(const ValueKey('day_2025-01-01')), findsNothing);
  });

  testWidgets('a long retreat\'s rows fit at 360 dp and a larger text size', (
    tester,
  ) async {
    await open(tester, _retreat);
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 4000);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    expect(tester.takeException(), isNull);
    // The chip stays one line.
    final chip = find.text('Guided meditation').first;
    expect(tester.getSize(chip).height, lessThan(30));
  });
}
