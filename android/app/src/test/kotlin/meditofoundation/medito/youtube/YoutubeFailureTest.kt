package meditofoundation.medito.youtube

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Test
import org.schabi.newpipe.extractor.exceptions.AccountTerminatedException
import org.schabi.newpipe.extractor.exceptions.AgeRestrictedContentException
import org.schabi.newpipe.extractor.exceptions.ContentNotAvailableException
import org.schabi.newpipe.extractor.exceptions.ExtractionException
import org.schabi.newpipe.extractor.exceptions.GeographicRestrictionException
import org.schabi.newpipe.extractor.exceptions.ParsingException
import org.schabi.newpipe.extractor.exceptions.PrivateContentException
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.exceptions.SignInConfirmNotBotException
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeoutException

class YoutubeFailureTest {

    private fun code(t: Throwable) = YoutubeFailure.from(t).code

    @Test
    fun contentErrorsMapToTheirCodes() {
        assertEquals("age-restricted", code(AgeRestrictedContentException("age")))
        assertEquals("private", code(PrivateContentException("private")))
        assertEquals("unavailable", code(ContentNotAvailableException("gone")))
        assertEquals("unavailable", code(GeographicRestrictionException("country")))
        assertEquals("unavailable", code(AccountTerminatedException("closed")))
    }

    @Test
    fun networkProblemsRemainDistinctFromBlocksAndTimeouts() {
        assertEquals("network", code(IOException("reset")))
        assertEquals("rate-limited", code(SocketTimeoutException("slow")))
        assertEquals("network", code(UnknownHostException("www.youtube.com")))
        assertEquals("rate-limited", code(ReCaptchaException("captcha", "https://www.youtube.com/watch?v=x")))
        assertEquals("rate-limited", code(SignInConfirmNotBotException("bot")))
        assertEquals("rate-limited", code(TimeoutException()))
        assertEquals("unavailable", code(CancellationException()))
        assertEquals("unavailable", code(InterruptedException()))
    }

    @Test
    fun localBusyIsNotOffline() {
        assertEquals("rate-limited", YoutubeFailure.busy().code)
        assertEquals("rate-limited", YoutubeFailure.timedOut().code)
    }

    @Test
    fun aWrappedCauseDecidesWhenTheWrapperSaysNothing() {
        assertEquals("network", code(ExtractionException("Could not get streams", IOException("reset"))))
        assertEquals("rate-limited", code(ExtractionException("wrapped", SignInConfirmNotBotException("bot"))))
        assertEquals("unavailable", code(ExtractionException("wrapped", TimeoutException())))
        assertEquals("private", code(ParsingException("Could not parse", PrivateContentException("private"))))
        assertEquals("age-restricted", code(RuntimeException(ExtractionException("x", AgeRestrictedContentException("age")))))
    }

    @Test
    fun anythingElseIsUnavailableAsUnreadable() {
        assertEquals("unavailable", code(ParsingException("Could not get name")))
        assertEquals("unavailable", code(NullPointerException()))
        assertEquals("unavailable", code(IllegalStateException("x")))
    }

    @Test
    fun ourOwnFailuresPassThrough() {
        val failure = YoutubeFailure.invalidLink()
        assertSame(failure, YoutubeFailure.from(failure))
        assertSame(failure, YoutubeFailure.from(RuntimeException(failure)))
    }

    @Test
    fun messagesNeverCarryUrlsTracesOrServerText() {
        val secret = "https://rr1.googlevideo.com/videoplayback?key=SECRET"
        val errors = listOf(
            AgeRestrictedContentException("age $secret"),
            PrivateContentException("private $secret"),
            ContentNotAvailableException("Got error UNPLAYABLE: \"$secret\""),
            ReCaptchaException("captcha $secret", secret),
            IOException("failed $secret"),
            ParsingException("Could not parse $secret", IOException(secret)),
            NullPointerException(secret),
        )
        for (error in errors) {
            val failure = YoutubeFailure.from(error)
            val message = failure.message ?: ""
            assertFalse(message, message.contains("http"))
            assertFalse(message, message.contains("SECRET"))
            assertFalse(message, message.contains("Exception"))
            assertFalse(message, message.contains("\n"))
            assertEquals(true, message.length in 10..120)
        }
    }
}
