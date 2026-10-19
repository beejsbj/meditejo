package meditofoundation.medito.youtube

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class YoutubeSelectionTest {

    private fun m4a(bitrate: Int, url: String = "https://r.example/m4a$bitrate", drc: Boolean = false, original: Boolean = true) =
        AudioCandidate(url, "audio/mp4", "mp4a.40.2", bitrate, drc, original)

    private fun opus(bitrate: Int, url: String = "https://r.example/opus$bitrate", drc: Boolean = false, original: Boolean = true) =
        AudioCandidate(url, "audio/webm", "opus", bitrate, drc, original)

    @Test
    fun picksTheHighestBitrateAcrossM4aAndOpus() {
        val best = YoutubeSelection.selectBestAudio(listOf(m4a(129_000), opus(160_000), opus(70_000), m4a(48_000)))
        assertEquals("https://r.example/opus160000", best?.url)
    }

    @Test
    fun m4aWinsWhenItIsFaster() {
        val best = YoutubeSelection.selectBestAudio(listOf(opus(130_000), m4a(131_000)))
        assertEquals("audio/mp4", best?.mimeType)
    }

    @Test
    fun opusWinsATie() {
        val best = YoutubeSelection.selectBestAudio(listOf(m4a(128_000), opus(128_000)))
        assertEquals("audio/webm", best?.mimeType)
    }

    @Test
    fun theFirstOfIdenticalStreamsWins() {
        val best = YoutubeSelection.selectBestAudio(listOf(m4a(128_000, url = "https://r.example/a"), m4a(128_000, url = "https://r.example/b")))
        assertEquals("https://r.example/a", best?.url)
    }

    @Test
    fun anOriginalTrackBeatsAFasterDubbedOne() {
        val best = YoutubeSelection.selectBestAudio(listOf(opus(160_000, original = false), m4a(128_000)))
        assertEquals("https://r.example/m4a128000", best?.url)
    }

    @Test
    fun aPlainStreamBeatsAFasterDynamicRangeCompressedOne() {
        val best = YoutubeSelection.selectBestAudio(listOf(opus(160_000, drc = true), opus(128_000)))
        assertEquals("https://r.example/opus128000", best?.url)
    }

    @Test
    fun aDubbedOrDrcStreamIsStillBetterThanNothing() {
        val best = YoutubeSelection.selectBestAudio(listOf(opus(160_000, drc = true, original = false)))
        assertEquals("https://r.example/opus160000", best?.url)
    }

    @Test
    fun unsupportedStreamsAreNeverChosen() {
        val vorbis = AudioCandidate("https://r.example/v", "audio/webm", "vorbis", 192_000)
        val insecure = AudioCandidate("http://r.example/i", "audio/mp4", "mp4a.40.2", 192_000)
        val video = AudioCandidate("https://r.example/mp4", "video/mp4", "avc1.4d401f", 900_000)
        val ac3 = AudioCandidate("https://r.example/ac3", "audio/mp4", "ac-3", 384_000)
        val mp3 = AudioCandidate("https://r.example/mp3", "audio/mpeg", "mp3", 320_000)
        assertNull(YoutubeSelection.selectBestAudio(listOf(vorbis, insecure, video, ac3, mp3)))
        assertEquals("https://r.example/m4a48000", YoutubeSelection.selectBestAudio(listOf(vorbis, video, m4a(48_000)))?.url)
    }

    @Test
    fun anM4aWithoutACodecStringIsAccepted() {
        assertTrue(YoutubeSelection.isSupported(AudioCandidate("https://r.example/a", "audio/mp4", "", 1)))
        assertFalse(YoutubeSelection.isSupported(AudioCandidate("https://r.example/a", "audio/webm", "", 1)))
    }

    @Test
    fun noCandidatesMeansNoStream() {
        assertNull(YoutubeSelection.selectBestAudio(emptyList()))
    }

    @Test
    fun unknownBitratesStillRankBelowKnownOnes() {
        assertEquals("https://r.example/opus64000", YoutubeSelection.selectBestAudio(listOf(m4a(0), opus(64_000)))?.url)
    }

    @Test
    fun expiryComesFromTheQueryInMilliseconds() {
        val url = "https://rr1.googlevideo.com/videoplayback?expire=1787000000&ei=abc&itag=251"
        assertEquals(1_787_000_000_000L, YoutubeSelection.expiresAtMillis(url))
        assertEquals(1_787_000_000_000L, YoutubeSelection.expiresAtMillis("https://x.example/videoplayback?itag=140&expire=1787000000"))
    }

    @Test
    fun expiryCanBeInThePath() {
        assertEquals(1_787_000_000_000L, YoutubeSelection.expiresAtMillis("https://x.example/videoplayback/expire/1787000000/itag/140"))
    }

    @Test
    fun missingOrImplausibleExpiryIsNull() {
        assertNull(YoutubeSelection.expiresAtMillis("https://x.example/videoplayback?itag=140"))
        assertNull(YoutubeSelection.expiresAtMillis("https://x.example/videoplayback?expire=12"))
        assertNull(YoutubeSelection.expiresAtMillis("https://x.example/videoplayback?expire=99999999999"))
        assertNull(YoutubeSelection.expiresAtMillis("https://x.example/videoplayback?notexpire=1787000000"))
    }

    @Test
    fun aBareIdBecomesAWatchUrl() {
        assertEquals("https://www.youtube.com/watch?v=dQw4w9WgXcQ", YoutubeSelection.videoUrl(" dQw4w9WgXcQ "))
        assertEquals("https://www.youtube.com/watch?v=-_AbC123xyZ", YoutubeSelection.videoUrl("-_AbC123xyZ"))
    }

    @Test
    fun youtubeLinksAreAcceptedInTheirCommonForms() {
        assertEquals("https://youtu.be/dQw4w9WgXcQ?t=5", YoutubeSelection.videoUrl("https://youtu.be/dQw4w9WgXcQ?t=5"))
        assertEquals("https://m.youtube.com/watch?v=dQw4w9WgXcQ", YoutubeSelection.videoUrl("m.youtube.com/watch?v=dQw4w9WgXcQ"))
        assertEquals("https://www.youtube.com/watch?v=dQw4w9WgXcQ", YoutubeSelection.videoUrl("http://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        assertEquals("https://music.youtube.com/watch?v=dQw4w9WgXcQ", YoutubeSelection.videoUrl("https://music.youtube.com/watch?v=dQw4w9WgXcQ"))
    }

    @Test
    fun otherSitesAndJunkAreRejected() {
        for (text in listOf(
            "", "  ", "short", "https://vimeo.com/12345", "https://evil.example/https://youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ", "ftp://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "file:///etc/passwd", "javascript:alert(1)", "https://www.youtube.com/watch?v=a b",
            "https://soundcloud.com/a/b", "dQw4w9WgXcQ!!", "x".repeat(3000),
        )) {
            assertNull("accepted: $text", YoutubeSelection.videoUrl(text))
            assertNull("accepted: $text", YoutubeSelection.playlistUrl(text))
        }
    }

    @Test
    fun aBarePlaylistIdBecomesAPlaylistUrl() {
        assertEquals(
            "https://www.youtube.com/playlist?list=PLND1JCRq8VujAHvDA482SXF1cJTQrwlx3",
            YoutubeSelection.playlistUrl("PLND1JCRq8VujAHvDA482SXF1cJTQrwlx3"),
        )
        assertEquals(
            "https://www.youtube.com/playlist?list=PLbmYHvGI-YSvnpbh3ppQqcG72lpw4aQdE",
            YoutubeSelection.playlistUrl("PLbmYHvGI-YSvnpbh3ppQqcG72lpw4aQdE"),
        )
        assertEquals(
            "https://www.youtube.com/playlist?list=PLND1JCRq8VujAHvDA482SXF1cJTQrwlx3",
            YoutubeSelection.playlistUrl("https://www.youtube.com/playlist?list=PLND1JCRq8VujAHvDA482SXF1cJTQrwlx3"),
        )
    }

    @Test
    fun videoIdsAreReadFromItemUrls() {
        assertEquals("dQw4w9WgXcQ", YoutubeSelection.videoIdOf("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        assertEquals("dQw4w9WgXcQ", YoutubeSelection.videoIdOf("https://www.youtube.com/watch?list=PLx&v=dQw4w9WgXcQ&t=3"))
        assertEquals("dQw4w9WgXcQ", YoutubeSelection.videoIdOf("https://youtu.be/dQw4w9WgXcQ"))
        assertEquals("dQw4w9WgXcQ", YoutubeSelection.videoIdOf("https://www.youtube.com/shorts/dQw4w9WgXcQ"))
        assertNull(YoutubeSelection.videoIdOf("https://www.youtube.com/playlist?list=PLx"))
    }

    @Test
    fun theLargestThumbnailIsChosen() {
        val best = YoutubeSelection.bestThumbnail(
            listOf(
                ThumbnailCandidate("https://i.example/small.jpg", 168, 94),
                ThumbnailCandidate("https://i.example/large.jpg", 1280, 720),
                ThumbnailCandidate("https://i.example/medium.jpg", 480, 360),
                ThumbnailCandidate("http://i.example/insecure-huge.jpg", 4000, 3000),
            ),
        )
        assertEquals("https://i.example/large.jpg", best)
    }

    @Test
    fun unknownSizedThumbnailsStillWorkAndNoneIsEmpty() {
        assertEquals("https://i.example/a.jpg", YoutubeSelection.bestThumbnail(listOf(ThumbnailCandidate("https://i.example/a.jpg", -1, -1))))
        assertEquals("", YoutubeSelection.bestThumbnail(emptyList()))
    }

    @Test
    fun htmlDescriptionsBecomePlainText() {
        val html = "Line one<br>Line <b>two</b> &amp; more<br/><a href=\"https://x.example\">link</a> &lt;3"
        assertEquals("Line one\nLine two & more\nlink <3", YoutubeSelection.plainText(html, isHtml = true))
        assertEquals("a <b> c", YoutubeSelection.plainText("  a <b> c ", isHtml = false))
    }
}
