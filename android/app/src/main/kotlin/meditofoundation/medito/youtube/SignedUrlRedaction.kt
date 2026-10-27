package meditofoundation.medito.youtube

import androidx.media3.common.util.UnstableApi
import java.net.URI
import java.util.Locale

/**
 * Keeps signed YouTube stream addresses out of logcat. Such an address works
 * for anyone who holds it until it expires, and `adb logcat` is shared in bug
 * reports. Only the host survives, so a log still says which server failed.
 */
object SignedUrlRedaction {
    private val url = Regex("""https?://[^\s"'<>)\]]+""")

    fun redact(text: String): String = url.replace(text) { match ->
        if (isSigned(match.value)) "https://${hostOf(match.value) ?: "unknown"}/<redacted>" else match.value
    }

    /** A stream address: a googlevideo.com host, or a youtube.com `/videoplayback` path. */
    internal fun isSigned(address: String): Boolean {
        val uri = try { URI(address) } catch (e: Exception) { null }
        val host = uri?.host?.lowercase(Locale.ROOT)
            ?: return address.contains("googlevideo.com", ignoreCase = true) ||
                address.contains("/videoplayback", ignoreCase = true)
        return host == "googlevideo.com" || host.endsWith(".googlevideo.com") ||
            (uri.path ?: "").startsWith("/videoplayback")
    }

    private fun hostOf(address: String): String? =
        try { URI(address).host?.lowercase(Locale.ROOT) } catch (e: Exception) { null }
}

/** Media3 logs its failures with the data source's address; this scrubs them on the way to logcat. */
@UnstableApi
object RedactingMedia3Logger : androidx.media3.common.util.Log.Logger {
    private fun line(message: String, throwable: Throwable?): String {
        val text = if (throwable == null) message else message + "\n" + android.util.Log.getStackTraceString(throwable)
        return SignedUrlRedaction.redact(text)
    }

    override fun d(tag: String, message: String, throwable: Throwable?) {
        android.util.Log.d(tag, line(message, throwable))
    }

    override fun i(tag: String, message: String, throwable: Throwable?) {
        android.util.Log.i(tag, line(message, throwable))
    }

    override fun w(tag: String, message: String, throwable: Throwable?) {
        android.util.Log.w(tag, line(message, throwable))
    }

    override fun e(tag: String, message: String, throwable: Throwable?) {
        android.util.Log.e(tag, line(message, throwable))
    }
}
