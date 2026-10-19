package meditofoundation.medito

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Keeps the process in the foreground while the Sounds mixer plays on its own
 * (no session). The mixer itself is flutter_soloud, which only renders audio:
 * it holds no service, notification or audio focus, so without this Android
 * may freeze the app soon after the screen goes off.
 *
 * During a session AudioPlayerService already holds the foreground, and the
 * mixer follows the session player instead; Dart never holds both.
 */
class SoundscapeService : Service() {

    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private var pausedForTransientLoss = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                SoundscapeBridge.send("stop")
                finish()
            }
            else -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Sounds"
                val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""
                val stopLabel = intent?.getStringExtra(EXTRA_STOP_LABEL) ?: "Stop"
                try {
                    val notification = buildNotification(title, text, stopLabel)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        startForeground(
                            NOTIFICATION_ID,
                            notification,
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                        )
                    } else {
                        startForeground(NOTIFICATION_ID, notification)
                    }
                    requestFocus()
                } catch (e: Exception) {
                    // Most likely ForegroundServiceStartNotAllowedException: the
                    // app was not in the foreground. Sounds still play while
                    // the app is visible.
                    Log.w(TAG, "Could not hold the foreground: ${e.message}")
                    stopSelf()
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Swiping the app away ends its Flutter engine, and the sound with it.
        finish()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        abandonFocus()
        super.onDestroy()
    }

    private fun finish() {
        abandonFocus()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun requestFocus() {
        if (focusRequest != null) return
        val manager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            .setWillPauseWhenDucked(false)
            .setOnAudioFocusChangeListener({ change -> onFocusChange(change) }, Handler(Looper.getMainLooper()))
            .build()
        audioManager = manager
        focusRequest = request
        manager.requestAudioFocus(request)
    }

    private fun onFocusChange(change: Int) {
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                // Another app took over playback: pause, and let the user
                // resume from the Sounds screen.
                pausedForTransientLoss = false
                SoundscapeBridge.send("pause")
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                pausedForTransientLoss = true
                SoundscapeBridge.send("pause")
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                if (pausedForTransientLoss) SoundscapeBridge.send("resume")
                pausedForTransientLoss = false
            }
        }
    }

    private fun abandonFocus() {
        val request = focusRequest ?: return
        audioManager?.abandonAudioFocusRequest(request)
        focusRequest = null
    }

    private fun buildNotification(title: String, text: String, stopLabel: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Sounds", NotificationManager.IMPORTANCE_LOW).apply {
                    setShowBadge(false)
                },
            )
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, flags)
        }
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, SoundscapeService::class.java).setAction(ACTION_STOP),
            flags,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(0, stopLabel, stop)
            .build()
    }

    companion object {
        private const val TAG = "SoundscapeService"
        private const val CHANNEL_ID = "meditejo_sounds"
        private const val NOTIFICATION_ID = 4107
        const val ACTION_HOLD = "meditejo.soundscape.HOLD"
        const val ACTION_STOP = "meditejo.soundscape.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_STOP_LABEL = "stopLabel"
    }
}

/**
 * `meditejo/soundscape`: Dart calls `hold` / `release`; the service sends
 * `command` with `stop`, `pause` or `resume` (the notification's Stop
 * action and audio focus changes).
 */
object SoundscapeBridge {
    const val CHANNEL = "meditejo/soundscape"

    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())

    fun attach(context: Context, messenger: BinaryMessenger) {
        val appContext = context.applicationContext
        channel = MethodChannel(messenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "hold" -> {
                        val intent = Intent(appContext, SoundscapeService::class.java)
                            .setAction(SoundscapeService.ACTION_HOLD)
                            .putExtra(SoundscapeService.EXTRA_TITLE, call.argument<String>("title"))
                            .putExtra(SoundscapeService.EXTRA_TEXT, call.argument<String>("text"))
                            .putExtra(SoundscapeService.EXTRA_STOP_LABEL, call.argument<String>("stopLabel"))
                        try {
                            ContextCompat.startForegroundService(appContext, intent)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.w("SoundscapeBridge", "Could not start the service: ${e.message}")
                            result.success(false)
                        }
                    }
                    "release" -> {
                        appContext.stopService(Intent(appContext, SoundscapeService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    fun send(command: String) {
        main.post { channel?.invokeMethod("command", command) }
    }
}
