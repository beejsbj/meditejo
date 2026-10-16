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
    HomeWidgetType.shortcuts,
    HomeWidgetType.carousel,
    HomeWidgetType.quote,
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  });

  tearDown(() => container.dispose());

  test('new installs show only local practice sections', () {
    expect(container.read(homeWidgetOrderProvider), defaults);
  });

  test('preserves the relative order of saved local sections', () async {
    await prefs.setStringList(SharedPreferenceConstants.homeWidgetOrder, [
      'quote',
      'shortcuts',
      'upNext',
      'carousel',
    ]);
    expect(container.read(homeWidgetOrderProvider), [
      HomeWidgetType.quote,
      HomeWidgetType.shortcuts,
      HomeWidgetType.upNext,
      HomeWidgetType.carousel,
    ]);
  });

  test(
    'migrates retired sections without moving shortcuts ahead of quote',
    () async {
      await prefs.setStringList(SharedPreferenceConstants.homeWidgetOrder, [
        'products',
        'donation',
        'unknown',
        'quote',
        'shortcuts',
        'quote',
      ]);
      expect(container.read(homeWidgetOrderProvider), [
        HomeWidgetType.upNext,
        HomeWidgetType.quote,
        HomeWidgetType.shortcuts,
        HomeWidgetType.carousel,
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
      'quote',
    ]);
    notifier.refreshOrder();
    expect(container.read(homeWidgetOrderProvider), [
      HomeWidgetType.upNext,
      HomeWidgetType.quote,
      HomeWidgetType.shortcuts,
      HomeWidgetType.carousel,
    ]);
  });
}
