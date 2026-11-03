import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';

// The generated signatures are sharePackText(link, packName) and
// shareTrackText(link, trackName): placeholders are sorted alphabetically.
// Callers must pass the link first, so the name lands in the name slot.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('sharePackText puts the pack name before the link', () {
    const link = 'meditejo://meditejo/packs/42';
    const name = 'Practising the Jhānas';

    final text = l10n.sharePackText(link, name);

    expect(text, contains('Check out $name on Meditejo!'));
    expect(text.indexOf(name), lessThan(text.indexOf(link)));
    expect(text, isNot(contains('Check out $link')));
  });

  test('shareTrackText puts the track name before the link', () {
    const link = 'meditejo://meditejo/tracks/7';
    const name = 'Body Scan';

    final text = l10n.shareTrackText(link, name);

    expect(text, contains('"$name" on Meditejo.'));
    expect(text.indexOf(name), lessThan(text.indexOf(link)));
  });
}
