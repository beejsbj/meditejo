package meditofoundation.medito.folder

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

/** A tree held in memory: directory ID → its children. */
private class FakeTree(
    private val folders: Map<String, List<TreeEntry>>,
    private val unreadable: Set<String> = emptySet(),
) : DocumentTree {
    val asked = ArrayList<String>()

    override fun children(directoryId: String): List<TreeEntry> {
        asked.add(directoryId)
        if (directoryId in unreadable) throw IOException("provider refused $directoryId")
        return folders[directoryId] ?: emptyList()
    }
}

private fun file(id: String, name: String, mime: String = "audio/mpeg", size: Long = 1000) =
    TreeEntry(id, name, mime, size)

private fun dir(id: String, name: String) = TreeEntry(id, name, DIRECTORY_MIME, -1)

private fun ScanResult.names() = files.map { it.name }
private fun ScanResult.paths() = files.map { it.relativePath.joinToString("/") }

class AudioTreeScannerTest {
    private fun scan(
        folders: Map<String, List<TreeEntry>>,
        unreadable: Set<String> = emptySet(),
        maxFiles: Int = AudioTreeScanner.MAX_FILES,
        maxDepth: Int = AudioTreeScanner.MAX_DEPTH,
    ) = AudioTreeScanner(FakeTree(folders, unreadable), maxFiles, maxDepth).scan("root")

    // ---- Ordering --------------------------------------------------------

    @Test fun sessionTwoComesBeforeSessionTen() {
        val result = scan(
            mapOf(
                "root" to listOf(
                    file("1", "Session 10.mp3"),
                    file("2", "Session 2.mp3"),
                    file("3", "Session 1.mp3"),
                    file("4", "session 11.mp3"),
                ),
            ),
        )
        assertEquals(
            listOf("Session 1.mp3", "Session 2.mp3", "Session 10.mp3", "session 11.mp3"),
            result.names(),
        )
    }

    @Test fun nestedFoldersAreWalkedAndOrderedFolderByFolder() {
        val result = scan(
            mapOf(
                "root" to listOf(
                    dir("w10", "Week 10"),
                    dir("w2", "Week 2"),
                    file("a", "Intro.mp3"),
                ),
                "w2" to listOf(file("w2b", "Sit 2.mp3"), file("w2a", "Sit 1.mp3")),
                "w10" to listOf(file("w10a", "Sit 1.mp3"), dir("deep", "Extras")),
                "deep" to listOf(file("d", "Bonus.m4a", "audio/mp4")),
            ),
        )
        assertEquals(
            listOf(
                "Intro.mp3",
                "Week 2/Sit 1.mp3",
                "Week 2/Sit 2.mp3",
                "Week 10/Extras/Bonus.m4a",
                "Week 10/Sit 1.mp3",
            ),
            result.paths(),
        )
    }

    @Test fun leadingZerosAndCaseOnlyDifferencesStayDeterministic() {
        val order = listOf("track 01.mp3", "Track 1.mp3", "track 2.mp3").shuffled()
        val sorted = order.sortedWith(NaturalOrder)
        assertEquals(sorted, order.shuffled().sortedWith(NaturalOrder))
        assertEquals("track 2.mp3", sorted.last())
    }

    @Test fun veryLongDigitRunsDoNotOverflow() {
        val big = "9".repeat(40)
        assertTrue(NaturalOrder.compare("a${big}0", "a$big") > 0)
        assertTrue(NaturalOrder.compare("a2", "a$big") < 0)
    }

    // ---- Filtering -------------------------------------------------------

    @Test fun audioIsFoundByMimeTypeAndByExtension() {
        val result = scan(
            mapOf(
                "root" to listOf(
                    file("1", "by-mime", "audio/x-something"),
                    file("2", "by-extension.FLAC", "application/octet-stream"),
                    file("3", "ogg-container", "application/ogg"),
                    file("4", "notes.txt", "text/plain"),
                    file("5", "cover.jpg", "image/jpeg"),
                    file("6", "clip.mp4", "video/mp4"),
                ),
            ),
        )
        assertEquals(setOf("by-mime", "by-extension.FLAC", "ogg-container"), result.names().toSet())
    }

    @Test fun playlistsAndCueSheetsAreNotAudioEvenWhenTypedAsAudio() {
        val result = scan(
            mapOf(
                "root" to listOf(
                    file("1", "all.m3u", "audio/x-mpegurl"),
                    file("2", "all.m3u8", "application/vnd.apple.mpegurl"),
                    file("3", "disc.cue", "audio/x-cue"),
                    file("4", "real.mp3"),
                ),
            ),
        )
        assertEquals(listOf("real.mp3"), result.names())
    }

    @Test fun hiddenFilesAndFoldersAreSkipped() {
        val result = scan(
            mapOf(
                "root" to listOf(
                    file("1", "._Session 1.mp3"),
                    file("2", ".trashed-1700000000-Session 2.mp3"),
                    dir("h", ".thumbnails"),
                    file("3", "Session 3.mp3"),
                ),
                "h" to listOf(file("x", "hidden.mp3")),
            ),
        )
        assertEquals(listOf("Session 3.mp3"), result.names())
    }

