import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/pack_sequence.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/home/up_next_provider.dart';

PackModel _pack({
  required String id,
  required int total,
  required int completed,
}) => PackModel(
  id: id,
  title: 'Pack $id',
  items: List.generate(
    total,
    (i) => PackItemsModel(
      type: 'track',
      id: '$id-item-$i',
      title: 'Item $i',
      path: '/t/$i',
      isCompleted: i < completed,
    ),
  ),
);

UpNextData _data(PackModel pack) {
  final completed = pack.items.where((i) => i.isCompleted == true).length;
  final isCompleted = pack.items.isNotEmpty && completed >= pack.items.length;
  return UpNextData(
    pack: pack,
    nextSession: (isCompleted || pack.items.isEmpty)
        ? null
        : pack.items.firstWhere(
            (i) => i.isCompleted != true,
            orElse: () => pack.items.first,
          ),
    completedCount: completed,
    totalCount: pack.items.length,
    nextPackId: isCompleted ? PackSequence.nextPackAfter(pack.id) : null,
    isEndOfPath: isCompleted && PackSequence.isPathTerminal(pack.id),
  );
}

void main() {
  test('ships no proprietary progression', () {
    expect(PackSequence.ordered, isEmpty);
    expect(PackSequence.beginnerEntryPackId, isEmpty);
    expect(PackSequence.nextPackAfter('ds-retreat'), isNull);
    expect(PackSequence.positionOf('ds-retreat'), isNull);
  });

  group('UpNextData completion', () {
    test('an empty pack is not treated as completed', () {
      final data = _data(_pack(id: 'empty', total: 0, completed: 0));
      expect(data.isCompleted, isFalse);
      expect(data.nextPackId, isNull);
    });

    test('a partially complete pack surfaces the next session', () {
      final data = _data(_pack(id: 'ds-retreat', total: 5, completed: 2));
      expect(data.isCompleted, isFalse);
      expect(data.nextSession?.id, 'ds-retreat-item-2');
      expect(data.nextPackId, isNull, reason: 'no successor until completed');
    });

    test('completing the legacy megapack counts as the end of the path', () {
      final data = _data(
        _pack(id: PackSequence.legacyMegapackId, total: 2, completed: 2),
      );
      expect(data.isCompleted, isTrue);
      expect(data.nextPackId, isNull, reason: 'never offer a successor to it');
      expect(data.isEndOfPath, isTrue);
    });

    test('completing an unknown pack is a plain completion', () {
      final data = _data(_pack(id: 'hand-pinned', total: 2, completed: 2));
      expect(data.isCompleted, isTrue);
      expect(data.nextPackId, isNull);
      expect(data.isEndOfPath, isFalse);
    });
  });
}
