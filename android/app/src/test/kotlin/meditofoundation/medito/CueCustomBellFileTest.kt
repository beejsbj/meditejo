package meditofoundation.medito

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * A bell the user made reaches the cue engine as the absolute path of a WAV in
 * the app's own storage (Dart swaps the `custom-bell:` id for it, see
 * NativeCueController). The bank plays it as it plays a bundled asset, but a
 * path that came through the config is never trusted to point anywhere else.
 */
class CueCustomBellFileTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun dataDir() = tmp.newFolder("data")
    private fun bell(dir: File, name: String = "abcdef1234.wav", bytes: Int = 44 + 2000): File {
        val f = File(File(dir, "files/custom_bells").apply { mkdirs() }, name)
        f.writeBytes(ByteArray(bytes))
        return f
    }

    @Test fun aSavedBellPathSurvivesTheConfigUnchanged() {
        val dir = dataDir()
        val path = bell(dir).absolutePath
        val cfg = CueConfig.fromMap(
            mapOf("startSound" to path, "intervalSound" to path, "endSound" to path, "intervalMinutes" to 5),
        )
        assertEquals(path, cfg.startSound)
        assertEquals(path, cfg.intervalSound)
        assertEquals(path, cfg.endSound)
        assertTrue(cfg.hasInterval)
    }

    @Test fun aPathIsAFileAndAnAssetIsNot() {
        assertTrue(CueSoundBank.isFilePath("/data/user/0/app/files/custom_bells/abcdef1234.wav"))
        assertFalse(CueSoundBank.isFilePath("assets/audio/bell_temple.wav"))
        assertFalse(CueSoundBank.isFilePath("custom-bell:abcdef1234"))
    }

    @Test fun aBellInsideAppStorageResolves() {
        val dir = dataDir()
        val f = bell(dir)
        assertEquals(f.canonicalFile, CueSoundBank.resolveFile(f.absolutePath, dir))
    }

    @Test fun aMissingOrEmptyFileDoesNot() {
        val dir = dataDir()
        assertNull(CueSoundBank.resolveFile(File(dir, "files/custom_bells/none.wav").absolutePath, dir))
        assertNull(CueSoundBank.resolveFile(bell(dir, "empty.wav", 0).absolutePath, dir))
        assertNull(CueSoundBank.resolveFile(File(dir, "files").absolutePath, dir))
    }

    @Test fun aFileTooBigForSoundPoolDoesNot() {
        val dir = dataDir()
        assertNull(CueSoundBank.resolveFile(bell(dir, "big.wav", (CueSoundBank.MAX_FILE_BYTES + 1).toInt()).absolutePath, dir))
        assertNotNull(CueSoundBank.resolveFile(bell(dir, "ok.wav", (CueSoundBank.MAX_FILE_BYTES - 1).toInt()).absolutePath, dir))
    }

    @Test fun aPathOutsideAppStorageDoesNot() {
        val dir = dataDir()
        val outside = tmp.newFile("outside.wav").apply { writeBytes(ByteArray(100)) }
        assertNull(CueSoundBank.resolveFile(outside.absolutePath, dir))
        // Nor does one that climbs out of it.
        bell(dir)
        val climbing = File(dir, "files/custom_bells/../../../outside.wav").path
        assertNull(CueSoundBank.resolveFile(climbing, dir))
        // Nor a sibling whose name only starts like the directory's.
        val sibling = File(tmp.root, "data-evil").apply { mkdirs() }
        val evil = File(sibling, "x.wav").apply { writeBytes(ByteArray(100)) }
        assertNull(CueSoundBank.resolveFile(evil.absolutePath, dir))
    }

    @Test fun aLinkOutOfAppStorageDoesNot() {
        val dir = dataDir()
        val outside = tmp.newFile("target.wav").apply { writeBytes(ByteArray(100)) }
        val link = File(File(dir, "files").apply { mkdirs() }, "link.wav")
        try {
            java.nio.file.Files.createSymbolicLink(link.toPath(), outside.toPath())
        } catch (_: Exception) {
            return // no symlinks on this host
        }
        assertNull(CueSoundBank.resolveFile(link.absolutePath, dir))
    }
}
