import 'package:flutter/foundation.dart';

/// The extractor's host bridge is currently implemented only on Android.
bool get youtubeBridgeAvailable =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
