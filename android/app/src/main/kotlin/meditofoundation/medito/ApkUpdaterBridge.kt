package meditofoundation.medito

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * The Android half of in-app updates: reads a downloaded APK's signing
 * certificate, sends the person to "Install unknown apps", and installs through
 * a PackageInstaller session. The Dart side is lib/services/updates/apk_installer.dart.
 */
class ApkUpdaterBridge(
    private val activity: Activity,
    private val scope: CoroutineScope,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "meditejo.app/updater"

        @Volatile
        private var channel: MethodChannel? = null

        /** Passes an install result to Dart; called by [ApkInstallResultReceiver] on the main thread. */
        fun report(status: String, message: String?) {
            channel?.invokeMethod("installResult", mapOf("status" to status, "message" to message))
        }
    }

    fun attach(messenger: BinaryMessenger) {
        val methodChannel = MethodChannel(messenger, CHANNEL)
        methodChannel.setMethodCallHandler(this)
        channel = methodChannel
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canInstallPackages" -> result.success(activity.packageManager.canRequestPackageInstalls())
            "openInstallPermissionSettings" -> {
                val intent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${activity.packageName}"),
                )
                activity.startActivity(intent)
                result.success(null)
            }
            "inspectApk" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("ARGUMENT", "path is required", null)
                    return
                }
                scope.launch(Dispatchers.IO) {
                    val outcome = runCatching { inspect(path) }
                    withContext(Dispatchers.Main) {
                        outcome.fold(
                            { result.success(it) },
                            { result.error("INSPECT", it.message, null) },
                        )
                    }
                }
            }
            "install" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("ARGUMENT", "path is required", null)
                    return
                }
                scope.launch(Dispatchers.IO) {
                    val outcome = runCatching { install(File(path)) }
                    withContext(Dispatchers.Main) {
                        outcome.fold(
                            { result.success(null) },
                            { result.error("INSTALL", it.message, null) },
                        )
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun inspect(path: String): Map<String, Any> {
        val info = archiveInfo(path) ?: error("Android could not read this file as an APK.")
        val signers: List<ByteArray> = if (Build.VERSION.SDK_INT >= 28) {
            info.signingInfo?.apkContentsSigners?.map { it.toByteArray() } ?: emptyList()
        } else {
            info.signatures?.map { it.toByteArray() } ?: emptyList()
        }
        val versionCode: Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        return mapOf(
            "packageMatches" to (info.packageName == activity.packageName),
            "signatureMatchesPin" to UpdateSignaturePolicy.signersMatchPin(signers),
            "versionCode" to versionCode,
        )
    }

    @Suppress("DEPRECATION")
    private fun archiveInfo(path: String): PackageInfo? {
        val pm = activity.packageManager
        return when {
            Build.VERSION.SDK_INT >= 33 -> pm.getPackageArchiveInfo(
                path,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong()),
            )
            Build.VERSION.SDK_INT >= 28 -> pm.getPackageArchiveInfo(path, PackageManager.GET_SIGNING_CERTIFICATES)
            else -> pm.getPackageArchiveInfo(path, PackageManager.GET_SIGNATURES)
        }
    }

    private fun install(apk: File) {
        val installer = activity.packageManager.packageInstaller
        // A session left by an earlier attempt would hold the same package.
        installer.mySessions.forEach { runCatching { installer.abandonSession(it.sessionId) } }

        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(activity.packageName)
        params.setSize(apk.length())
        if (Build.VERSION.SDK_INT >= 31) {
            // Honoured only for an update by the installer of record; otherwise Android asks.
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }

        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            apk.inputStream().use { input ->
                session.openWrite("meditejo.apk", 0, apk.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            val callback = PendingIntent.getBroadcast(
                activity,
                sessionId,
                Intent(activity, ApkInstallResultReceiver::class.java),
                flags,
            )
            session.commit(callback.intentSender)
        }
    }
}
