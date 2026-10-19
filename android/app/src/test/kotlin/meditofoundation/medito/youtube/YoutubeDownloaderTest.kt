package meditofoundation.medito.youtube

import com.sun.net.httpserver.HttpServer
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
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import java.util.zip.GZIPOutputStream

class YoutubeDownloaderTest {
    private lateinit var server: HttpServer
    private lateinit var base: String
    private val release = java.util.concurrent.CountDownLatch(1)

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0)
        server.executor = java.util.concurrent.Executors.newCachedThreadPool { Thread(it).apply { isDaemon = true } }
        server.createContext("/ok") { ex ->
            val bytes = "héllo".toByteArray(Charsets.UTF_8)
            ex.responseHeaders.add("Content-Type", "text/plain; charset=utf-8")
            ex.responseHeaders.add("X-Seen-Agent", ex.requestHeaders.getFirst("User-Agent") ?: "")
            ex.responseHeaders.add("X-Seen-Custom", ex.requestHeaders.getFirst("X-Custom") ?: "")
            ex.sendResponseHeaders(200, bytes.size.toLong())
            ex.responseBody.use { it.write(bytes) }
        }
        server.createContext("/echo") { ex ->
            val body = ex.requestBody.readBytes()
            ex.sendResponseHeaders(200, body.size.toLong())
            ex.responseBody.use { it.write(body) }
        }
        server.createContext("/limited") { ex ->
            ex.sendResponseHeaders(429, -1)
            ex.close()
        }
        server.createContext("/missing") { ex ->
            val bytes = "nope".toByteArray()
            ex.sendResponseHeaders(404, bytes.size.toLong())
            ex.responseBody.use { it.write(bytes) }
        }
        server.createContext("/gzip") { ex ->
            val packed = ByteArrayOutputStream().also { out -> GZIPOutputStream(out).use { it.write("zipped text".toByteArray()) } }.toByteArray()
            ex.responseHeaders.add("Content-Encoding", "gzip")
            ex.sendResponseHeaders(200, packed.size.toLong())
            ex.responseBody.use { it.write(packed) }
        }
        server.createContext("/big") { ex ->
            ex.sendResponseHeaders(200, 0)
            ex.responseBody.use { out -> val chunk = ByteArray(8192) { 'a'.code.toByte() }; repeat(64) { out.write(chunk) } }
        }
        server.createContext("/hang") { ex ->
            release.await()
            ex.close()
        }
        server.createContext("/drip") { ex ->
            ex.sendResponseHeaders(200, 0)
            try {
                ex.responseBody.use { out -> repeat(100) { out.write('x'.code); out.flush(); Thread.sleep(50) } }
            } catch (e: IOException) {
                // the client gave up
            }
        }
        server.createContext("/redirect") { ex ->
            ex.responseHeaders.add("Location", "$base/ok")
            ex.sendResponseHeaders(302, -1)
            ex.close()
        }
        server.start()
        base = "http://127.0.0.1:${server.address.port}"
    }

    @After
    fun stop() {
        release.countDown()
        server.stop(0)
    }

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
            assertEquals("network", YoutubeFailure.from(e).code)
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
