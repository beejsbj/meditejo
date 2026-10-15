import 'package:medito/models/home/announcement/announcement_model.dart';
import 'package:medito/models/home/home_model.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'home_repository.g.dart';

abstract class HomeRepository {
  Future<HomeModel> fetchHome();

  Future<AnnouncementModel?> fetchLatestAnnouncement();
}

class HomeRepositoryImpl extends HomeRepository {
  HomeRepositoryImpl({this.catalogue = const LocalCatalogue()});

  final LocalCatalogue catalogue;

  @override
  Future<HomeModel> fetchHome() async => catalogue.home;

  @override
  Future<AnnouncementModel?> fetchLatestAnnouncement() async => null;
}

@riverpod
HomeRepositoryImpl homeRepository(Ref ref) {
  return HomeRepositoryImpl();
}
