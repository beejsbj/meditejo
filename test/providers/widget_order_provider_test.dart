import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/home/widget_order_provider.dart';
import 'package:medito/constants/enums/home_widget_type.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;
  const defaults = [
    HomeWidgetType.upNext,
    HomeWidgetType.homeShortcuts,
    HomeWidgetType.pinned,
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  });

  tearDown(() => container.dispose());

  test('new installs show every section, Continue first', () {
    expect(container.read(homeWidgetOrderProvider), defaults);
  });

  test('preserves the relative order of saved sections', () async {
    await prefs.setStringList(SharedPreferenceConstants.homeWidgetOrder, [
      'pinned',
      'homeShortcuts',
      'upNext',
    ]);
    expect(container.read(homeWidgetOrderProvider), [
      HomeWidgetType.pinned,
      HomeWidgetType.homeShortcuts,
      HomeWidgetType.upNext,
    ]);
  });

  test('a layout saved before the rename keeps its Shortcuts place', () async {
    await prefs.setStringList(SharedPreferenceConstants.homeWidgetOrder, [
      'pinned',
      'quickLinks',
      'upNext',
    ]);
    expect(container.read(homeWidgetOrderProvider), [
      HomeWidgetType.pinned,
      HomeWidgetType.homeShortcuts,
      HomeWidgetType.upNext,
    ]);
    expect(HomeWidgetType.tryParse('quickLinks'), HomeWidgetType.homeShortcuts);
    // Saving writes the new name.
    await container
        .read(homeWidgetOrderProvider.notifier)
        .updateOrder(container.read(homeWidgetOrderProvider));
    expect(prefs.getStringList(SharedPreferenceConstants.homeWidgetOrder), [
      'pinned',
      'homeShortcuts',
      'upNext',
    ]);
  });

  test(
    'ignores retired sections and a section the layout predates joins last',
    () async {
      await prefs.setStringList(SharedPreferenceConstants.homeWidgetOrder, [
        'products',
        'unknown',
        'quote',
        'homeShortcuts',
        'homeShortcuts',
        'carousel',
      ]);
      expect(container.read(homeWidgetOrderProvider), [
        HomeWidgetType.upNext,
        HomeWidgetType.homeShortcuts,
        HomeWidgetType.pinned,
      ]);
    },
  );

  test('an entirely retired order recovers the default sections', () async {
    await prefs.setStringList(SharedPreferenceConstants.homeWidgetOrder, [
      'products',
      'donation',
    ]);
    expect(container.read(homeWidgetOrderProvider), defaults);
  });

  test('updates both state and saved order', () async {
    final order = defaults.reversed.toList();
    await container.read(homeWidgetOrderProvider.notifier).updateOrder(order);
    expect(container.read(homeWidgetOrderProvider), order);
    expect(
      prefs.getStringList(SharedPreferenceConstants.homeWidgetOrder),
      order.map((type) => type.name).toList(),
    );
  });

  test('refresh reloads a changed local preference', () async {
    final notifier = container.read(homeWidgetOrderProvider.notifier);
    await prefs.setStringList(SharedPreferenceConstants.homeWidgetOrder, [
      'pinned',
    ]);
    notifier.refreshOrder();
    expect(container.read(homeWidgetOrderProvider), [
      HomeWidgetType.upNext,
      HomeWidgetType.pinned,
      HomeWidgetType.homeShortcuts,
    ]);
  });
}
