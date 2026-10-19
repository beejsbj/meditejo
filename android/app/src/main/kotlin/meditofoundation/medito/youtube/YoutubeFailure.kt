package meditofoundation.medito.youtube

import org.schabi.newpipe.extractor.exceptions.AgeRestrictedContentException
import org.schabi.newpipe.extractor.exceptions.ContentNotAvailableException
import org.schabi.newpipe.extractor.exceptions.ExtractionException
import org.schabi.newpipe.extractor.exceptions.PrivateContentException
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.exceptions.SignInConfirmNotBotException
import java.io.IOException
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeoutException

/**
 * A failure the app can show: a typed code and a calm sentence. Nothing
 * from the extractor (URLs, stack traces, server text) is ever put in the
 * message, so it is safe to hand to Dart as it is.
 */
class YoutubeFailure(val code: String, message: String, cause: Throwable? = null) :
    Exception(message, cause) {

    companion object {
        const val UNAVAILABLE = "unavailable"
        const val AGE_RESTRICTED = "age-restricted"
        const val PRIVATE = "private"
        const val NETWORK = "network"
        const val RATE_LIMITED = "rate-limited"

        fun unavailable() = YoutubeFailure(UNAVAILABLE, "This isn't available on YouTube.")

        fun invalidLink() =
            YoutubeFailure(UNAVAILABLE, "That doesn't look like a YouTube video or playlist link.")

        fun unsupported(what: String) =
            YoutubeFailure(UNAVAILABLE, "$what can't be added to Meditejo.")

        fun noAudio() = YoutubeFailure(UNAVAILABLE, "YouTube has no audio Meditejo can play for this video.")

        fun unreadable(cause: Throwable? = null) = YoutubeFailure(
            UNAVAILABLE,
            "Meditejo couldn't read this from YouTube. It may not exist, or YouTube may have changed. Try again later.",
            cause,
        )

        fun tooLarge() = YoutubeFailure(UNAVAILABLE, "This playlist is too large to read in full.")

        fun network(cause: Throwable? = null) =
            YoutubeFailure(NETWORK, "Couldn't reach YouTube. Check the connection and try again.", cause)

        fun rateLimited(cause: Throwable? = null) =
            YoutubeFailure(RATE_LIMITED, "YouTube is limiting requests. Try again later.", cause)

        fun busy() = YoutubeFailure(RATE_LIMITED, "Meditejo is already busy with YouTube. Try again in a moment.")

        fun timedOut(cause: Throwable? = null) = YoutubeFailure(UNAVAILABLE, "YouTube took too long to answer. Try again.", cause)

        /** The failure a thrown exception stands for, looking through wrapped causes. */
        fun from(error: Throwable): YoutubeFailure {
            var current: Throwable? = error
            var depth = 0
            while (current != null && depth < 8) {
                matching(current, error)?.let { return it }
                current = current.cause
                depth++
            }
            return unreadable(error)
        }

        private fun matching(t: Throwable, root: Throwable): YoutubeFailure? = when (t) {
            is YoutubeFailure -> t
            is AgeRestrictedContentException ->
                YoutubeFailure(AGE_RESTRICTED, "YouTube only shows this to signed-in adults, so Meditejo can't play it.", root)
            is PrivateContentException ->
                YoutubeFailure(PRIVATE, "This is private on YouTube, so Meditejo can't reach it.", root)
            is ReCaptchaException, is SignInConfirmNotBotException -> rateLimited(root)
            is ContentNotAvailableException -> YoutubeFailure(UNAVAILABLE, unavailable().message!!, root)
            is TimeoutException, is java.io.InterruptedIOException -> timedOut(root)
            is CancellationException, is InterruptedException -> unreadable(root)
            is IOException -> network(root)
            is ExtractionException -> null // a wrapper: its cause may say more
            else -> null
        }
    }
}
