package meditofoundation.medito

import meditofoundation.medito.pigeon.*
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import java.io.File
import androidx.media3.common.util.UnstableApi
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import android.os.Handler
import android.os.Looper
import android.os.Build
import androidx.activity.enableEdgeToEdge
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.WindowInsetsCompat
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.DpSize
import meditofoundation.medito.widget.MeditationWidget
import meditofoundation.medito.widget.MeditationWidgetReceiver
import meditofoundation.medito.widget.ConsistencyWidget
import meditofoundation.medito.widget.ConsistencyWidgetReceiver

@UnstableApi
class MainActivity : FlutterFragmentActivity(), MeditoAndroidAudioServiceManager, MeditoWidgetManager {

    private var meditoAudioApi: MeditoAudioServiceCallbackApi? = null
    private val activityJob = SupervisorJob()
    private val activityScope = CoroutineScope(Dispatchers.Main + activityJob)

    // Links and audio shared into the app ("Share → Meditejo"). The share that
    // started the app is read once (audio is copied to the cache off the main
    // thread) and handed to Dart when it asks; later shares are pushed.
    private var shareChannel: MethodChannel? = null
    private var initialShare: Deferred<Map<String, Any?>?>? = null

    private val healthConnectBridge by lazy { HealthConnectBridge(this, activityScope) }
    private val healthConnectPermissionLauncher = registerForActivityResult(
        androidx.health.connect.client.PermissionController
            .createRequestPermissionResultContract()
    ) { granted ->
        healthConnectBridge.onPermissionResult(granted)
    }

