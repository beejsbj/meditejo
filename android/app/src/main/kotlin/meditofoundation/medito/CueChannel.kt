package meditofoundation.medito

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * `meditejo/cues`: the Dart side of the cue system. Execution lives in
 * [AudioPlayerService]; this only forwards.
 *
 *  - `configure(map)`  arm the cues for the next playAudio (or re-arm a live session)
 *  - `skipCountdown`   end the countdown now
 *  - `skipHold`        end the hold in the recording that is under way (bool: whether one was)
 *  - `holdInterlude`   wait out the autoplay interlude (the rest of it, when it began at the end)
 *  - `endInterlude`    no autoplay after all: finish once the end bell has rung out
 *  - `stop`            cancel every timer, sound and the configuration
 *  - `state`           map: phase (idle, countdown, playing, hold, extension, ended), countdownRemainingMs,
 *                      extensionRemainingMs, holdRemainingMs, extensionLeftMs, sessionMs, paused, heardMs
 *  - `countdownRemainingMs`  int
 *  - `sampleListening` bool: 90% really heard (the service samples the player itself)
 *  - `resetListening`  start a fresh listening record
 */
internal object CueChannel {
    const val NAME = "meditejo/cues"

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            val service = AudioPlayerService.instance
            if (service == null) {
                when (call.method) {
                    // Nothing is playing, so there is nothing to cancel or report.
                    "stop", "skipCountdown", "resetListening", "endInterlude" -> result.success(null)
                    "skipHold" -> result.success(false)
                    "state" -> result.success(mapOf("phase" to "idle"))
                    "countdownRemainingMs" -> result.success(0L)
                    "sampleListening" -> result.success(false)
                    else -> result.error("SERVICE_NOT_READY", "The audio service is not running", null)
                }
                return@setMethodCallHandler
            }
            try {
                when (call.method) {
                    "configure" -> {
                        service.configureCues(call.arguments as? Map<*, *> ?: emptyMap<String, Any?>())
                        result.success(null)
                    }
                    "holdInterlude" -> {
                        val args = call.arguments as? Map<*, *>
                        service.holdInterlude((args?.get("seconds") as? Number)?.toInt() ?: 0) { result.success(null) }
                    }
                    "endInterlude" -> { service.endInterlude(); result.success(null) }
                    "skipCountdown" -> { service.skipCountdown(); result.success(null) }
                    "skipHold" -> result.success(service.skipHold())
                    "stop" -> { service.stopCues(); result.success(null) }
                    "state" -> result.success(service.cueState())
                    "countdownRemainingMs" -> result.success(service.cueState()["countdownRemainingMs"] ?: 0L)
                    "sampleListening" -> result.success(service.sampleListening())
                    "resetListening" -> { service.resetListening(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("CUES_FAILED", e.message, null)
            }
        }
    }
}
