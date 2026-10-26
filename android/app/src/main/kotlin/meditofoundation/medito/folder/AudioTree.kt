package meditofoundation.medito.folder

import java.io.IOException

/** The MIME type Android's document providers give a directory. */
const val DIRECTORY_MIME = "vnd.android.document/directory"

/** One document inside a picked tree, as a provider describes it. */
data class TreeEntry(
    val documentId: String,
    val name: String,
    val mimeType: String,
    /** Bytes, or -1 when the provider does not say. */
    val size: Long,
) {
    val isDirectory: Boolean get() = mimeType == DIRECTORY_MIME
}

/** The only thing the scanner needs from Android: the children of a directory. */
interface DocumentTree {
    /** The directory's children. Throws [IOException] (or a security error) when it cannot be read. */
    @Throws(IOException::class)
    fun children(directoryId: String): List<TreeEntry>
}

/** An audio file found in a tree, with the folders above it. */
data class AudioFile(
    val documentId: String,
    val name: String,
    val mimeType: String,
    val size: Long,
    /** Folder names from the picked folder down to this file, ending with its own name. */
    val relativePath: List<String>,
)

data class ScanResult(
    /** Natural name order, folder by folder. */
    val files: List<AudioFile>,
    /** Every visible document looked at; zero means the folder is empty. */
    val entriesSeen: Int,
    /** Folders the provider would not list, or that were nested too deep. */
    val unreadableFolders: Int,
    /** The folder holds more audio than [AudioTreeScanner.maxFiles]; [files] is then incomplete. */
    val truncated: Boolean,
) {
    val totalBytes: Long get() = files.sumOf { if (it.size > 0) it.size else 0L }
}

/** Thrown from [AudioTreeScanner.scan] when the user cancels. */
class ScanCancelled : RuntimeException("The scan was cancelled")

/**
 * Walks a document tree, recursing into subfolders, and collects its audio by
 * MIME type and by extension. Hidden entries (a leading dot: macOS `._` files,
 * Android's `.trashed-…`) are skipped, as are playlist files that merely carry
 * an audio MIME type.
 */
class AudioTreeScanner(
    private val tree: DocumentTree,
    val maxFiles: Int = MAX_FILES,
    private val maxDepth: Int = MAX_DEPTH,
    private val isCancelled: () -> Boolean = { false },
) {
    fun scan(rootId: String): ScanResult {
        val found = ArrayList<AudioFile>()
        val visited = HashSet<String>()
        var entriesSeen = 0
        var unreadable = 0
        var truncated = false

        // Depth-first, but order is decided afterwards, so the stack order is free.
        val stack = ArrayDeque<Pair<String, List<String>>>()
        stack.addLast(rootId to emptyList())
        visited.add(rootId)

        walk@ while (stack.isNotEmpty()) {
            if (isCancelled()) throw ScanCancelled()
            val (directoryId, path) = stack.removeLast()
            val children = try {
                tree.children(directoryId)
            } catch (e: Exception) {
                // One folder the provider refuses must not lose the rest.
                if (e is ScanCancelled) throw e
                unreadable++
                continue
            }
            for (child in children) {
                if (child.name.startsWith(".")) continue
                entriesSeen++
                if (child.isDirectory) {
                    if (path.size + 1 >= maxDepth) {
                        unreadable++
                    } else if (visited.add(child.documentId)) {
                        stack.addLast(child.documentId to (path + child.name))
                    }
                } else if (isAudio(child.name, child.mimeType)) {
                    if (found.size >= maxFiles) {
                        truncated = true
                        break@walk
                    }
                    found.add(
                        AudioFile(
                            documentId = child.documentId,
                            name = child.name,
                            mimeType = child.mimeType,
                            size = child.size,
                            relativePath = path + child.name,
                        ),
                    )
                }
            }
        }
        found.sortWith { a, b -> NaturalOrder.comparePaths(a.relativePath, b.relativePath) }
        return ScanResult(found, entriesSeen, unreadable, truncated)
    }

    companion object {
        /** More than this is a music library, not a course; the importer says so. */
        const val MAX_FILES = 1000
        const val MAX_DEPTH = 16
    }
}

private val AUDIO_EXTENSIONS = setOf(
    "mp3", "m4a", "aac", "ogg", "oga", "opus", "wav", "flac", "m4b", "wma", "weba",
)

/** Playlists and cue sheets some providers type as audio. */
private val NOT_AUDIO_EXTENSIONS = setOf("m3u", "m3u8", "pls", "cue", "xspf")
private val NOT_AUDIO_MIME = setOf(
    "audio/x-mpegurl", "audio/mpegurl", "application/vnd.apple.mpegurl", "audio/x-scpls",
    "application/x-mpegurl", "application/xspf+xml",
)

fun extensionOf(name: String): String {
    val dot = name.lastIndexOf('.')
    return if (dot < 0 || dot == name.length - 1) "" else name.substring(dot + 1).lowercase()
}

/** Audio by MIME type or by extension, never a playlist. */
fun isAudio(name: String, mimeType: String): Boolean {
    val mime = mimeType.lowercase()
    val extension = extensionOf(name)
    if (extension in NOT_AUDIO_EXTENSIONS || mime in NOT_AUDIO_MIME) return false
    return mime.startsWith("audio/") || mime == "application/ogg" || extension in AUDIO_EXTENSIONS
}

/** "Session 2" before "Session 10", ignoring case; digits compare by value. */
object NaturalOrder : Comparator<String> {
    override fun compare(a: String, b: String): Int {
        var i = 0
        var j = 0
        while (i < a.length && j < b.length) {
            val x = a[i]
            val y = b[j]
            if (x.isDigit() && y.isDigit()) {
                val endA = digitRunEnd(a, i)
                val endB = digitRunEnd(b, j)
                val runA = a.substring(i, endA).trimStart('0')
                val runB = b.substring(j, endB).trimStart('0')
                if (runA.length != runB.length) return runA.length.compareTo(runB.length)
                val byDigits = runA.compareTo(runB)
                if (byDigits != 0) return byDigits
                i = endA
                j = endB
            } else {
                val lx = x.lowercaseChar()
                val ly = y.lowercaseChar()
                if (lx != ly) return lx.compareTo(ly)
                i++
                j++
            }
        }
        val remaining = (a.length - i).compareTo(b.length - j)
        if (remaining != 0) return remaining
        // Same up to case and leading zeros: keep the order stable.
        return a.compareTo(b)
    }

    private fun digitRunEnd(text: String, from: Int): Int {
        var end = from
        while (end < text.length && text[end].isDigit()) end++
        return end
    }

    /** Folder by folder, so "Week 2/Session 1" comes before "Week 10/Session 1". */
    fun comparePaths(a: List<String>, b: List<String>): Int {
        for (k in 0 until minOf(a.size, b.size)) {
            val c = compare(a[k], b[k])
            if (c != 0) return c
        }
        return a.size.compareTo(b.size)
    }
}