    // audio_service drives iOS only; Android plays through AudioPlayerService. If
    // the plugin attaches to this activity it starts a second FlutterEngine that
    // runs main() again, repeats app initialization, and binds to a
    // service we never declare, whose failure NPEs if it lands after a detach.
    // It must be gone before the activity attaches, which happens before
    // configureFlutterEngine, so build the engine here without it. The fragment
    // still destroys it with the activity, and super.configureFlutterEngine
    // skips plugin registration for an injected engine.
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        FlutterEngine(
            context,
            FlutterShellArgs.fromIntent(intent).toArray(),
            true,
            true,
        ).also { it.plugins.remove(AudioServicePlugin::class.java) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        FlutterEngineCache
            .getInstance()
            .put(ENGINE_ID, flutterEngine)
        super.configureFlutterEngine(flutterEngine)

        MeditoAndroidAudioServiceManager.setUp(flutterEngine.dartExecutor.binaryMessenger, this)
        MeditoWidgetManager.setUp(flutterEngine.dartExecutor.binaryMessenger, this)
        MeditoAppIconManager.setUp(flutterEngine.dartExecutor.binaryMessenger, AppIconManagerImpl(this))

        ApkUpdaterBridge(this, activityScope).attach(flutterEngine.dartExecutor.binaryMessenger)

        healthConnectBridge.attachLauncher(healthConnectPermissionLauncher)
        MeditoHealthConnectManager.setUp(flutterEngine.dartExecutor.binaryMessenger, healthConnectBridge)

        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "getInitial") {
                    val pending = initialShare
                    initialShare = null
                    if (pending == null) {
                        result.success(null)
                    } else {
                        activityScope.launch {
                            try {
                                result.success(pending.await())
                            } catch (e: Exception) {
                                println("❌ [Share] Could not read the shared content: ${e.message}")
                                result.success(null)
                            }
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
        }

        meditoAudioApi = MeditoAudioServiceCallbackApi(flutterEngine.dartExecutor.binaryMessenger)
        checkAndSendCompletionData()
        
        // Set up platform channel for widget updates
        val widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "medito.app/widget")
        widgetChannel.setMethodCallHandler { call, result ->
            if (call.method == "updateWidget") {
                // Run widget update asynchronously to avoid blocking the main thread
                // Note: sendBroadcast should not block, but running on IO thread as defensive measure
                activityScope.launch(Dispatchers.IO) {
                    try {
                        println("🔔 [Widget] Sending widget update broadcast on thread: ${Thread.currentThread().name}")
                        val intent = Intent("es.antonborri.home_widget.UPDATE_WIDGET")
                        intent.setPackage(packageName)
                        sendBroadcast(intent)
                        println("🔔 [Widget] Broadcast sent successfully")
                        withContext(Dispatchers.Main) {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        println("❌ [Widget] Error sending broadcast: ${e.message}")
                        withContext(Dispatchers.Main) {
                            result.error("UPDATE_FAILED", "Failed to send widget update broadcast", e.message)
                        }
                    }
                }
            } else if (call.method == "pinWidget") {
                // pinWidget is already handled by the MeditoWidgetManager interface
                result.notImplemented()
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        // Only the first creation carries a fresh share; a recreated activity
        // (rotation) still holds the old intent.
        if (savedInstanceState == null) {
            val startIntent = intent
            initialShare = activityScope.async(Dispatchers.IO) { readShare(startIntent) }
        }
        super.onCreate(savedInstanceState)
        
        val windowInsetsController = WindowCompat.getInsetsController(window, window.decorView)
        windowInsetsController?.let { controller ->
            controller.isAppearanceLightStatusBars = false
            controller.isAppearanceLightNavigationBars = false
        }
        
        createNotificationChannels()
    }

    override fun onResume() {
        super.onResume()
        checkAndSendCompletionData()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        activityScope.launch {
            val share = withContext(Dispatchers.IO) { readShare(intent) }
            if (share != null) {
                shareChannel?.invokeMethod("onShare", share)
            }
        }
    }

    /**
     * What an intent shares: text (a link) or audio, as a map for Dart. Audio
     * is copied into the cache because the sender's permission to read the
     * content URI ends with the share. Returns null for anything else.
     */
    @Suppress("DEPRECATION")
    private fun readShare(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        val type = intent.type ?: ""
        try {
            cleanSharedCache()
            when (intent.action) {
                Intent.ACTION_SEND -> {
                    if (type.startsWith("audio/")) {
                        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return null
                        val file = copySharedAudio(uri, type) ?: return null
                        return mapOf("files" to listOf(file))
                    }
                    // Some apps put a styled CharSequence here, not a String.
                    val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                    return if (text.isNullOrBlank()) null else mapOf("text" to text)
                }
                Intent.ACTION_SEND_MULTIPLE -> {
                    val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: return null
                    val files = uris.mapNotNull {
                        try {
                            copySharedAudio(it, type)
                        } catch (e: Exception) {
                            println("❌ [Share] Skipped one shared file: ${e.message}")
                            null
                        }
                    }
                    return if (files.isEmpty()) null else mapOf("files" to files)
                }
            }
        } catch (e: Exception) {
            println("❌ [Share] Could not read the shared content: ${e.message}")
        }
        return null
    }

    private fun copySharedAudio(uri: Uri, mimeType: String): Map<String, Any?>? {
        val name = sharedDisplayName(uri) ?: "shared-audio"
        val folder = File(cacheDir, SHARED_CACHE_DIR).apply { mkdirs() }
        val safeName = name.replace(Regex("[^A-Za-z0-9._ -]"), "_")
        val target = File(folder, "${System.currentTimeMillis()}-$safeName")
        val input = contentResolver.openInputStream(uri) ?: return null
        input.use { source ->
            target.outputStream().use { sink -> source.copyTo(sink) }
        }
        return mapOf(
            "path" to target.absolutePath,
            "name" to name,
            "mimeType" to mimeType,
            "size" to target.length(),
        )
    }

    private fun sharedDisplayName(uri: Uri): String? {
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val name = cursor.getString(0)
                    if (!name.isNullOrBlank()) return name
                }
            }
        }
        return uri.lastPathSegment
    }

