import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/enums/home_widget_type.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';

final homeWidgetOrderProvider =
    NotifierProvider<HomeWidgetOrderNotifier, List<HomeWidgetType>>(
      HomeWidgetOrderNotifier.new,
    );

class HomeWidgetOrderNotifier extends Notifier<List<HomeWidgetType>> {
  static const _defaultOrder = HomeWidgetType.values;

  @override
  List<HomeWidgetType> build() => _loadOrder();

  List<HomeWidgetType> _loadOrder() {
    final saved = ref
        .read(sharedPreferencesProvider)
        .getStringList(SharedPreferenceConstants.homeWidgetOrder);
    if (saved == null) return List.of(_defaultOrder);

    // Ignore retired sections and unknown names. Preserve the relative order
    // of the remaining sections; a section the saved layout predates joins
    // at its default place (Continue first, the rest last).
    final order = <HomeWidgetType>{
      for (final name in saved) ?HomeWidgetType.tryParse(name),
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

/// Sections the user has switched off. Empty by default: every section shows.
final homeHiddenWidgetsProvider =
    NotifierProvider<HomeHiddenWidgetsNotifier, Set<HomeWidgetType>>(
      HomeHiddenWidgetsNotifier.new,
    );

class HomeHiddenWidgetsNotifier extends Notifier<Set<HomeWidgetType>> {
  @override
  Set<HomeWidgetType> build() => {
    for (final name
        in ref
                .read(sharedPreferencesProvider)
                .getStringList(SharedPreferenceConstants.homeWidgetHidden) ??
            const <String>[])
      ?HomeWidgetType.tryParse(name),
  };

  Future<void> setVisible(HomeWidgetType type, bool visible) async {
    state = visible ? ({...state}..remove(type)) : {...state, type};
    await ref
        .read(sharedPreferencesProvider)
        .setStringList(SharedPreferenceConstants.homeWidgetHidden, [
          for (final t in state) t.name,
        ]);
  }
}
