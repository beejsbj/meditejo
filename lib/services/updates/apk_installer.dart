import 'dart:async';

import 'package:flutter/services.dart';
import 'package:medito/services/updates/update_failure.dart';

/// What Android's package manager says about a downloaded APK.
class ApkInspection {
  const ApkInspection({
    required this.packageMatches,
    required this.signatureMatchesPin,
    required this.versionCode,
  });

  /// It is Meditejo's own package.
  final bool packageMatches;

  /// Exactly one signer, and its certificate SHA-256 is the pinned digest.
  final bool signatureMatchesPin;
  final int versionCode;
}

sealed class InstallOutcome {
  const InstallOutcome();
}

class InstallSucceeded extends InstallOutcome {
  const InstallSucceeded();
}

/// The person closed Android's install prompt.
class InstallCancelled extends InstallOutcome {
  const InstallCancelled();
}

class InstallRejected extends InstallOutcome {
  const InstallRejected(this.message);

  final String message;
}

/// The Android half of an update: certificate inspection, the "Install
/// unknown apps" permission and the install session itself.
abstract class ApkInstaller {
  Future<bool> canInstallPackages();

  /// Opens Android's "Install unknown apps" page for this app.
  Future<void> openInstallPermissionSettings();

  /// Reads the APK's package, version and signing certificate.
  Future<ApkInspection> inspect(String path);

  /// Hands the APK to Android. Completes once the install has succeeded,
  /// been cancelled or been rejected (on success the process is usually
  /// replaced first, so the future may simply never complete).
  Future<InstallOutcome> install(String path);
}

class MethodChannelApkInstaller implements ApkInstaller {
  MethodChannelApkInstaller([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const channelName = 'meditejo.app/updater';

  final MethodChannel _channel;
  Completer<InstallOutcome>? _pending;

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'installResult') return null;
    final args = (call.arguments as Map).cast<String, Object?>();
    final outcome = switch (args['status']) {
      'success' => const InstallSucceeded(),
      'cancelled' => const InstallCancelled(),
      _ => InstallRejected('${args['message'] ?? ''}'),
    };
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(outcome);
    return null;
  }

  @override
  Future<bool> canInstallPackages() async =>
      await _channel.invokeMethod<bool>('canInstallPackages') ?? false;

  @override
  Future<void> openInstallPermissionSettings() =>
      _channel.invokeMethod<void>('openInstallPermissionSettings');

  @override
  Future<ApkInspection> inspect(String path) async {
    final map = await _channel.invokeMapMethod<String, Object?>('inspectApk', {
      'path': path,
    });
    if (map == null) {
      throw const UpdateException(UpdateFailure.notMeditejo, 'No inspection');
    }
    return ApkInspection(
      packageMatches: map['packageMatches'] == true,
      signatureMatchesPin: map['signatureMatchesPin'] == true,
      versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<InstallOutcome> install(String path) async {
    final pending = _pending = Completer<InstallOutcome>();
    try {
      await _channel.invokeMethod<void>('install', {'path': path});
    } on PlatformException catch (e) {
      _pending = null;
      return InstallRejected(e.message ?? e.code);
    }
    return pending.future;
  }
}
