package meditofoundation.medito.youtube

import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.SocketPolicy
import okio.Buffer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.SocketTimeoutException
import java.util.concurrent.TimeUnit
import java.util.zip.GZIPOutputStream

class YoutubeDownloaderTest {
    private lateinit var server: MockWebServer
    private lateinit var base: String

    @Before
    fun start() {
        // Android's unit-test compiler omits the JDK-only com.sun HTTP server.
        // MockWebServer exercises the same real socket paths on both routes.
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when (request.path) {
                "/ok" -> MockResponse()
                    .addHeader("Content-Type", "text/plain; charset=utf-8")
                    .addHeader("X-Seen-Agent", request.getHeader("User-Agent") ?: "")
                    .addHeader("X-Seen-Custom", request.getHeader("X-Custom") ?: "")
                    .setBody("héllo")
                "/echo" -> MockResponse().setBody(request.body.readUtf8())
                "/limited" -> MockResponse().setResponseCode(429)
                "/missing" -> MockResponse().setResponseCode(404).setBody("nope")
                "/gzip" -> {
                    val packed = ByteArrayOutputStream().also { out ->
                        GZIPOutputStream(out).use { it.write("zipped text".toByteArray()) }
                    }.toByteArray()
                    MockResponse().addHeader("Content-Encoding", "gzip").setBody(Buffer().write(packed))
                }
                "/big" -> MockResponse().setBody("a".repeat(512 * 1024))
                "/hang" -> MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE)
                "/drip" -> MockResponse().setBody("x".repeat(100))
                    .throttleBody(1, 50, TimeUnit.MILLISECONDS)
                "/redirect" -> MockResponse().setResponseCode(302).addHeader("Location", "$base/ok")
                else -> MockResponse().setResponseCode(404)
            }
        }
        server.start()
        base = server.url("/").toString().removeSuffix("/")
    }

    @After
    fun stop() = server.shutdown()

    private fun downloader(
        connect: Int = 2_000, read: Int = 2_000, deadline: Long = 5_000, max: Int = 64 * 1024,
    ) = YoutubeDownloader(connect, read, deadline, max, requireHttps = false)

    @Test
    fun getsBodyHeadersAndFinalUrl() {
        val response = downloader().execute(Request.newBuilder().get("$base/ok").setHeader("X-Custom", "yes").build())
        assertEquals(200, response.responseCode())
        assertEquals("héllo", response.responseBody())
        assertEquals(YoutubeDownloader.USER_AGENT, response.getHeader("X-Seen-Agent"))
        assertEquals("yes", response.getHeader("x-seen-custom"))
        assertEquals("$base/ok", response.latestUrl())
    }

    @Test
    fun postsTheBody() {
        val response = downloader().execute(Request.newBuilder().post("$base/echo", "{\"a\":1}".toByteArray()).build())
        assertEquals("{\"a\":1}", response.responseBody())
    }

    @Test
    fun followsRedirectsAndReportsTheLastUrl() {
        val response = downloader().execute(Request.newBuilder().get("$base/redirect").build())
        assertEquals("héllo", response.responseBody())
        assertEquals("$base/ok", response.latestUrl())
    }

    @Test
    fun errorStatusesCarryTheirBody() {
        val response = downloader().execute(Request.newBuilder().get("$base/missing").build())
        assertEquals(404, response.responseCode())
        assertEquals("nope", response.responseBody())
    }

    @Test
    fun tooManyRequestsIsAReCaptcha() {
        try {
            downloader().execute(Request.newBuilder().get("$base/limited").build())
            fail("expected ReCaptchaException")
        } catch (e: ReCaptchaException) {
            assertEquals("rate-limited", YoutubeFailure.from(e).code)
        }
    }

    @Test
    fun gzipBodiesAreDecoded() {
        val response = downloader().execute(Request.newBuilder().get("$base/gzip").build())
        assertEquals("zipped text", response.responseBody())
    }

    @Test
    fun anOversizedBodyIsRefused() {
        try {
            downloader(max = 100 * 1024).execute(Request.newBuilder().get("$base/big").build())
            fail("expected IOException")
        } catch (e: IOException) {
            assertEquals("network", YoutubeFailure.from(e).code)
        }
    }

    @Test
    fun aServerThatNeverAnswersTimesOutOnRead() {
        val started = System.nanoTime()
        try {
            downloader(read = 300).execute(Request.newBuilder().get("$base/hang").build())
            fail("expected SocketTimeoutException")
        } catch (e: SocketTimeoutException) {
            assertTrue(System.nanoTime() - started < 3_000_000_000L)
        }
    }

    @Test
    fun aSlowDripStopsAtTheOverallDeadline() {
        val started = System.nanoTime()
        try {
            downloader(read = 1_000, deadline = 400).execute(Request.newBuilder().get("$base/drip").build())
            fail("expected IOException")
        } catch (e: IOException) {
            assertTrue(System.nanoTime() - started < 3_000_000_000L)
        }
    }

    @Test
    fun cleartextIsRefusedByDefault() {
        try {
            YoutubeDownloader().execute(Request.newBuilder().get("$base/ok").build())
            fail("expected IOException")
        } catch (e: IOException) {
            assertTrue(e.message!!.contains("https"))
        }
    }
}
