import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/app_globals.dart' show appReadyCompleter;
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/intro/first_run_intro.dart';
import 'package:medito/views/bottom_navigation/bottom_navigation_bar_view.dart';
import 'package:medito/views/intro/intro_view.dart';
import 'package:medito/views/root/root_page_view.dart';

/// Opens the local library without requiring an account or network
/// connection. On a fresh install the intro ([IntroView]) opens over Home
/// once; Start closes it onto Home.
class SplashView extends ConsumerStatefulWidget {
  const SplashView({
    super.key,
    this.root = const RootPageView(firstChild: BottomNavigationBarView()),
  });
  static const routeName = 'SplashView';

  /// The tabs. Tests pass a stand-in.
  final Widget root;

  @override
  ConsumerState<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends ConsumerState<SplashView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!appReadyCompleter.isCompleted) appReadyCompleter.complete();
      final showIntro = FirstRunIntro.isDue(
        ref.read(sharedPreferencesProvider),
      );
      final navigator = Navigator.of(context);
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => widget.root),
      );
      if (showIntro) navigator.push(IntroView.firstRunRoute());
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
