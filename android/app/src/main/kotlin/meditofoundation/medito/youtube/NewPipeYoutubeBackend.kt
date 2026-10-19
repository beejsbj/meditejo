package meditofoundation.medito.youtube

import meditofoundation.medito.pigeon.YoutubeAudioStream
import meditofoundation.medito.pigeon.YoutubePlaylist
import meditofoundation.medito.pigeon.YoutubePlaylistItem
import meditofoundation.medito.pigeon.YoutubeVideo
import org.schabi.newpipe.extractor.Image
import org.schabi.newpipe.extractor.MediaFormat
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.Page
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.exceptions.ParsingException
import org.schabi.newpipe.extractor.localization.Localization
import org.schabi.newpipe.extractor.playlist.PlaylistInfo
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.AudioTrackType
import org.schabi.newpipe.extractor.stream.Description
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamType
import java.util.Locale

/** What the bridge needs from YouTube. Calls block, so they run on worker threads. */
interface YoutubeBackend {
    /** [url] is a link [YoutubeSelection.playlistUrl] accepted. */
    fun playlist(url: String): YoutubePlaylist

    /** [url] is a link [YoutubeSelection.videoUrl] accepted. */
    fun video(url: String): YoutubeVideo

    /** [url] is a link [YoutubeSelection.videoUrl] accepted. */
    fun audioStream(url: String): YoutubeAudioStream
}

/**
 * [YoutubeBackend] over NewPipeExtractor. The extractor keeps its downloader
 * and localisation in static state, so it is set up once per process, and
 * only the YouTube service is ever used.
 */
class NewPipeYoutubeBackend(
    private val downloader: YoutubeDownloader = YoutubeDownloader(),
) : YoutubeBackend {

    override fun playlist(url: String): YoutubePlaylist {
        ensureInitialized(downloader)
        val extractor = linked { ServiceList.YouTube.getPlaylistExtractor(url) }
        extractor.fetchPage()
        if (extractor.playlistType != PlaylistInfo.PlaylistType.NORMAL) {
            // Mixes are generated endlessly; there is no playlist to keep.
            throw YoutubeFailure.unsupported("A YouTube mix")
        }
        val title = extractor.name
        val uploader = optional { extractor.uploaderName }
        val thumbnail = optional { YoutubeSelection.bestThumbnail(thumbnails(extractor.thumbnails)) }

        val firstPage = extractor.initialPage
        val items = YoutubePaging.collect(
            first = PageResult(firstPage.items.mapNotNull(::toItem), firstPage.nextPage.takeIf(Page::isValid)),
            keyOf = ::pageKey,
            fetch = { token ->
                val page = extractor.getPage(token)
                PageResult(page.items.mapNotNull(::toItem), page.nextPage.takeIf(Page::isValid))
            },
        )
        return YoutubePlaylist(title = title, uploader = uploader, thumbnail = thumbnail, items = items)
    }

    override fun video(url: String): YoutubeVideo {
        ensureInitialized(downloader)
        val extractor = linked { ServiceList.YouTube.getStreamExtractor(url) }
        extractor.fetchPage()
        return YoutubeVideo(
            videoId = extractor.id,
            title = extractor.name,
            uploader = optional { extractor.uploaderName },
            durationSeconds = optional(0L) { extractor.length }.coerceAtLeast(0L),
            thumbnail = optional { YoutubeSelection.bestThumbnail(thumbnails(extractor.thumbnails)) },
            description = optional { plainText(extractor.description) },
        )
    }

    override fun audioStream(url: String): YoutubeAudioStream {
        ensureInitialized(downloader)
        val extractor = linked { ServiceList.YouTube.getStreamExtractor(url) }
        extractor.fetchPage()
        val type = extractor.streamType
        if (type == StreamType.LIVE_STREAM || type == StreamType.AUDIO_LIVE_STREAM) {
            throw YoutubeFailure.unsupported("A live stream")
        }
        // Only the audio list is read: building video streams is wasted work, and
        // never anything that could be played as video.
        val streams = extractor.audioStreams
        val byUrl = HashMap<String, AudioCandidate>()
        for (stream in streams) toCandidate(stream)?.let { byUrl.putIfAbsent(it.url, it) }
        val best = YoutubeSelection.selectBestAudio(byUrl.values.toList()) ?: throw YoutubeFailure.noAudio()
        return YoutubeAudioStream(
            url = best.url,
            mimeType = best.mimeType,
            bitrate = best.bitrate.toLong(),
            expiresAt = YoutubeSelection.expiresAtMillis(best.url),
        )
    }

    private fun toItem(item: org.schabi.newpipe.extractor.stream.StreamInfoItem): YoutubePlaylistItem? {
        val id = YoutubeSelection.videoIdOf(item.url) ?: return null
        return YoutubePlaylistItem(
            videoId = id,
            title = item.name ?: "",
            durationSeconds = item.duration.coerceAtLeast(0L),
            thumbnail = YoutubeSelection.bestThumbnail(thumbnails(item.thumbnails)),
        )
    }

    private fun pageKey(page: Page): Any =
        listOf(page.url, page.id, page.ids, page.body?.contentHashCode(), page.cookies)

    private fun plainText(description: Description?): String =
        description?.let { YoutubeSelection.plainText(it.content ?: "", it.type == Description.HTML) } ?: ""

    /** The extractor for a link, or the failure for a link the service doesn't take. */
    private fun <T> linked(make: () -> T): T = try {
        make()
    } catch (e: ParsingException) {
        throw YoutubeFailure.invalidLink()
    }

    /** A detail that is nice to have: when YouTube leaves it out, it is empty. */
    private fun optional(read: () -> String): String = optional("", read)

    private fun <T> optional(fallback: T, read: () -> T): T = try {
        read() ?: fallback
    } catch (e: ParsingException) {
        fallback
    }

    companion object {
        private val lock = Any()

        @Volatile
        private var initialised = false

        /** Sets up NewPipeExtractor once, whichever thread asks first. */
        fun ensureInitialized(downloader: YoutubeDownloader) {
            if (initialised) return
            synchronized(lock) {
                if (initialised) return
                val country = Locale.getDefault().country.takeIf { it.length == 2 } ?: "GB"
                NewPipe.init(downloader, Localization("en", country))
                initialised = true
            }
        }

        internal fun thumbnails(images: List<Image>?): List<ThumbnailCandidate> =
            images.orEmpty().map { ThumbnailCandidate(it.url, it.width, it.height) }

        /** Null for anything that is not one plain, directly fetchable audio file. */
        internal fun toCandidate(stream: AudioStream): AudioCandidate? {
            if (stream.deliveryMethod != DeliveryMethod.PROGRESSIVE_HTTP || !stream.isUrl) return null
            val format = stream.format ?: return null
            var codec = stream.codec ?: ""
            if (codec.isEmpty() && (format == MediaFormat.WEBMA_OPUS || format == MediaFormat.OPUS)) {
                codec = "opus"
            }
            val bitrate = when {
                stream.bitrate > 0 -> stream.bitrate
                stream.averageBitrate > 0 -> stream.averageBitrate * 1000
                else -> 0
            }
            val itag = stream.itagItem
            val track = stream.audioTrackType
            return AudioCandidate(
                url = stream.content ?: return null,
                mimeType = format.mimeType,
                codec = codec,
                bitrate = bitrate,
                isDrc = itag?.isDrc() == true,
                isOriginalTrack = track == null || track == AudioTrackType.ORIGINAL,
            )
        }
    }
}
