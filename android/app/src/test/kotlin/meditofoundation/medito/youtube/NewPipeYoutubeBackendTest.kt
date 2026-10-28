package meditofoundation.medito.youtube

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import org.schabi.newpipe.extractor.stream.StreamType

class NewPipeYoutubeBackendTest {
    private fun row(url: String, uploader: String?): StreamInfoItem {
        val item = StreamInfoItem(0, url, "A talk", StreamType.VIDEO_STREAM)
        item.uploaderName = uploader
        item.duration = 90L
        return item
    }

    @Test
    fun aRowCarriesItsOwnUploader() {
        val item = NewPipeYoutubeBackend.toItem(row("https://www.youtube.com/watch?v=aaaaaaaaaaa", "Guest Channel"))
        assertEquals("aaaaaaaaaaa", item?.videoId)
        assertEquals("Guest Channel", item?.uploader)
        assertEquals(90L, item?.durationSeconds)
    }

    @Test
    fun aRowWithNoUploaderIsLeftEmpty() {
        val item = NewPipeYoutubeBackend.toItem(row("https://www.youtube.com/watch?v=bbbbbbbbbbb", null))
        assertEquals("", item?.uploader)
    }

    @Test
    fun aRowThatIsNotAVideoIsDropped() {
        assertNull(NewPipeYoutubeBackend.toItem(row("https://www.youtube.com/channel/UC123", "Someone")))
    }
}