    /** Shared copies the app never imported are not kept past a day. */
    private fun cleanSharedCache() {
        val cutoff = System.currentTimeMillis() - 24L * 60 * 60 * 1000
        File(cacheDir, SHARED_CACHE_DIR).listFiles()?.forEach { file ->
            if (file.lastModified() < cutoff) file.delete()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        activityJob.cancel()
    }

    private fun createNotificationChannels() {
        createAudioServiceNotificationChannel()
        createReminderNotificationChannel()
        createNewsNotificationChannel()
    }

    private fun createAudioServiceNotificationChannel() {
        val channelName = "Meditation audio"
        val importance = NotificationManager.IMPORTANCE_LOW
        val channel = NotificationChannel(AudioPlayerService.CHANNEL_ID, channelName, importance).apply {
            description = "Notification for media control of meditation audio"
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
        }

        val notificationManager: NotificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.createNotificationChannel(channel)
        
        println("Created audio service notification channel with ID: ${AudioPlayerService.CHANNEL_ID}")
    }

    private fun createNewsNotificationChannel() {
        val channelName = "News and Updates"
        val importance = NotificationManager.IMPORTANCE_HIGH
        val channel = NotificationChannel(NEWS_CHANNEL_ID, channelName, importance).apply {
            description = "Stay up-to-date with the latest news and updates from Meditejo"
        }

        val notificationManager: NotificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.createNotificationChannel(channel)
    }

    private fun createReminderNotificationChannel() {
        val channelName = "Reminders"
        val importance = NotificationManager.IMPORTANCE_HIGH
        val channel = NotificationChannel(REMINDER_CHANNEL_ID, channelName, importance).apply {
            description = "Notification for meditation reminders"
        }

        val notificationManager: NotificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.createNotificationChannel(channel)
    }

    override fun startService() {
        // Ensure notification channel exists before starting service
        createAudioServiceNotificationChannel()
        val intent = Intent(this, AudioPlayerService::class.java)
        
        try {
            // Use the appropriate method based on Android version
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(this, intent)
            } else {
                startService(intent)
            }
            // Log successful service start attempt
            println("🔊 Service start requested")
        } catch (e: Exception) {
            println("❌ Error starting service: ${e.message}")
            e.printStackTrace()
        }
    }

    override fun isServiceReady(callback: (Result<Boolean>) -> Unit) {
        println("🔊 [Native] isServiceReady called")
        val intent = Intent(this, AudioPlayerService::class.java)
        intent.action = AudioPlayerService.ACTION_BIND_SERVICE
        
        // Add a timeout handler
        val timeoutHandler = Handler(Looper.getMainLooper())
        val timeoutRunnable = Runnable {
            println("❌ [Native] Service binding timeout occurred")
            try {
                callback(Result.success(false))
            } catch (e: Exception) {
                println("❌ [Native] Error handling timeout: ${e.message}")
            }
        }
        // Set a 5-second timeout
        timeoutHandler.postDelayed(timeoutRunnable, 5000)
        
        val serviceConnection = object : android.content.ServiceConnection {
            override fun onServiceConnected(name: android.content.ComponentName?, service: android.os.IBinder?) {
                // Cancel the timeout since we connected
                timeoutHandler.removeCallbacks(timeoutRunnable)
                
                println("🔊 [Native] onServiceConnected called")
                try {
                    val binder = service as? AudioPlayerService.LocalBinder
                    val audioService = binder?.service
                    
                    if (audioService != null) {
                        println("🔊 [Native] Service connected, calling audioService.checkReadiness")
                        audioService.checkReadiness { isReady ->
                            println("🔊 [Native] audioService.checkReadiness callback: isReady = $isReady")
                            callback(Result.success(isReady))
                            println("🔊 [Native] Unbinding service after readiness check")
                            try {
                                unbindService(this)
                            } catch (e: Exception) {
                                println("❌ [Native] Error unbinding service: ${e.message}")
                            }
                        }
                    } else {
                        println("❌ [Native] Service connected but binder is null or wrong type")
                        callback(Result.success(false))
                        println("🔊 [Native] Unbinding service due to binder issue")
                        try {
                            unbindService(this)
                        } catch (e: Exception) {
                            println("❌ [Native] Error unbinding service: ${e.message}")
                        }
                    }
                } catch (e: Exception) {
                    println("❌ [Native] Error in onServiceConnected: ${e.message}")
                    callback(Result.success(false))
                    try {
                        println("🔊 [Native] Unbinding service due to error in onServiceConnected")
                        unbindService(this)
                    } catch (e: Exception) {
                        println("❌ [Native] Error unbinding service: ${e.message}")
                    }
                }
            }

            override fun onServiceDisconnected(name: android.content.ComponentName?) {
                // Cancel timeout if disconnected
                timeoutHandler.removeCallbacks(timeoutRunnable)
                
                println("❌ [Native] onServiceDisconnected called")
                callback(Result.success(false))
            }
        }
        
        try {
            println("🔊 [Native] Attempting to bind service...")
            val bound = bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
            if (!bound) {
                // Cancel the timeout since binding failed immediately
                timeoutHandler.removeCallbacks(timeoutRunnable)
                
                println("❌ [Native] bindService returned false")
                callback(Result.success(false))
            }
            else {
                println("🔊 [Native] bindService returned true")
                // Keep timeout handler running as we're waiting for connection
            }
        } catch (e: Exception) {
            // Cancel the timeout since there was an exception
            timeoutHandler.removeCallbacks(timeoutRunnable)
            
            println("❌ [Native] Error binding to service: ${e.message}")
            callback(Result.success(false))
        }
    }

