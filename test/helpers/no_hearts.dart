import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/widgets/medito_icon.dart';

/// Material's hearts, in every style the app could reach for.
final _hearts = {
  Icons.favorite,
  Icons.favorite_border,
  Icons.favorite_rounded,
  Icons.favorite_border_rounded,
  Icons.favorite_outlined,
  Icons.favorite_sharp,
  Icons.favorite_border_sharp,
};

/// Fails if anything on screen is a heart or a favourite's star: keeping
/// things is pinning, with a pin (#79).
void expectNoHearts() {
  final hearts = find.byWidgetPredicate(
    (w) => w is Icon && _hearts.contains(w.icon),
  );
  expect(hearts, findsNothing, reason: 'a heart icon is on screen');
  final assets = find.byWidgetPredicate(
    (w) =>
        w is MeditoIcon &&
        (w.assetName.contains('heart') || w.assetName.contains('star')),
  );
  expect(assets, findsNothing, reason: 'a heart or star asset is on screen');
  for (final word in ['Favorites', 'Favourites', 'favorites', 'favourites']) {
    expect(find.textContaining(word), findsNothing, reason: word);
  }
}