    @Test fun extensionNeedsAnActualExtension() {
        assertFalse(isAudio("mp3", "application/octet-stream"))
        assertFalse(isAudio("song.", "application/octet-stream"))
        assertTrue(isAudio("song.MP3", ""))
    }

    // ---- Empty, no audio, unreadable ------------------------------------

    @Test fun anEmptyFolderIsToldApartFromOneWithNoAudio() {
        val empty = scan(mapOf("root" to emptyList()))
        assertEquals(0, empty.files.size)
        assertEquals(0, empty.entriesSeen)

        val noAudio = scan(mapOf("root" to listOf(file("1", "notes.txt", "text/plain"), dir("d", "Photos"))))
        assertEquals(0, noAudio.files.size)
        assertEquals(2, noAudio.entriesSeen)
    }

    @Test fun anUnreadableSubfolderIsCountedAndTheRestStillScanned() {
        val result = scan(
            mapOf(
                "root" to listOf(dir("locked", "Locked"), dir("open", "Open"), file("1", "Top.mp3")),
                "open" to listOf(file("2", "Inside.mp3")),
            ),
            unreadable = setOf("locked"),
        )
        assertEquals(listOf("Inside.mp3", "Top.mp3"), result.names().sorted())
        assertEquals(1, result.unreadableFolders)
    }

    @Test fun anUnreadableRootIsReportedNotThrown() {
        val result = scan(emptyMap(), unreadable = setOf("root"))
        assertEquals(0, result.files.size)
        assertEquals(1, result.unreadableFolders)
    }

    // ---- Large and odd trees ---------------------------------------------

    @Test fun aFolderOverTheLimitIsFlaggedTruncated() {
        val many = (1..25).map { file("f$it", "Track $it.mp3") }
        val result = scan(mapOf("root" to many), maxFiles = 20)
        assertTrue(result.truncated)
        assertEquals(20, result.files.size)
    }

    @Test fun aFolderAtTheLimitIsNotTruncated() {
        val exact = (1..20).map { file("f$it", "Track $it.mp3") }
        val result = scan(mapOf("root" to exact), maxFiles = 20)
        assertFalse(result.truncated)
        assertEquals(20, result.files.size)
    }

    @Test fun fiftyFilesInOrderAcrossSubfolders() {
        val folders = mutableMapOf<String, List<TreeEntry>>()
        folders["root"] = (1..5).map { dir("d$it", "Part $it") }.shuffled()
        for (part in 1..5) {
            folders["d$part"] = (1..10).map { file("p$part-$it", "Talk $it.mp3") }.shuffled()
        }
        val result = scan(folders)
        assertEquals(50, result.files.size)
        val expected = (1..5).flatMap { part -> (1..10).map { "Part $part/Talk $it.mp3" } }
        assertEquals(expected, result.paths())
    }

    @Test fun aFolderThatContainsItselfIsWalkedOnce() {
        val tree = FakeTree(
            mapOf(
                "root" to listOf(dir("a", "A"), file("1", "One.mp3")),
                "a" to listOf(dir("root", "Back to the top"), dir("a", "Itself"), file("2", "Two.mp3")),
            ),
        )
        val result = AudioTreeScanner(tree).scan("root")
        assertEquals(listOf("One.mp3", "A/Two.mp3").sorted(), result.paths().sorted())
        assertEquals(1, tree.asked.count { it == "a" })
        assertEquals(1, tree.asked.count { it == "root" })
    }

    @Test fun foldersNestedTooDeepAreReportedAndNotFollowed() {
        val folders = mutableMapOf<String, List<TreeEntry>>("root" to listOf(dir("n1", "n1")))
        for (level in 1..6) {
            folders["n$level"] = listOf(dir("n${level + 1}", "n${level + 1}"), file("f$level", "Level $level.mp3"))
        }
        val result = scan(folders, maxDepth = 4)
        assertEquals(listOf("Level 1.mp3", "Level 2.mp3", "Level 3.mp3"), result.names())
        assertEquals(1, result.unreadableFolders)
    }

    @Test fun cancellingStopsTheScan() {
        var calls = 0
        val tree = object : DocumentTree {
            override fun children(directoryId: String): List<TreeEntry> {
                calls++
                return listOf(dir("again$calls", "More"))
            }
        }
        val scanner = AudioTreeScanner(tree, isCancelled = { calls >= 3 })
        try {
            scanner.scan("root")
            throw AssertionError("expected the scan to be cancelled")
        } catch (e: ScanCancelled) {
            assertEquals(3, calls)
        }
    }

    @Test fun totalBytesIgnoresUnknownSizes() {
        val result = scan(
            mapOf("root" to listOf(file("1", "A.mp3", size = 100), file("2", "B.mp3", size = -1), file("3", "C.mp3", size = 50))),
        )
        assertEquals(150L, result.totalBytes)
    }
}
