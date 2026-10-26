package meditofoundation.medito.folder

import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.nio.file.Files

class FolderCopierTest {
    private lateinit var staging: File

    @Before fun makeStaging() {
        staging = Files.createTempDirectory("folder_copier_test").toFile()
    }

    @After fun removeStaging() {
        staging.deleteRecursively()
    }

    private fun audio(id: String, name: String, size: Long = 100) =
        AudioFile(id, name, "audio/mpeg", size, listOf(name))

    /** Sources by document ID. A null entry opens as null; a missing one throws. */
    private fun copier(
        sources: Map<String, ByteArray?>,
        isCancelled: () -> Boolean = { false },
    ) = FolderCopier(
        open = { file ->
            if (!sources.containsKey(file.documentId)) throw SecurityException("no grant for ${file.documentId}")
            sources[file.documentId]?.let { ByteArrayInputStream(it) }
        },
        isCancelled = isCancelled,
    )

    private fun staged() = staging.listFiles()!!.map { it.name }.sorted()

    @Test fun copiesInOrderUnderNumberedNamesWithTheOriginalNameKept() {
        val files = listOf(audio("a", "Session 1.mp3"), audio("b", "Session 2.mp3"), audio("c", "Jhāna.m4a"))
        val result = copier(
            mapOf("a" to byteArrayOf(1, 2, 3), "b" to byteArrayOf(4), "c" to byteArrayOf(5, 6)),
        ).copy(files, staging)

        assertEquals(listOf("Session 1.mp3", "Session 2.mp3", "Jhāna.m4a"), result.copied.map { it.name })
        assertEquals(listOf("001-Session 1.mp3", "002-Session 2.mp3", "003-Jh_na.m4a"), staged())
        assertEquals(emptyList<String>(), result.skipped)
        assertArrayEquals(byteArrayOf(1, 2, 3), File(result.copied[0].path).readBytes())
        assertEquals(3L, result.copied[0].size)
    }

    @Test fun twoFilesWithTheSameNameDoNotCollide() {
        val files = listOf(
            AudioFile("a", "Sit.mp3", "audio/mpeg", 1, listOf("Week 1", "Sit.mp3")),
            AudioFile("b", "Sit.mp3", "audio/mpeg", 1, listOf("Week 2", "Sit.mp3")),
        )
        val result = copier(mapOf("a" to byteArrayOf(1), "b" to byteArrayOf(2))).copy(files, staging)
        assertEquals(2, result.copied.size)
        assertEquals(2, staged().size)
    }

    @Test fun unreadableFilesAreSkippedAndReportedWhileTheRestCopy() {
        val files = listOf(
            audio("ok1", "One.mp3"),
            audio("denied", "Denied.mp3"), // the provider refuses it
            audio("nullstream", "Gone.mp3"), // the provider has no stream
            audio("empty", "Empty.mp3"), // opens, holds nothing
            audio("ok2", "Two.mp3"),
        )
        val result = copier(
            mapOf(
                "ok1" to byteArrayOf(1),
                "nullstream" to null,
                "empty" to ByteArray(0),
                "ok2" to byteArrayOf(2),
            ),
        ).copy(files, staging)

        assertEquals(listOf("One.mp3", "Two.mp3"), result.copied.map { it.name })
        assertEquals(listOf("Denied.mp3", "Gone.mp3", "Empty.mp3"), result.skipped)
        assertEquals(2, staged().size)
    }

    @Test fun aReadFailurePartWayThroughSkipsThatFileAndLeavesNoPartialCopy() {
        val flaky = object : InputStream() {
            var sent = false
            override fun read(): Int = throw IOException("connection lost")
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (!sent) {
                    sent = true
                    b[off] = 7
                    return 1
                }
                throw IOException("connection lost")
            }
        }
        val copier = FolderCopier(open = { if (it.documentId == "flaky") flaky else ByteArrayInputStream(byteArrayOf(9)) })
        val result = copier.copy(listOf(audio("flaky", "Flaky.mp3"), audio("fine", "Fine.mp3")), staging)

