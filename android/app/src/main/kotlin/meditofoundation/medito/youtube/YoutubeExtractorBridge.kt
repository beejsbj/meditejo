package meditofoundation.medito.youtube

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import meditofoundation.medito.pigeon.YoutubeAudioStream
import meditofoundation.medito.pigeon.YoutubeExtractorApi
import meditofoundation.medito.pigeon.YoutubeFlutterError
import meditofoundation.medito.pigeon.YoutubePlaylist
import meditofoundation.medito.pigeon.YoutubeVideo

/**
 * The Android side of `YoutubeExtractorApi`: Dart hands over a link or video id
 * and gets metadata or a fresh audio stream back. Work runs on the runner's
 * threads; replies go out on the platform thread. Failures reach Dart as a
 * [YoutubeFlutterError] holding only a code and a safe sentence.
 */
class YoutubeExtractorBridge(
    private val backend: YoutubeBackend,
    private val runner: YoutubeWorkRunner,
) : YoutubeExtractorApi {

    private var messenger: BinaryMessenger? = null

    /** Starts answering Dart on [binaryMessenger]. */
    fun attach(binaryMessenger: BinaryMessenger) {
        messenger = binaryMessenger
        YoutubeExtractorApi.setUp(binaryMessenger, this)
    }

    /** Stops answering, interrupts running work and releases the threads. */
    fun dispose() {
        messenger?.let { YoutubeExtractorApi.setUp(it, null) }
        messenger = null
        runner.dispose()
    }

    override fun resolvePlaylist(url: String, callback: (Result<YoutubePlaylist>) -> Unit) {
        val link = YoutubeSelection.playlistUrl(url)
        run(PLAYLIST_TIMEOUT_MS, callback) {
            backend.playlist(link ?: throw YoutubeFailure.invalidLink())
        }
    }

    override fun resolveVideo(urlOrId: String, callback: (Result<YoutubeVideo>) -> Unit) {
        val link = YoutubeSelection.videoUrl(urlOrId)
        run(VIDEO_TIMEOUT_MS, callback) {
            backend.video(link ?: throw YoutubeFailure.invalidLink())
        }
    }

    override fun resolveAudioStream(videoId: String, callback: (Result<YoutubeAudioStream>) -> Unit) {
        val link = YoutubeSelection.videoUrl(videoId)
        run(STREAM_TIMEOUT_MS, callback) {
            backend.audioStream(link ?: throw YoutubeFailure.invalidLink())
        }
    }

    private fun <T> run(timeoutMs: Long, callback: (Result<T>) -> Unit, work: () -> T) {
        runner.run(timeoutMs, work) { result ->
            callback(result.fold({ Result.success(it) }, { Result.failure<T>(toFlutterError(it)) }))
        }
    }

    companion object {
        // Overall limits. Reading a playlist is many requests in a row; a stream
        // may first fetch and run YouTube's player script.
        const val PLAYLIST_TIMEOUT_MS = 120_000L
        const val VIDEO_TIMEOUT_MS = 45_000L
        const val STREAM_TIMEOUT_MS = 60_000L

        /** The bridge as the app runs it: real extractor, replies on the platform thread. */
        fun create(): YoutubeExtractorBridge {
            val main = Handler(Looper.getMainLooper())
            return YoutubeExtractorBridge(NewPipeYoutubeBackend(), YoutubeWorkRunner(deliver = { main.post(it) }))
        }

        internal fun toFlutterError(error: Throwable): YoutubeFlutterError {
            val failure = YoutubeFailure.from(error)
            return YoutubeFlutterError(failure.code, failure.message ?: "", null)
        }
    }
}
