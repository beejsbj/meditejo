package meditofoundation.medito

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

/**
 * Receives the PackageInstaller session's status. Android first asks for the
 * person's confirmation (STATUS_PENDING_USER_ACTION), which is shown by
 * launching the intent it hands over; every other status ends the session and
 * is passed on to Dart.
 */
class ApkInstallResultReceiver : BroadcastReceiver() {
    @Suppress("DEPRECATION")
    private fun confirmationIntent(intent: Intent): Intent? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_INTENT)
        }


    override fun onReceive(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm = confirmationIntent(intent)
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirm)
                } else {
                    ApkUpdaterBridge.report("failed", "Android did not offer a confirmation screen.")
                }
            }
            PackageInstaller.STATUS_SUCCESS -> ApkUpdaterBridge.report("success", null)
            PackageInstaller.STATUS_FAILURE_ABORTED -> ApkUpdaterBridge.report("cancelled", null)
            else -> ApkUpdaterBridge.report(
                "failed",
                intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "Install status $status",
            )
        }
    }
}
