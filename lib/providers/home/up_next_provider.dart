import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/home_widget_service.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'up_next_provider.g.dart';

String? _lastPushedWidgetSignature;

/// An empty ID means no course is pinned. There is no bundled course fallback.
@riverpod
String upNextPackId(Ref ref) {
  return ref
          .watch(sharedPreferencesProvider)
          .getString(SharedPreferenceConstants.upNextPackId) ??
      '';
}

class UpNextData {
  final PackModel pack;
  final PackItemsModel? nextSession;
  final int completedCount;
  final int totalCount;
  final String? nextPackId;
  final bool isEndOfPath;

  const UpNextData({
    required this.pack,
    required this.nextSession,
    required this.completedCount,
    required this.totalCount,
    this.nextPackId,
    this.isEndOfPath = false,
  });

  const UpNextData.empty()
    : pack = const PackModel(id: '', title: ''),
      nextSession = null,
      completedCount = 0,
      totalCount = 0,
      nextPackId = null,
      isEndOfPath = false;

  double get progressPercentage =>
      totalCount > 0 ? (completedCount / totalCount) * 100 : 0;

  bool get isCompleted => totalCount > 0 && completedCount >= totalCount;
}

/// Resolve an explicitly pinned source course through the local repository.
/// Completion is derived locally; no seed IDs or global course sequence apply.
@Riverpod(keepAlive: true)
AsyncValue<UpNextData> upNext(Ref ref) {
  final packId = ref.watch(upNextPackIdProvider);
  if (packId.isEmpty) {
    _updateWidget(const UpNextData.empty());
    return const AsyncData(UpNextData.empty());
  }

  return ref
      .watch(packProvider(packId: packId))
      .when(
        loading: () => const AsyncLoading(),
        error: (error, stack) {
          // Old pins can outlive their source or a catalogue entry. Keep the pin
          // for a future source refresh while leaving Home usable now.
          _updateWidget(const UpNextData.empty());
          return error is CatalogueEntryUnavailable
              ? const AsyncData(UpNextData.empty())
              : AsyncError(error, stack);
        },
        data: (pack) {
          final completed = pack.items
              .where((item) => item.isCompleted == true)
              .length;
          final remaining = pack.items.where(
            (item) => item.isCompleted != true,
          );
          final data = UpNextData(
            pack: pack,
            nextSession: remaining.firstOrNull,
            completedCount: completed,
            totalCount: pack.items.length,
          );
          _updateWidget(data);
          return AsyncData(data);
        },
      );
}

void _updateWidget(UpNextData data) {
  final session = data.nextSession;
  final signature =
      '${data.pack.id}|${session?.id}|${data.completedCount}/${data.totalCount}';
  if (signature == _lastPushedWidgetSignature) return;
  _lastPushedWidgetSignature = signature;
  HomeWidgetService.updateUpNextWidget(
    title: session?.title ?? '',
    packTitle: session == null ? '' : data.pack.title,
    trackId: session?.id ?? '',
    subtitle: session?.subtitle ?? '',
    completed: data.completedCount,
    total: data.totalCount,
  ).ignore();
}
