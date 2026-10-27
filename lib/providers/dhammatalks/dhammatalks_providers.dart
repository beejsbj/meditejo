import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/dhammatalks/dhammatalks_catalogue.dart';
import 'package:medito/services/dhammatalks/dhammatalks_feed.dart';
import 'package:medito/services/dhammatalks/dhammatalks_source.dart';

/// The bundled snapshot of dhammatalks.org (`assets/dhammatalks/`), unpacked
/// in a worker isolate so the inflate and the parse stay off the UI thread.
const dhammatalksAsset = 'assets/dhammatalks/catalogue.json.gz';

Future<DtCatalogue> loadBundledDhammatalks() async {
  final data = await rootBundle.load(dhammatalksAsset);
  final json = await compute(
    DtCatalogue.decode,
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  return DtCatalogue.fromJson(json);
}

final dhammatalksSourceProvider = Provider<DhammatalksSource>(
  (ref) => DhammatalksSource(
    loadSnapshot: loadBundledDhammatalks,
    http: ref.watch(importHttpProvider),
    cache: SharedPreferencesDtFeedCache(),
    library: ref.watch(libraryStoreProvider),
  ),
);
