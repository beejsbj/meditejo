package meditofoundation.medito.youtube

import meditofoundation.medito.pigeon.YoutubeAudioStream
import meditofoundation.medito.pigeon.YoutubeFlutterError
import meditofoundation.medito.pigeon.YoutubePlaylist
import meditofoundation.medito.pigeon.YoutubeVideo
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.schabi.newpipe.extractor.exceptions.AgeRestrictedContentException
import org.schabi.newpipe.extractor.exceptions.PrivateContentException
import java.io.IOException
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

class YoutubeExtractorBridgeTest {
    private val runner = YoutubeWorkRunner(deliver = { it.run() })

    @After
    fun tearDown() = runner.dispose()

    private class FakeBackend(
        val onPlaylist: (String) -> YoutubePlaylist = { error("unexpected") },
        val onVideo: (String) -> YoutubeVideo = { error("unexpected") },
        val onStream: (String) -> YoutubeAudioStream = { error("unexpected") },
    ) : YoutubeBackend {
        val seen = mutableListOf<String>()
        override fun playlist(url: String) = onPlaylist(url).also { seen += url }
        override fun video(url: String) = onVideo(url).also { seen += url }
        override fun audioStream(url: String) = onStream(url).also { seen += url }
    }

    private fun <T> await(call: ((Result<T>) -> Unit) -> Unit): Result<T> {
        val q = LinkedBlockingQueue<Result<T>>()
        call { q.add(it) }
        return q.poll(10, TimeUnit.SECONDS) ?: error("no reply")
    }

    private val video = YoutubeVideo("dQw4w9WgXcQ", "Title", "Someone", 212, "https://i.example/t.jpg", "About")
    private val stream = YoutubeAudioStream("https://r.example/a?expire=1787000000", "audio/webm", 160_000, 1_787_000_000_000)

    @Test
    fun resolvesAVideoFromABareId() {
        val backend = FakeBackend(onVideo = { video })
        val result = await<YoutubeVideo> { YoutubeExtractorBridge(backend, runner).resolveVideo("dQw4w9WgXcQ", it) }
        assertEquals(video, result.getOrThrow())
        assertEquals(listOf("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), backend.seen)
    }

    @Test
    fun resolvesAPlaylistAndAStream() {
        val playlist = YoutubePlaylist("T", "U", "https://i.example/p.jpg", emptyList())
        val backend = FakeBackend(onPlaylist = { playlist }, onStream = { stream })
        val bridge = YoutubeExtractorBridge(backend, runner)
        assertEquals(playlist, await<YoutubePlaylist> { bridge.resolvePlaylist("PLND1JCRq8VujAHvDA482SXF1cJTQrwlx3", it) }.getOrThrow())
        assertEquals(stream, await<YoutubeAudioStream> { bridge.resolveAudioStream("dQw4w9WgXcQ", it) }.getOrThrow())
        assertEquals(
            listOf("https://www.youtube.com/playlist?list=PLND1JCRq8VujAHvDA482SXF1cJTQrwlx3", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
            backend.seen,
        )
    }

    private fun errorOf(result: Result<*>): YoutubeFlutterError = result.exceptionOrNull() as YoutubeFlutterError

    @Test
    fun aBadLinkIsAnUnavailableErrorAndNeverReachesTheBackend() {
        val backend = FakeBackend()
        val bridge = YoutubeExtractorBridge(backend, runner)
        val error = errorOf(await<YoutubeVideo> { bridge.resolveVideo("https://vimeo.com/1", it) })
        assertEquals("unavailable", error.code)
        assertTrue(backend.seen.isEmpty())
        assertEquals("unavailable", errorOf(await<YoutubePlaylist> { bridge.resolvePlaylist("nonsense", it) }).code)
        assertEquals("unavailable", errorOf(await<YoutubeAudioStream> { bridge.resolveAudioStream("", it) }).code)
    }

    @Test
    fun extractorFailuresBecomeCodedSafeErrors() {
        val secret = "https://rr1.googlevideo.com/videoplayback?key=SECRET"
        for ((thrown, code) in listOf(
            AgeRestrictedContentException("age $secret") to "age-restricted",
            PrivateContentException("private $secret") to "private",
            IOException("reset $secret") to "network",
            IllegalStateException(secret) to "unavailable",
        )) {
            val bridge = YoutubeExtractorBridge(FakeBackend(onStream = { throw thrown }), runner)
            val error = errorOf(await<YoutubeAudioStream> { bridge.resolveAudioStream("dQw4w9WgXcQ", it) })
            assertEquals(code, error.code)
            assertEquals(null, error.details)
            assertTrue(!(error.message ?: "").contains("SECRET") && !(error.message ?: "").contains("http"))
        }
    }
}
