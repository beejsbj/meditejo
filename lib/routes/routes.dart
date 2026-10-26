import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/views/downloads/downloads_view.dart';
import 'package:medito/views/favorites/favorites_view.dart';
import 'package:medito/views/home/customise_home_layout_screen.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/settings/settings_screen.dart';
import 'package:medito/views/stats/stats_screen.dart';
import 'package:medito/views/teacher/teacher_view.dart';
import 'package:medito/views/timer/timer_view.dart';
import 'package:medito/views/track/track_view.dart';
import 'package:url_launcher/url_launcher.dart';

extension SanitisePath on String {
  String sanitisePath() => replaceFirst('/', '');
}

final navigatorKey = GlobalKey<NavigatorState>();

/// The tab a link such as `meditejo://library` opens; `search` is Explore with
/// the cursor in its field, and `settings` is You, where Settings lives. Null
/// for anything else.
MainTab? tabForLink(String type) => switch (type) {
  TypeConstants.tabHome => MainTab.home,
  TypeConstants.tabExplore || TypeConstants.tabSearch => MainTab.explore,
  TypeConstants.tabSounds => MainTab.sounds,
  TypeConstants.tabLibrary => MainTab.library,
  TypeConstants.tabYou || TypeConstants.tabSettings => MainTab.you,
  _ => null,
};

/// Source repositories supply track/pack IDs; navigation does not resolve media.
Future<void> handleNavigation(
  String? type,
  List<String?> ids,
  BuildContext context, {
  WidgetRef? ref,
  VoidCallback? onNavigationComplete,
  String? sourceRouteName,
  String? timerSource,
}) async {
  final values = ids.whereType<String>().where((id) => id.isNotEmpty).toList();
  if (type == null) return;
  final tab = tabForLink(type);
  if (tab != null) {
    final container = ref != null
        ? null
        : ProviderScope.containerOf(context, listen: false);
    // Close whatever is on top of the tabs, then show the one asked for.
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (ref != null) {
      ref.read(mainTabProvider.notifier).select(tab);
      if (type == TypeConstants.tabSearch) {
        ref.read(exploreFocusRequestProvider.notifier).request();
      }
    } else {
      container!.read(mainTabProvider.notifier).select(tab);
      if (type == TypeConstants.tabSearch) {
        container.read(exploreFocusRequestProvider.notifier).request();
      }
    }
    onNavigationComplete?.call();
    return;
  }
  Widget? page;
  if (type.contains('track') && values.isNotEmpty) {
    page = values.first == kLegacyTimerTrackId
        ? const TimerView()
        : TrackView(trackId: values.first);
  } else if (type == TypeConstants.teacher && values.isNotEmpty) {
    page = TeacherView(teacherId: values.first);
  } else if (type.contains('pack') && values.isNotEmpty) {
    final index = type.contains('pack3')
        ? 2
        : type.contains('pack2')
        ? 1
        : 0;
    if (index >= values.length) return;
    page = values[index] == 'favorites'
        ? const FavoritesView()
        : PackView(id: values[index]);
  } else if (type == TypeConstants.url || type == TypeConstants.link) {
    if (values.isEmpty) return;
    final uri = Uri.tryParse(values.last);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return;
  } else if (type.contains('settings')) {
    page = SettingsScreen();
  } else if (type == TypeConstants.email && values.isNotEmpty) {
    await launchEmailSubmission(values.first);
    return;
  } else if (type == TypeConstants.flow && values.contains('downloads')) {
    page = const DownloadsView();
  } else if (type == TypeConstants.route) {
    if (values.contains(TypeConstants.customiseHomeLayout)) {
      page = const CustomiseHomeLayoutScreen();
    } else if (values.any((id) => id.startsWith(RouteConstants.stats))) {
      page = StatsScreen(
        initialTabIndex: values.any((id) => id.contains(':history')) ? 1 : 0,
      );
    } else if (values.contains(RouteConstants.timer)) {
      page = const TimerView();
    }
  }
  if (page == null) return;
  await navigatorKey.currentState?.push<void>(
    MaterialPageRoute(builder: (_) => page!),
  );
  if (ref != null && context.mounted) {
    ref.read(statsProvider.notifier).refresh();
  }
  onNavigationComplete?.call();
}
