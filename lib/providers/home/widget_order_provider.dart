import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/enums/home_widget_type.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';

final homeWidgetOrderProvider =
    NotifierProvider<HomeWidgetOrderNotifier, List<HomeWidgetType>>(
      HomeWidgetOrderNotifier.new,
    );

class HomeWidgetOrderNotifier extends Notifier<List<HomeWidgetType>> {
  static const _defaultOrder = [
    HomeWidgetType.upNext,
    HomeWidgetType.shortcuts,
    HomeWidgetType.carousel,
    HomeWidgetType.quote,
  ];

  @override
  List<HomeWidgetType> build() => _loadOrder();

  List<HomeWidgetType> _loadOrder() {
    final saved = ref
        .read(sharedPreferencesProvider)
        .getStringList(SharedPreferenceConstants.homeWidgetOrder);
    if (saved == null) return List.of(_defaultOrder);

    // Ignore retired sections and unknown names rather than mapping them to
    // shortcuts. Preserve the relative order of the remaining sections.
    final byName = {for (final type in _defaultOrder) type.name: type};
    final order = <HomeWidgetType>{
      for (final name in saved) ?byName[name],
    }.toList();
    for (final type in _defaultOrder) {
      if (order.contains(type)) continue;
      if (type == HomeWidgetType.upNext) {
        order.insert(0, type);
      } else {
        order.add(type);
      }
    }
    return order;
  }

  Future<void> updateOrder(List<HomeWidgetType> newOrder) async {
    final order = newOrder.where(_defaultOrder.contains).toSet().toList();
    state = order;
    await ref
        .read(sharedPreferencesProvider)
        .setStringList(
          SharedPreferenceConstants.homeWidgetOrder,
          order.map((type) => type.name).toList(),
        );
  }

  void refreshOrder() => state = _loadOrder();
}
