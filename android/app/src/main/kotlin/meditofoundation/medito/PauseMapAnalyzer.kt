package meditofoundation.medito

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** What reading a recording found: its length, and its quiet stretches. */
internal data class PauseMap(val durationMs: Long, val silences: List<SilentSpan>)

/** The recording is online and the connection is metered: it is not fetched for this. */
internal class MeteredNetworkException : Exception("Metered network")

/** The analysis was cancelled (a newer one began, or the session ended). */
internal class AnalysisCancelledException : Exception("Cancelled")

/**
 * Decodes a recording once and reports where it is quiet: MediaExtractor and
 * MediaCodec to PCM, the level of each 100 ms window, then [SilenceDetector].
 * Runs on the calling thread (never the main one) and reads the whole file,
 * which is why a recording that is not already on the phone is read only on an
 * unmetered connection.
 */
internal object PauseMapAnalyzer {
    private const val TAG = "PauseMapAnalyzer"
    private const val TIMEOUT_US = 10_000L

    fun analyze(context: Context, source: String, isCancelled: () -> Boolean): PauseMap {
        val online = source.startsWith("http://") || source.startsWith("https://")
        if (online && isMetered(context)) throw MeteredNetworkException()

        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            when {
                online -> extractor.setDataSource(source)
                source.startsWith("content://") -> extractor.setDataSource(context, Uri.parse(source), null)
                source.startsWith("file://") -> extractor.setDataSource(Uri.parse(source).path ?: source)
                else -> extractor.setDataSource(source)
            }
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: throw IllegalStateException("No audio track")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            codec = MediaCodec.createDecoderByType(mime).also {
                it.configure(format, null, null, 0)
                it.start()
            }
            return decode(extractor, codec, format, isCancelled)
        } finally {
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            extractor.release()
        }
    }

    private fun decode(
        extractor: MediaExtractor,
        codec: MediaCodec,
        inputFormat: MediaFormat,
        isCancelled: () -> Boolean,
    ): PauseMap {
        var sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        var floatPcm = false

        val levels = ArrayList<Double>()
        var windowSamples = windowSize(sampleRate, channels)
        var inWindow = 0L
        var sumSquares = 0.0
        var totalFrames = 0L

        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        while (!outputDone) {
            if (isCancelled()) throw AnalysisCancelledException()
            if (!inputDone) {
                val index = codec.dequeueInputBuffer(TIMEOUT_US)
                if (index >= 0) {
                    val buffer = codec.getInputBuffer(index)!!
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) {
                        codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val out = codec.dequeueOutputBuffer(info, TIMEOUT_US)
            when {
                out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val f = codec.outputFormat
                    sampleRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    val encoding = if (f.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                        f.getInteger(MediaFormat.KEY_PCM_ENCODING)
                    } else AudioFormat.ENCODING_PCM_16BIT
                    // Anything else would read as noise and could put a hold in speech.
                    if (encoding != AudioFormat.ENCODING_PCM_16BIT && encoding != AudioFormat.ENCODING_PCM_FLOAT) {
                        throw IllegalStateException("Unsupported PCM encoding $encoding")
                    }
                    floatPcm = encoding == AudioFormat.ENCODING_PCM_FLOAT
                    windowSamples = windowSize(sampleRate, channels)
                }
                out >= 0 -> {
                    val buffer = codec.getOutputBuffer(out)
                    if (buffer != null && info.size > 0) {
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        buffer.order(ByteOrder.nativeOrder())
                        if (floatPcm) {
                            val samples = buffer.asFloatBuffer()
                            while (samples.hasRemaining()) {
                                val v = samples.get().toDouble()
                                sumSquares += v * v
                                if (++inWindow >= windowSamples) { levels.add(level(sumSquares, inWindow)); inWindow = 0; sumSquares = 0.0 }
                            }
                            totalFrames += info.size / (4L * channels)
                        } else {
                            val samples = buffer.asShortBuffer()
                            while (samples.hasRemaining()) {
                                val v = samples.get() / 32768.0
                                sumSquares += v * v
                                if (++inWindow >= windowSamples) { levels.add(level(sumSquares, inWindow)); inWindow = 0; sumSquares = 0.0 }
                            }
                            totalFrames += info.size / (2L * channels)
                        }
                    }
                    codec.releaseOutputBuffer(out, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                }
            }
        }
        val durationMs = totalFrames * 1000L / sampleRate
        return PauseMap(durationMs, SilenceDetector.findSpans(levels.toDoubleArray()))
    }

    private fun windowSize(sampleRate: Int, channels: Int): Long =
        (sampleRate.toLong() * channels * SilenceDetector.WINDOW_MS / 1000L).coerceAtLeast(1L)

    private fun level(sumSquares: Double, count: Long): Double =
        SilenceDetector.db(SilenceDetector.rms(sumSquares, count))

    private fun isMetered(context: Context): Boolean {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return true
        return !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    }
}

/**
 * `meditejo/pauses`: the Dart side of the pause map.
 *
 *  - `analyze({source})`  read the recording at [source] (a path, file:// or content:// URI, or
 *                         an http(s) URL, fetched only on an unmetered connection) and return
 *                         `{durationMs, spans: [{start, end}]}` of its quiet stretches.
 *                         Errors: `METERED` (not fetched), `CANCELLED`, `ANALYSIS_FAILED`.
 *  - `cancel`             stop the analysis under way, if any.
 *
 * One analysis runs at a time, on a background thread; a new one cancels the last.
 */
internal object PauseMapChannel {
    const val NAME = "meditejo/pauses"
    private const val TAG = "PauseMapChannel"

    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread {
            Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
            r.run()
        }.apply { name = "pause-map" }
    }
    private val generation = AtomicInteger(0)
    private val main = Handler(Looper.getMainLooper())

    fun attach(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "analyze" -> {
                    val source = (call.arguments as? Map<*, *>)?.get("source") as? String
                    if (source.isNullOrBlank()) {
                        result.error("ANALYSIS_FAILED", "No source", null)
                        return@setMethodCallHandler
                    }
                    val mine = generation.incrementAndGet()
                    executor.execute {
                        try {
                            val map = PauseMapAnalyzer.analyze(app, source) { generation.get() != mine }
                            val payload = mapOf(
                                "durationMs" to map.durationMs,
                                "spans" to map.silences.map { mapOf("start" to it.startMs, "end" to it.endMs) },
                            )
                            main.post { result.success(payload) }
                        } catch (e: MeteredNetworkException) {
                            main.post { result.error("METERED", "Not fetching on a metered connection", null) }
                        } catch (e: AnalysisCancelledException) {
                            main.post { result.error("CANCELLED", "Cancelled", null) }
                        } catch (e: Throwable) {
                            Log.w(TAG, "Analysis failed: ${e.message}")
                            main.post { result.error("ANALYSIS_FAILED", e.message, null) }
                        }
                    }
                }
                "cancel" -> { generation.incrementAndGet(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
}
