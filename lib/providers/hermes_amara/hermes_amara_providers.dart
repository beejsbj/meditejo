import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/hermes_amara/hermes_amara_ids.dart';
import 'package:medito/services/hermes_amara/hermes_amara_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the last Hermes Amāra listing in shared preferences. Only used when
/// `hermesAmaraEnabled` is on; with it off nothing here ever runs.
class SharedPreferencesHaListingCache implements HaListingCache {
  static const _raw = 'hermes_amara_listing_v1';
  static const _at = 'hermes_amara_listing_at_v1';

  @override
  Future<HaListingState?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_raw);
    final at = DateTime.tryParse(prefs.getString(_at) ?? '');
    return raw == null || at == null
        ? null
        : HaListingState(raw: raw, fetchedAt: at);
  }

  @override
  Future<void> write(HaListingState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_raw, state.raw);
    await prefs.setString(_at, state.fetchedAt.toUtc().toIso8601String());
  }
}

/// The Hermes Amāra adapter. It joins `contentSourcesProvider` only when the
/// compile-time flag is on (it is off in every build; see DECISIONS.md,
/// 2026-10-27), so nothing reads this provider otherwise.
final hermesAmaraSourceProvider = Provider<HermesAmaraSource>(
  (ref) => HermesAmaraSource(
    fetchListing: () async {
      final result = await ref
          .read(importHttpProvider)
          .get(Uri.parse(haListingUrl));
      if (!result.ok) {
        throw StateError('Hermes Amāra listing: HTTP ${result.status}');
      }
      return result.text;
    },
    library: ref.watch(libraryStoreProvider),
    cache: SharedPreferencesHaListingCache(),
  ),
);
