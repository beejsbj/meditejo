package meditofoundation.medito.youtube

import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.InterruptedIOException
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.Charset
import java.nio.charset.StandardCharsets
import java.util.zip.GZIPInputStream

/**
 * NewPipeExtractor's window to the network, over the platform's own
 * HttpURLConnection. Every request is bounded: it connects within
 * [connectTimeoutMs], each read waits at most [readTimeoutMs], and the whole
 * exchange stops at [requestDeadlineMs] and [maxBodyBytes].
 */
class YoutubeDownloader(
    private val connectTimeoutMs: Int = 10_000,
    private val readTimeoutMs: Int = 15_000,
    private val requestDeadlineMs: Long = 40_000,
    private val maxBodyBytes: Int = 16 * 1024 * 1024,
    private val requireHttps: Boolean = true,
) : Downloader() {

    @Throws(IOException::class, ReCaptchaException::class)
    override fun execute(request: Request): Response {
        val url = URL(request.url())
        if (requireHttps && url.protocol != "https") {
            throw IOException("Refusing a request that is not https")
        }
        val deadline = System.nanoTime() + requestDeadlineMs * 1_000_000L

        val connection = url.openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = connectTimeoutMs
            connection.readTimeout = readTimeoutMs
            connection.useCaches = false
            connection.instanceFollowRedirects = true
            connection.requestMethod = request.httpMethod()
            connection.setRequestProperty("User-Agent", USER_AGENT)
            for ((name, values) in request.headers()) {
                // The platform negotiates and undoes gzip itself unless told otherwise.
                if (name.equals("Accept-Encoding", ignoreCase = true)) continue
                values.forEachIndexed { index, value ->
                    if (index == 0) connection.setRequestProperty(name, value)
                    else connection.addRequestProperty(name, value)
                }
            }

            val body = request.dataToSend()
            if (body != null) {
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(body.size)
                connection.outputStream.use { it.write(body) }
            }

            val code = connection.responseCode
            if (code == 429) {
                throw ReCaptchaException("reCAPTCHA challenge requested", request.url())
            }
            val stream = if (code >= 400) connection.errorStream else connection.inputStream
            val text = stream?.use { read(it, connection, deadline) } ?: ""

            val headers = connection.headerFields
                .filterKeys { it != null }
                .mapValues { it.value.toList() }
            return Response(code, connection.responseMessage ?: "", headers, text, connection.url.toString())
        } finally {
            connection.disconnect()
        }
    }

    private fun read(source: InputStream, connection: HttpURLConnection, deadline: Long): String {
        val gzipped = connection.contentEncoding?.contains("gzip", ignoreCase = true) == true
        val input = if (gzipped) GZIPInputStream(source) else source
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(16 * 1024)
        while (true) {
            if (Thread.currentThread().isInterrupted) throw InterruptedIOException("Interrupted")
            if (System.nanoTime() > deadline) throw InterruptedIOException("Took too long")
            val count = input.read(buffer)
            if (count < 0) break
            if (out.size() + count > maxBodyBytes) throw IOException("Response too large")
            out.write(buffer, 0, count)
        }
        return String(out.toByteArray(), charsetOf(connection.contentType))
    }

    private fun charsetOf(contentType: String?): Charset {
        val name = contentType
            ?.split(';')
            ?.map { it.trim() }
            ?.firstOrNull { it.startsWith("charset=", ignoreCase = true) }
            ?.substring(8)
            ?.trim('"', ' ')
            ?: return StandardCharsets.UTF_8
        return try {
            Charset.forName(name)
        } catch (e: IllegalArgumentException) {
            StandardCharsets.UTF_8
        }
    }

    companion object {
        // A desktop Firefox string, as NewPipe sends; the extractor sets its own
        // client strings on the requests that need them.
        const val USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
    }
}
