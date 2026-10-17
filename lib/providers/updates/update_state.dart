import 'package:medito/services/updates/update_failure.dart';
import 'package:medito/services/updates/update_release.dart';

enum UpdatePhase {
  /// Nothing known yet.
  idle,
  checking,
  upToDate,
  available,
  downloading,
  verifying,

  /// Waiting for "Install unknown apps" to be switched on.
  needsPermission,
  installing,
  failed,
}

class InstalledBuild {
  const InstalledBuild({required this.versionName, required this.versionCode});

  final String versionName;
  final int versionCode;
}

class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.release,
    this.progress = 0,
    this.failure,
    this.failureDetail,
    this.lastCheckedAt,
    this.dismissedVersionCode,
    this.explainPermission = false,
  });

  final UpdatePhase phase;

  /// The newest release, only when it is newer than the installed build.
  final UpdateRelease? release;

  /// Download progress, 0 to 1.
  final double progress;
  final UpdateFailure? failure;
  final String? failureDetail;
  final DateTime? lastCheckedAt;

  /// The version whose Home notice was dismissed.
  final int? dismissedVersionCode;

  /// The permission step has not been explained before.
  final bool explainPermission;

  bool get isBusy => const {
    UpdatePhase.checking,
    UpdatePhase.downloading,
    UpdatePhase.verifying,
    UpdatePhase.installing,
  }.contains(phase);

  /// The single dismissible line on Home: a new version, said once.
  bool get showHomeNotice =>
      phase == UpdatePhase.available &&
      release != null &&
      release!.versionCode != dismissedVersionCode;

  UpdateState copyWith({
    UpdatePhase? phase,
    UpdateRelease? release,
    bool clearRelease = false,
    double? progress,
    UpdateFailure? failure,
    String? failureDetail,
    bool clearFailure = false,
    DateTime? lastCheckedAt,
    int? dismissedVersionCode,
    bool? explainPermission,
  }) => UpdateState(
    phase: phase ?? this.phase,
    release: clearRelease ? null : release ?? this.release,
    progress: progress ?? this.progress,
    failure: clearFailure ? null : failure ?? this.failure,
    failureDetail: clearFailure ? null : failureDetail ?? this.failureDetail,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    dismissedVersionCode: dismissedVersionCode ?? this.dismissedVersionCode,
    explainPermission: explainPermission ?? this.explainPermission,
  );
}
