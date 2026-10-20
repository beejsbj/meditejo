import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/library/library_models.dart';

ContinueItem _item(
  String id,
  LibraryGroup group,
  int day, {
  String? course,
}) => ContinueItem(
  trackId: id,
  path: '/tracks/$id',
  title: id,
  group: group,
  lastPlayed: DateTime(2026, 10, day),
  courseId: course,
);

void main() {
  test('practice comes before talks, however recent the talk', () {
    final ranked = rankContinue([
      _item('talk-new', LibraryGroup.talks, 19),
      _item('practice-old', LibraryGroup.practice, 1),
    ]);
    expect(ranked.map((i) => i.trackId), ['practice-old', 'talk-new']);
  });

  test('within a group, the most recently played leads', () {
    final ranked = rankContinue([
      _item('a', LibraryGroup.practice, 3),
      _item('b', LibraryGroup.practice, 9),
      _item('c', LibraryGroup.practice, 5),
    ]);
    expect(ranked.map((i) => i.trackId), ['b', 'c', 'a']);
  });

  test('shows at most three', () {
    final ranked = rankContinue([
      for (var i = 1; i <= 6; i++) _item('t$i', LibraryGroup.practice, i),
    ]);
    expect(ranked.map((i) => i.trackId), ['t6', 't5', 't4']);
  });

  test('a course appears once, by its best-ranked session', () {
    final ranked = rankContinue([
      _item('s1', LibraryGroup.practice, 2, course: 'c'),
      _item('s2', LibraryGroup.practice, 8, course: 'c'),
      _item('single', LibraryGroup.practice, 5),
    ]);
    expect(ranked.map((i) => i.trackId), ['s2', 'single']);
  });

  test('ties are stable by session id', () {
    final ranked = rankContinue([
      _item('b', LibraryGroup.practice, 4),
      _item('a', LibraryGroup.practice, 4),
    ]);
    expect(ranked.map((i) => i.trackId), ['a', 'b']);
  });

  test('nothing in, nothing out', () {
    expect(rankContinue(const []), isEmpty);
  });
}
