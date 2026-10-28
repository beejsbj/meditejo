import 'package:flutter/foundation.dart';
import 'package:medito/utils/signed_url_redaction.dart';

/// Makes every Flutter-side log line, including the framework's own error
/// dumps, pass through [redactSignedUrls]. Called once from `main`.
void redactDebugPrint() {
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => original(
    message == null ? null : redactSignedUrls(message),
    wrapWidth: wrapWidth,
  );
}

/// A utility class for logging messages only in debug mode
class AppLogger {
  /// Log a debug message that will only be shown in debug mode
  static void d(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[${DateTime.now()} $tag] ${redactSignedUrls(message)}');
    }
  }

  /// Log an error message that will only be shown in debug mode
  static void e(
    String tag,
    String message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    if (kDebugMode) {
      debugPrint(
        '[${DateTime.now()} $tag] 🛑 ERROR: ${redactSignedUrls(message)}',
      );
      if (error != null) {
        debugPrint(
          '[${DateTime.now()} $tag] Error details: '
          '${redactSignedUrls('$error')}',
        );
      }
      if (stackTrace != null) {
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  /// Log an info message that will only be shown in debug mode
  static void i(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[${DateTime.now()} $tag] ℹ️ ${redactSignedUrls(message)}');
    }
  }

  /// Log a warning message that will only be shown in debug mode
  static void w(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[${DateTime.now()} $tag] ⚠️ ${redactSignedUrls(message)}');
    }
  }
}

class AppLoggerAdapter {
  const AppLoggerAdapter(this.tag);

  final String tag;

  void log(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    int? level,
  }) {
    if (error != null || stackTrace != null) {
      AppLogger.e(tag, message, error, stackTrace);

      return;
    }

    AppLogger.d(tag, message);
  }
}
