package meditofoundation.medito

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * The bells the Customize sheet offers live in Dart (`cueBellSounds` in
 * lib/models/cues/cue_settings.dart); a cue config reaches this side carrying
 * the stored asset path. This reads that catalogue and checks each id: the
 * config keeps it, the bank looks it up where the APK packs it, and the file
 * there is a WAV SoundPool decodes. (CueMathTest owns the timing.)
 */
class CueBellCatalogueTest {
    private val root = File("../..") // Gradle runs unit tests from android/app
    private val dart = File(root, "lib/models/cues/cue_settings.dart")

    private fun catalogue(): List<Pair<String, String>> {
        check(dart.exists()) { "Catalogue not found at ${dart.absolutePath}" }
        val block = Regex("""const cueBellSounds = <String, String>\{(.*?)\};""", RegexOption.DOT_MATCHES_ALL)
            .find(dart.readText())!!.groupValues[1]
        return Regex("""'([^']*)':\s*'([^']*)'""").findAll(block).map { it.groupValues[1] to it.groupValues[2] }.toList()
    }

    private val bells get() = catalogue().filter { it.second.isNotEmpty() }

    @Test fun catalogueHasOffAndEnoughBells() {
        assertEquals("Off" to "", catalogue().first())
        assertTrue("only ${bells.size} bells", bells.size >= 8)
        assertEquals(bells.size, bells.map { it.second }.toSet().size)
    }

    @Test fun everyBellIdSurvivesTheConfigUnchanged() {
        for ((name, id) in bells) {
            val cfg = CueConfig.fromMap(
                mapOf("startSound" to id, "intervalSound" to id, "endSound" to id, "intervalMinutes" to 5),
            )
            assertEquals(name, id, cfg.startSound)
            assertEquals(name, id, cfg.intervalSound)
            assertEquals(name, id, cfg.endSound)
            assertTrue(name, cfg.hasInterval)
        }
    }

    @Test fun offStaysSilentOnTheNativeSide() {
        val cfg = CueConfig.fromMap(mapOf("startSound" to null, "intervalSound" to null, "endSound" to null, "intervalMinutes" to 5))
        assertNull(cfg.startSound)
        assertNull(cfg.endSound)
        assertFalse(cfg.hasInterval)
    }

    @Test fun everyBellIsPackedWhereTheBankLooksForIt() {
        for ((name, id) in bells) {
            // Flutter packs assets/... as flutter_assets/assets/... in the APK.
            assertEquals("flutter_assets/$id", CueSoundBank.fallbackKey(id))
            assertTrue("$name: $id is not under assets/audio/", id.startsWith("assets/audio/"))
            assertTrue("$name: ${File(root, id).absolutePath} is missing", File(root, id).isFile)
        }
    }

    @Test fun everyBellIsPlainPcmThatSoundPoolDecodes() {
        for ((name, id) in bells) {
            val b = ByteBuffer.wrap(File(root, id).readBytes()).order(ByteOrder.LITTLE_ENDIAN)
            assertEquals("$name RIFF", 0x46464952, b.getInt(0))
            assertEquals("$name WAVE", 0x45564157, b.getInt(8))
            assertEquals("$name PCM", 1, b.getShort(20).toInt())
            assertEquals("$name mono", 1, b.getShort(22).toInt())
            assertEquals("$name 16-bit", 16, b.getShort(34).toInt())
            val rate = b.getInt(24)
            assertTrue("$name rate $rate", rate == 22050 || rate == 44100)
            // The end bell holds the service open for its length; the longest ring stays modest.
            val seconds = (b.limit() - 44) / 2.0 / rate
            assertTrue("$name is $seconds s", seconds in 0.2..15.0)
            // SoundPool decodes a sound whole and refuses one over about 1 MiB.
            assertTrue("$name is ${b.limit()} bytes", b.limit() < 1 shl 20)
        }
    }

    @Test fun theOriginalBellKeepsItsIdAndTheBellPlayerStillFindsIt() {
        assertTrue(bells.any { it.second == "assets/audio/session_bell_v2.wav" })
        val player = File(root, "android/app/src/main/kotlin/meditofoundation/medito/SessionBellPlayer.kt").readText()
        assertTrue(player.contains("flutter_assets/assets/audio/session_bell_v2.wav"))
    }
}