        assertEquals(listOf("Flaky.mp3"), result.skipped)
        assertEquals(listOf("Fine.mp3"), result.copied.map { it.name })
        assertEquals(listOf("002-Fine.mp3"), staged())
    }

    @Test fun cancellingRemovesEverythingCopiedSoFar() {
        var started = 0
        val files = (1..5).map { audio("f$it", "Track $it.mp3") }
        val sources = files.associate { it.documentId to byteArrayOf(1, 2, 3) }
        val copier = FolderCopier(
            open = { started++; ByteArrayInputStream(sources[it.documentId]) },
            isCancelled = { started >= 3 },
        )
        try {
            copier.copy(files, staging)
            fail("expected the copy to be cancelled")
        } catch (e: CopyCancelled) {
            assertEquals(emptyList<String>(), staged())
        }
    }

    @Test fun cancellingInTheMiddleOfAFileLeavesNothing() {
        val big = ByteArray(4 * 1024 * 1024)
        var reads = 0
        val copier = FolderCopier(
            open = { ByteArrayInputStream(big) },
            isCancelled = { reads++ > 10 },
        )
        try {
            copier.copy(listOf(audio("big", "Big.wav", big.size.toLong())), staging)
            fail("expected the copy to be cancelled")
        } catch (e: CopyCancelled) {
            assertEquals(emptyList<String>(), staged())
        }
    }

    @Test fun aWriteFailureStopsTheCopyAndRemovesEverything() {
        val stream = ByteArrayInputStream(byteArrayOf(1, 2, 3))
        val files = listOf(audio("ok", "One.mp3"), audio("full", "Two.mp3"))
        // Two.mp3 fails to write: its target is a directory that already exists.
        File(staging, "002-Two.mp3").mkdirs()
        val copier = FolderCopier(open = { stream.reset(); stream })
        try {
            copier.copy(files, staging)
            fail("expected the write to fail")
        } catch (e: IOException) {
            assertFalse(File(staging, "001-One.mp3").exists())
        }
    }

    @Test fun progressCountsFilesAndBytes() {
        val files = listOf(audio("a", "One.mp3", 3), audio("b", "Two.mp3", 2))
        val seen = ArrayList<CopyProgress>()
        copier(mapOf("a" to byteArrayOf(1, 2, 3), "b" to byteArrayOf(4, 5))).copy(files, staging) { seen.add(it) }

        assertEquals(CopyProgress(0, 2, 0, 5, "One.mp3"), seen.first())
        val last = seen.last()
        assertEquals(2, last.filesDone)
        assertEquals(2, last.filesTotal)
        assertEquals(5L, last.bytesDone)
        assertTrue(seen.map { it.filesDone }.zipWithNext().all { (a, b) -> b >= a })
    }

    @Test fun stagedNamesAreSafeAndShort() {
        assertEquals("a_b_c.mp3", FolderCopier.stagedName("a/b:c.mp3"))
        assertEquals("audio", FolderCopier.stagedName("   "))
        val long = "x".repeat(300) + ".mp3"
        val short = FolderCopier.stagedName(long)
        assertTrue(short.length <= 100)
        assertTrue(short.endsWith(".mp3"))
    }

    @Test fun aFullDiskIsRecognisedFromTheWriteError() {
        assertTrue(FolderCopier.looksLikeFullDisk(IOException("write failed: ENOSPC (No space left on device)")))
        assertTrue(FolderCopier.looksLikeFullDisk(IOException("No space left on device")))
        assertFalse(FolderCopier.looksLikeFullDisk(IOException("Permission denied")))
        assertFalse(FolderCopier.looksLikeFullDisk(IOException()))
    }

    @Test fun roomCheckKeepsAMargin() {
        val mb = 1024L * 1024
        assertTrue(FolderCopier.hasRoom(usable = 500 * mb, needed = 400 * mb))
        assertFalse(FolderCopier.hasRoom(usable = 450 * mb, needed = 400 * mb))
        assertFalse(FolderCopier.hasRoom(usable = 10 * mb, needed = 400 * mb))
    }
}