    override fun pinWidget(widgetType: String, callback: (Result<Boolean>) -> Unit) {
        activityScope.launch(Dispatchers.Main) {
            try {
                val manager = GlanceAppWidgetManager(this@MainActivity)
                val receiver = when (widgetType) {
                    "consistency" -> ConsistencyWidgetReceiver::class.java
                    else -> MeditationWidgetReceiver::class.java
                }
                val widget = when (widgetType) {
                    "consistency" -> ConsistencyWidget()
                    else -> MeditationWidget()
                }
                
                val success = manager.requestPinGlanceAppWidget(
                    receiver = receiver,
                    preview = widget,
                    previewSize = DpSize(245.dp, 115.dp)
                )
                callback(Result.success(success))
            } catch (e: Exception) {
                println("Error pinning widget: ${e.message}")
                callback(Result.failure(e))
            }
        }
    }

    private fun checkAndSendCompletionData() {
        activityScope.launch(Dispatchers.IO) {
            val completionData = SharedPreferencesManager.getCompletionData(this@MainActivity)
            if (completionData != null) {
                try {
                    withContext(Dispatchers.Main) {
                        meditoAudioApi?.handleCompletedTrack(completionData) {
                            if (it.getOrNull() == true) {
                                activityScope.launch(Dispatchers.IO) {
                                    SharedPreferencesManager.clearCompletionData(this@MainActivity)
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    println("Error parsing completion data: ${e.message}")
                }
            }

            val pendingRepeats = SharedPreferencesManager.getPendingRepeats(this@MainActivity)
            if (pendingRepeats.isNotEmpty()) {
                withContext(Dispatchers.Main) {
                    pendingRepeats.forEach { repeat ->
                        meditoAudioApi?.handleRepeatPlaythrough(repeat) {
                            if (it.getOrNull() == true) {
                                activityScope.launch(Dispatchers.IO) {
                                    SharedPreferencesManager.removePendingRepeat(this@MainActivity, repeat)
                                }
                            }
                        }
                    }
                }
            }
        }
    }


    companion object {
        const val SHARE_CHANNEL = "meditejo/share"
        const val SHARED_CACHE_DIR = "shared_audio"
        const val ENGINE_ID = "medito_flutter_engine"
        const val REMINDER_CHANNEL_ID = "medito_reminder_channel"
        const val NEWS_CHANNEL_ID = "medito_news_channel"
    }
}
