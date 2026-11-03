import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/services/home/next_session.dart';

PackModel _pack(
  int sessions, {
  Set<int> done = const {},
  List<PackItemsModel> extra = const [],
}) => PackModel(
  id: 'course',
  title: 'Course',
  items: [
    for (var i = 1; i <= sessions; i++)
      PackItemsModel(
        type: TypeConstants.track,
        id: 't$i',
        title: 'Lesson $i',
        path: '/tracks/t$i',
        isCompleted: done.contains(i),
      ),
    ...extra,
  ],
);

DateTime _day(int d) => DateTime(2026, 10, d);

void main() {
  group('nextSessionFor', () {
    test('a fresh course offers its first session, as a start', () {
      final next = nextSessionFor(_pack(4))!;
      expect(next.item.id, 't1');
      expect(next.isPartway, isFalse);
      expect(next.isResume, isFalse);
      expect(next.completedCount, 0);
    });

    test('a course with nothing playable has no next session', () {
      expect(nextSessionFor(_pack(0)), isNull);
    });

    test('a session left partway wins over the first incomplete one', () {
      final next = nextSessionFor(_pack(4), partial: {'t2': _day(18)})!;
      expect(next.item.id, 't2');
      expect(next.isPartway, isTrue);
      expect(next.isResume, isTrue);
      expect(next.leftPartwayAt, _day(18));
    });

    test('a partway session in an otherwise untouched course resumes', () {
      final next = nextSessionFor(_pack(18), partial: {'t2': _day(18)})!;
      expect(next.item.id, 't2');
      expect(next.completedCount, 0);
      expect(next.isResume, isTrue);
    });

    test('the most recently left of several partway sessions wins', () {
      final next = nextSessionFor(
        _pack(5),
        partial: {'t2': _day(10), 't4': _day(20), 't3': _day(15)},
      )!;
      expect(next.item.id, 't4');
    });

    test('a tie on time keeps the earlier session', () {
      final next = nextSessionFor(
        _pack(4),
        partial: {'t3': _day(10), 't2': _day(10)},
      )!;
      expect(next.item.id, 't2');
    });

    test('without partway sessions it is the first incomplete one', () {
      final next = nextSessionFor(_pack(5, done: {1, 2, 4}))!;
      expect(next.item.id, 't3');
      expect(next.completedCount, 3);
      expect(next.isPartway, isFalse);
      expect(next.isResume, isTrue, reason: 'something is already finished');
    });

    test('mixed finished and partway: the partway one wins, even later', () {
      final next = nextSessionFor(
        _pack(6, done: {1, 2}),
        partial: {'t5': _day(12)},
      )!;
      expect(next.item.id, 't5');
      expect(next.completedCount, 2);
    });

    test('a finished session is never offered, even with a stale mark', () {
      final next = nextSessionFor(
        _pack(4, done: {2}),
        partial: {'t2': _day(20), 't3': _day(10)},
      )!;
      expect(next.item.id, 't3');
    });

    test(
      'a stale mark on a finished session falls back to first incomplete',
      () {
        final next = nextSessionFor(
          _pack(3, done: {1}),
          partial: {'t1': _day(20)},
        )!;
        expect(next.item.id, 't2');
        expect(next.isPartway, isFalse);
      },
    );

    test('marks for sessions outside the course are ignored', () {
      final next = nextSessionFor(_pack(3), partial: {'elsewhere': _day(20)})!;
      expect(next.item.id, 't1');
    });

    test('a finished course has no next session', () {
      expect(nextSessionFor(_pack(3, done: {1, 2, 3})), isNull);
      expect(
        nextSessionFor(_pack(3, done: {1, 2, 3}), partial: {'t2': _day(1)}),
        isNull,
      );
    });

    test('completedIds overrides the items own flags', () {
      final pack = _pack(4, done: {1});
      expect(nextSessionFor(pack)!.item.id, 't2');
      final next = nextSessionFor(pack, completedIds: {'t1', 't2'})!;
      expect(next.item.id, 't3');
      expect(next.completedCount, 2);
      expect(nextSessionFor(pack, completedIds: const {})!.item.id, 't1');
    });

    test('sub-packs and links are not sessions', () {
      final pack = _pack(
        2,
        done: {1, 2},
        extra: const [
          PackItemsModel(
            type: TypeConstants.pack,
            id: 'child',
            title: 'Child',
            path: '/packs/child',
          ),
        ],
      );
      expect(nextSessionFor(pack, partial: {'child': _day(1)}), isNull);
    });
  });
}
