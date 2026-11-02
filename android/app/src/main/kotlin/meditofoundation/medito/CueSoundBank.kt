package meditofoundation.medito

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaMetadataRetriever
import android.media.SoundPool
import android.os.SystemClock
import android.util.Log
import io.flutter.FlutterInjector
import java.io.File

/**
 * Cue sounds decoded once into a SoundPool, so a beat or a bell never starts a
 * decoder. A sound is a Flutter asset path (`assets/audio/...`) or, for a bell
 * the user made, an absolute path to a WAV in the app's own storage.
 */
internal class CueSoundBank(private val context: Context) {
    private class Entry(val soundId: Int, val tailMs: Long) {
        @Volatile var loaded = false
        var pendingVolume = -1f
        var pendingAt = 0L
    }

    private val pool: SoundPool = SoundPool.Builder()
        .setMaxStreams(6)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        .build()
    private val entries = HashMap<String, Entry>()
    private val byId = HashMap<Int, Entry>()

    init {
        pool.setOnLoadCompleteListener { _, id, status ->
            val entry = byId[id] ?: return@setOnLoadCompleteListener
            if (status != 0) { Log.e(TAG, "Cue sound $id failed to load ($status)"); return@setOnLoadCompleteListener }
            entry.loaded = true
            // Asked for before it finished decoding: still worth playing if it is fresh.
            val volume = entry.pendingVolume
            if (volume >= 0f && SystemClock.elapsedRealtime() - entry.pendingAt < LATE_PLAY_MS) {
                pool.play(id, volume, volume, 1, 0, 1f)
            }
            entry.pendingVolume = -1f
        }
    }

    /** Starts decoding [asset] now. Safe to call again for the same path. */
    fun preload(asset: String?) {
        if (asset == null || entries.containsKey(asset)) return
        try {
            val file = openAsset(asset)
            val tail = durationOf(file)
            val id = if (file.fd != null) {
                pool.load(file.fd, 1).also { try { file.fd.close() } catch (_: Exception) {} }
            } else pool.load(file.path, 1)
            val entry = Entry(id, tail)
            entries[asset] = entry
            byId[id] = entry
        } catch (e: Exception) {
            Log.e(TAG, "Cue sound $asset is unavailable: ${e.message}")
        }
    }

    /** Plays [asset] at [volume] (0..1). Returns false when it has no sound to play. */
    fun play(asset: String?, volume: Double): Boolean {
        val entry = asset?.let { entries[it] } ?: return false
        val v = volume.coerceIn(0.0, 1.0).toFloat()
        if (!entry.loaded) {
            entry.pendingVolume = v
            entry.pendingAt = SystemClock.elapsedRealtime()
            return true
        }
        return pool.play(entry.soundId, v, v, 1, 0, 1f) != 0
    }

    /** Length of the sound, for holding the service open until the last bell has rung out. */
    fun tailMs(asset: String?): Long = asset?.let { entries[it]?.tailMs } ?: 0L

    fun pauseAll() = pool.autoPause()
    fun resumeAll() = pool.autoResume()

    fun release() {
        try { pool.release() } catch (_: Exception) {}
        entries.clear()
        byId.clear()
    }

    private class Opened(val fd: android.content.res.AssetFileDescriptor?, val path: String?)

    private fun openAsset(asset: String): Opened {
        if (isFilePath(asset)) {
            val file = resolveFile(asset, context.dataDir)
                ?: throw IllegalArgumentException("not a usable bell file")
            return Opened(null, file.absolutePath)
        }
        val key = try {
            FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
        } catch (_: Exception) {
            fallbackKey(asset)
        }
        try {
            return Opened(context.assets.openFd(key), null)
        } catch (_: Exception) {
            // Compressed in the APK: unpack once to the cache, where it has a path.
            val dir = File(context.cacheDir, "cue_sounds").apply { mkdirs() }
            val out = File(dir, asset.replace('/', '_'))
            if (!out.exists() || out.length() == 0L) {
                context.assets.open(key).use { input -> out.outputStream().use { input.copyTo(it) } }
            }
            return Opened(null, out.absolutePath)
        }
    }

    private fun durationOf(file: Opened): Long {
        val retriever = MediaMetadataRetriever()
        return try {
            if (file.fd != null) retriever.setDataSource(file.fd.fileDescriptor, file.fd.startOffset, file.fd.length)
            else retriever.setDataSource(file.path)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: DEFAULT_TAIL_MS
        } catch (_: Exception) {
            DEFAULT_TAIL_MS
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }
    }

    companion object {
        /** Where an asset sits in the APK when the Flutter loader cannot be asked. */
        internal fun fallbackKey(asset: String): String = "flutter_assets/$asset"

        /** A sound given as a file path (a bell the user made) rather than a Flutter asset. */
        internal fun isFilePath(sound: String): Boolean = sound.startsWith("/")

        /** SoundPool decodes a sound whole and refuses one over about 1 MiB. */
        internal const val MAX_FILE_BYTES = 1L shl 20

        /**
         * The file behind [path], or null when it is not a plain WAV-sized file
         * inside [dataDir] (the app's own storage): a path that came through
         * the cue config is never trusted to point anywhere else.
         */
        internal fun resolveFile(path: String, dataDir: File): File? = try {
            val file = File(path).canonicalFile
            val root = dataDir.canonicalFile
            if (file.isFile && file.length() in 1 until MAX_FILE_BYTES &&
                file.path.startsWith(root.path + File.separator)) file else null
        } catch (_: Exception) {
            null
        }

        private const val TAG = "CueSoundBank"
        private const val LATE_PLAY_MS = 1500L
        private const val DEFAULT_TAIL_MS = 8000L
    }
}
