import 'package:flutter/material.dart';
import 'package:medito/app_globals.dart' show appReadyCompleter;
import 'package:medito/views/bottom_navigation/bottom_navigation_bar_view.dart';
import 'package:medito/views/root/root_page_view.dart';

/// Opens the local library without requiring an account or network connection.
class SplashView extends StatefulWidget {
  const SplashView({super.key});
  static const routeName = 'SplashView';

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!appReadyCompleter.isCompleted) appReadyCompleter.complete();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              const RootPageView(firstChild: BottomNavigationBarView()),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
