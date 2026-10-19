package meditofoundation.medito.youtube

import java.net.URI
import java.net.URISyntaxException
import java.util.Locale

/**
 * The pure rules of the YouTube bridge: which audio stream to play, what counts
 * as a YouTube link, when a stream URL expires. Nothing here touches
 * NewPipeExtractor or Android, so the JVM tests cover all of it.
 */

/** An audio stream reduced to what the choice depends on. Bitrate is bits per second. */
data class AudioCandidate(
    val url: String,
    val mimeType: String,
    val codec: String,
    val bitrate: Int,
    val isDrc: Boolean = false,
    /** False for dubbed, descriptive and other secondary tracks. */
    val isOriginalTrack: Boolean = true,
)

data class ThumbnailCandidate(val url: String, val width: Int, val height: Int)

object YoutubeSelection {
    private const val MAX_INPUT_LENGTH = 2048
    private const val MIN_PLAUSIBLE_EXPIRY_SECONDS = 946_684_800L // 2000-01-01
    private const val MAX_PLAUSIBLE_EXPIRY_SECONDS = 4_102_444_800L // 2100-01-01

    private val videoId = Regex("^[A-Za-z0-9_-]{11}$")
    private val playlistId = Regex("^(PL|UU|FL|OLAK5uy_)[A-Za-z0-9_-]{10,}$")
    private val videoIdInUrl = Regex("""(?:[?&]v=|youtu\.be/|/(?:shorts|embed|live|v)/)([A-Za-z0-9_-]{11})""")
    private val expireParam = Regex("""[?&]expire=(\d{1,12})(?:&|$)""")
    private val expirePath = Regex("""/expire/(\d{1,12})(?:/|$)""")
    private val youtubeHosts = setOf(
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "music.youtube.com",
        "youtu.be",
        "www.youtube-nocookie.com",
        "youtube-nocookie.com",
    )

    /**
     * Whether a stream is something Meditejo can play: AAC in MP4 (m4a) or Opus
     * in WebM/Ogg. An empty codec is accepted for MP4, whose only YouTube
     * audio is AAC; WebM must say it is Opus because older WebM audio is Vorbis.
     */
    fun isSupported(candidate: AudioCandidate): Boolean {
        if (!candidate.url.startsWith("https://")) return false
        val mime = candidate.mimeType.substringBefore(';').trim().lowercase(Locale.ROOT)
        val codec = candidate.codec.lowercase(Locale.ROOT)
        return when (mime) {
            "audio/mp4" -> codec.isEmpty() || codec.startsWith("mp4a")
            "audio/webm", "audio/opus", "audio/ogg" -> codec.contains("opus")
            else -> false
        }
    }

    /**
     * The best stream: the original-language track, without dynamic-range
     * compression (it flattens quiet teaching), at the highest bitrate. A tie
     * goes to Opus, then to the earlier stream.
     */
    fun selectBestAudio(candidates: List<AudioCandidate>): AudioCandidate? {
        val supported = candidates.filter(::isSupported)
        if (supported.isEmpty()) return null
        return supported.reduce { best, next -> if (rank(next) > rank(best)) next else best }
    }

    private fun rank(c: AudioCandidate): Long {
        val original = if (c.isOriginalTrack) 1L else 0L
        val plain = if (c.isDrc) 0L else 1L
        val opus = if (c.codec.contains("opus", ignoreCase = true)) 1L else 0L
        val bitrate = c.bitrate.coerceIn(0, 0xFFFFFF).toLong()
        return (original shl 40) or (plain shl 36) or (bitrate shl 4) or opus
    }

    /** Epoch milliseconds when a stream URL stops working, from its `expire` field; null if absent. */
    fun expiresAtMillis(url: String): Long? {
        val seconds = (expireParam.find(url) ?: expirePath.find(url))
            ?.groupValues?.get(1)?.toLongOrNull()
            ?: return null
        if (seconds < MIN_PLAUSIBLE_EXPIRY_SECONDS || seconds > MAX_PLAUSIBLE_EXPIRY_SECONDS) return null
        return seconds * 1000L
    }

    /** The URL of a video from a link or a bare 11-character id, or null if it is neither. */
    fun videoUrl(urlOrId: String): String? {
        val text = urlOrId.trim()
        if (videoId.matches(text)) return "https://www.youtube.com/watch?v=$text"
        return youtubeUrl(text)
    }

    /** The URL of a playlist from a link or a bare playlist id, or null if it is neither. */
    fun playlistUrl(urlOrId: String): String? {
        val text = urlOrId.trim()
        if (playlistId.matches(text)) return "https://www.youtube.com/playlist?list=$text"
        return youtubeUrl(text)
    }

    /** The video id a stream item's URL points at. */
    fun videoIdOf(url: String): String? = videoIdInUrl.find(url)?.groupValues?.get(1)

    /** A well-formed https YouTube link, with the scheme added if the text started at the host. */
    private fun youtubeUrl(text: String): String? {
        if (text.isEmpty() || text.length > MAX_INPUT_LENGTH || text.any { it.isWhitespace() }) return null
        val withScheme = when {
            text.startsWith("https://", ignoreCase = true) -> text
            text.startsWith("http://", ignoreCase = true) -> "https://" + text.substring(7)
            text.contains("://") -> return null
            else -> "https://$text"
        }
        val host = try {
            URI(withScheme).host?.lowercase(Locale.ROOT)
        } catch (e: URISyntaxException) {
            null
        }
        return if (host != null && host in youtubeHosts) withScheme else null
    }

    /** The largest thumbnail; unknown sizes rank below known ones. Empty when there is none. */
    fun bestThumbnail(candidates: List<ThumbnailCandidate>): String {
        val usable = candidates.filter { it.url.startsWith("https://") }
        if (usable.isEmpty()) return ""
        fun area(t: ThumbnailCandidate) = t.width.coerceAtLeast(0).toLong() * t.height.coerceAtLeast(0).toLong()
        return usable.reduce { best, next -> if (area(next) > area(best)) next else best }.url
    }

    /** Text from a description that may be HTML: line breaks kept, tags dropped, entities decoded. */
    fun plainText(content: String, isHtml: Boolean): String {
        if (!isHtml) return content.trim()
        return content
            .replace(Regex("(?i)<\\s*br\\s*/?>"), "\n")
            .replace(Regex("(?i)</\\s*(p|div|li)\\s*>"), "\n")
            .replace(Regex("<[^>]*>"), "")
            .replace("&nbsp;", " ")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace("&amp;", "&")
            .trim()
    }
}
