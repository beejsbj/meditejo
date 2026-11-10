@file:androidx.media3.common.util.UnstableApi
package meditofoundation.medito

import androidx.media3.common.FlagSet
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import java.util.concurrent.CopyOnWriteArraySet

/**
 * The player the media session (lock screen, notification, headset) sees. For
 * a guided session it reads as Dart's player does, as if the recording were
 * longer by Extend: position and length on [ExtendedTimeline], and playing
 * through a hold or the tail while the voice underneath is stopped. Play,
 * pause and seeks go through the service, so a lock-screen press in a hold
 * pauses the hold instead of starting the voice.
 *
 * Anything else (a timer, a repeat, no session) is the player as it is.
 */
internal class SessionPlayer(player: Player, private val session: Session) : ForwardingPlayer(player) {

    interface Session {
        /** The session reads as the extended timeline. */
        fun extends(): Boolean
        fun positionMs(): Long
        fun durationMs(): Long
        /** The session is under way: the voice playing, or its silence running. */
        fun running(): Boolean
        /** The voice is waiting: the countdown, a hold or the tail. */
        fun silent(): Boolean
        fun setRunning(run: Boolean)
        fun seekTo(positionMs: Long)
        fun seekBy(deltaMs: Long)
    }

    private val listeners = CopyOnWriteArraySet<Player.Listener>()

    override fun addListener(listener: Player.Listener) {
        super.addListener(listener)
        listeners.add(listener)
    }

    override fun removeListener(listener: Player.Listener) {
        super.removeListener(listener)
        listeners.remove(listener)
    }

    /**
     * The session's state changed without the voice's player noticing (a hold
     * or the tail paused, resumed, entered or left): tell the session's
     * listeners, which read the state back from the getters below.
     */
    fun invalidate() {
        if (listeners.isEmpty()) return
        val playWhenReady = playWhenReady
        val state = playbackState
        val playing = isPlaying
        val events = Player.Events(
            FlagSet.Builder().addAll(
                Player.EVENT_PLAY_WHEN_READY_CHANGED,
                Player.EVENT_PLAYBACK_STATE_CHANGED,
                Player.EVENT_IS_PLAYING_CHANGED,
            ).build(),
        )
        listeners.forEach {
            it.onPlayWhenReadyChanged(playWhenReady, Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST)
            it.onPlaybackStateChanged(state)
            it.onIsPlayingChanged(playing)
            it.onEvents(this, events)
        }
    }

    private val extended: Boolean get() = session.extends()
    private val silent: Boolean get() = extended && session.silent()

    override fun isPlaying(): Boolean = if (extended) session.running() else super.isPlaying()

    override fun getPlayWhenReady(): Boolean = if (silent) session.running() else super.getPlayWhenReady()

    // In a hold or the tail the voice is paused or ended, but the session plays on.
    override fun getPlaybackState(): Int = if (silent) Player.STATE_READY else super.getPlaybackState()

    // Silence runs at real time, whatever the voice's speed.
    override fun getPlaybackParameters(): PlaybackParameters =
        if (silent) PlaybackParameters.DEFAULT else super.getPlaybackParameters()

    override fun getCurrentPosition(): Long = if (extended) session.positionMs() else super.getCurrentPosition()

    override fun getContentPosition(): Long = if (extended) session.positionMs() else super.getContentPosition()

    override fun getDuration(): Long = if (extended) session.durationMs() else super.getDuration()

    override fun getContentDuration(): Long = if (extended) session.durationMs() else super.getContentDuration()

    override fun getBufferedPosition(): Long {
        if (!extended) return super.getBufferedPosition()
        val ahead = (super.getBufferedPosition() - super.getCurrentPosition()).coerceAtLeast(0L)
        return (session.positionMs() + ahead).coerceAtMost(session.durationMs())
    }

    override fun getContentBufferedPosition(): Long = getBufferedPosition()

    override fun play() { if (extended) session.setRunning(true) else super.play() }

    override fun pause() { if (extended) session.setRunning(false) else super.pause() }

    override fun setPlayWhenReady(playWhenReady: Boolean) {
        if (extended) session.setRunning(playWhenReady) else super.setPlayWhenReady(playWhenReady)
    }

    override fun seekTo(positionMs: Long) { if (extended) session.seekTo(positionMs) else super.seekTo(positionMs) }

    override fun seekTo(mediaItemIndex: Int, positionMs: Long) {
        if (extended && mediaItemIndex == currentMediaItemIndex) session.seekTo(positionMs)
        else super.seekTo(mediaItemIndex, positionMs)
    }

    override fun seekBack() { if (extended) session.seekBy(-seekBackIncrement) else super.seekBack() }

    override fun seekForward() { if (extended) session.seekBy(seekForwardIncrement) else super.seekForward() }
}
