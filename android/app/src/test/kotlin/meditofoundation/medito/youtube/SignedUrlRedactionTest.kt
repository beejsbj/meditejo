package meditofoundation.medito.youtube

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SignedUrlRedactionTest {
    private val signed =
        "https://rr1---sn-abc.googlevideo.com/videoplayback?expire=1&sig=SECRET&ip=1.2.3.4&mime=audio%2Fwebm"

    @Test
    fun aStreamAddressKeepsOnlyItsHost() {
        assertEquals(
            "Source error for https://rr1---sn-abc.googlevideo.com/<redacted> after 3 tries",
            SignedUrlRedaction.redact("Source error for $signed after 3 tries"),
        )
    }

    @Test
    fun everyAddressInAStackTraceIsRedacted() {
        val text = "HttpDataSourceException: Unable to connect\n  at x(DataSpec[GET $signed])\nCaused by: $signed."
        val out = SignedUrlRedaction.redact(text)
        assertFalse(out.contains("SECRET"))
        assertFalse(out.contains("sig="))
        assertEquals(2, Regex("<redacted>").findAll(out).count())
    }

    @Test
    fun aVideoplaybackPathOnYoutubeIsSignedToo() {
        assertTrue(SignedUrlRedaction.isSigned("https://www.youtube.com/videoplayback?sig=SECRET"))
    }

    @Test
    fun aSignedAddressHoldingBracketsIsRedactedToItsEnd() {
        val out = SignedUrlRedaction.redact("uri = https://rr.googlevideo.com/videoplayback?n=(x)&p=[1]&sig=SECRET.")
        assertFalse(out.contains("SECRET"))
        assertFalse(out.contains("&p="))
        assertEquals(1, Regex("<redacted>").findAll(out).count())
    }

    @Test
    fun aSignedAddressJoinedToAnOrdinaryOneIsStillRedacted() {
        val out = SignedUrlRedaction.redact("urls: https://example.org/a,$signed done")
        assertFalse(out.contains("SECRET"))
        assertFalse(out.contains("sig="))
    }

    @Test
    fun aSignedAddressCarryingAnotherInItsQueryIsRedacted() {
        val out = SignedUrlRedaction.redact("https://rr.googlevideo.com/videoplayback?redirect=https://example.org&sig=SECRET")
        assertFalse(out.contains("SECRET"))
    }

    @Test
    fun redactingTwiceDoesNotStackMarkers() {
        val once = SignedUrlRedaction.redact("uri = $signed")
        assertEquals(once, SignedUrlRedaction.redact(once))
        assertEquals(1, Regex("<redacted>").findAll(once).count())
    }

    @Test
    fun theSchemeAndHostMatchWhateverTheirCase() {
        assertFalse(SignedUrlRedaction.redact("HTTPS://RR1.GoogleVideo.com/videoplayback?sig=S").contains("sig="))
    }

    @Test
    fun ordinaryAddressesAreLeftAlone() {
        val text = "Fetched https://www.youtube.com/watch?v=aaaaaaaaaaa and https://example.org/a.mp3?x=1"
        assertEquals(text, SignedUrlRedaction.redact(text))
    }

    @Test
    fun textWithoutAddressesIsUnchanged() {
        assertEquals("Player error: ERROR_CODE_IO_NETWORK_CONNECTION_FAILED", SignedUrlRedaction.redact("Player error: ERROR_CODE_IO_NETWORK_CONNECTION_FAILED"))
    }
}
