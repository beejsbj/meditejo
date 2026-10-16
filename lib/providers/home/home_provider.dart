import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/home/home_model.dart';
import '../../repositories/home/home_repository.dart';

part 'home_provider.g.dart';

/// The local catalogue owns Home's content. An empty catalogue is valid.
@riverpod
Future<HomeModel> fetchHome(Ref ref) async {
  ref.keepAlive();
  return ref.watch(homeRepositoryProvider).fetchHome();
}

@riverpod
Future<void> refreshHomeAPIs(Ref ref) async {
  ref.invalidate(fetchHomeProvider);
  await ref.read(fetchHomeProvider.future);
}
