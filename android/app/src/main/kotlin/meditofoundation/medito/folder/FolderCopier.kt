package meditofoundation.medito.folder

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream

/** A staged copy of one audio file. */
data class CopiedFile(
    val path: String,
    /** The original display name, for the title. */
    val name: String,
    val mimeType: String,
    val size: Long,
)

data class CopyResult(
    val copied: List<CopiedFile>,
    /** Display names of files that could not be read and were left out. */
    val skipped: List<String>,
)

/** Where the copy is in its run, for the progress line. */
data class CopyProgress(
    val filesDone: Int,
    val filesTotal: Int,
    val bytesDone: Long,
    val bytesTotal: Long,
    val name: String,
)

/** The user cancelled; everything copied so far has been removed. */
class CopyCancelled : RuntimeException("The copy was cancelled")

/** The device ran out of room while writing. */
class StorageFull(message: String) : IOException(message)

/** Reading one source failed; that file is skipped, the rest go on. */
private class SourceUnreadable(cause: Throwable?) : IOException(cause)

/**
 * Copies picked audio into a staging folder, in order, one file at a time.
 * A file that cannot be read is skipped and reported; running out of room
 * or a cancel removes everything copied and stops.
 *
 * Staged names are `001-name.ext`, so the order survives and two files with
 * the same name never collide; the original name travels separately.
 */
class FolderCopier(
    private val open: (AudioFile) -> InputStream?,
    private val isCancelled: () -> Boolean = { false },
) {
    fun copy(
        files: List<AudioFile>,
        destination: File,
        onProgress: (CopyProgress) -> Unit = {},
    ): CopyResult {
        if (!destination.isDirectory && !destination.mkdirs()) {
            throw IOException("Could not create the staging folder")
        }
        val copied = ArrayList<CopiedFile>()
        val skipped = ArrayList<String>()
        val bytesTotal = files.sumOf { if (it.size > 0) it.size else 0L }
        var bytesDone = 0L
        val width = maxOf(3, files.size.toString().length)

        try {
            files.forEachIndexed { index, file ->
                if (isCancelled()) throw CopyCancelled()
                onProgress(CopyProgress(index, files.size, bytesDone, bytesTotal, file.name))
                val target = File(destination, "%0${width}d-%s".format(index + 1, stagedName(file.name)))
                try {
                    val written = copyOne(file, target) { chunk ->
                        bytesDone += chunk
                        onProgress(CopyProgress(index, files.size, bytesDone, bytesTotal, file.name))
                    }
                    if (written == 0L) throw SourceUnreadable(null)
                    copied.add(CopiedFile(target.absolutePath, file.name, file.mimeType, written))
                } catch (e: SourceUnreadable) {
                    target.delete()
                    skipped.add(file.name)
                }
            }
            onProgress(CopyProgress(files.size, files.size, bytesDone, bytesTotal, ""))
        } catch (e: Throwable) {
            // Cancelled or out of room: leave nothing behind.
            copied.forEach { File(it.path).delete() }
            throw e
        }
        return CopyResult(copied, skipped)
    }

    private fun copyOne(file: AudioFile, target: File, onChunk: (Long) -> Unit): Long {
        val opened: InputStream? = try {
            open(file)
        } catch (e: IOException) {
            throw SourceUnreadable(e)
        } catch (e: SecurityException) {
            throw SourceUnreadable(e)
        } catch (e: IllegalArgumentException) {
            throw SourceUnreadable(e)
        }
        val input: InputStream = opened ?: throw SourceUnreadable(null)

        var written = 0L
        try {
            input.use { source ->
                FileOutputStream(target).use { sink ->
                    val buffer = ByteArray(BUFFER_BYTES)
                    var sinceReport = 0L
                    while (true) {
                        if (isCancelled()) {
                            target.delete()
                            throw CopyCancelled()
                        }
                        val read = try {
                            source.read(buffer)
                        } catch (e: IOException) {
                            throw SourceUnreadable(e)
                        }
                        if (read < 0) break
                        try {
                            sink.write(buffer, 0, read)
                        } catch (e: IOException) {
                            target.delete()
                            throw if (looksLikeFullDisk(e)) StorageFull(e.message ?: "No space left") else e
                        }
                        written += read
                        sinceReport += read
                        if (sinceReport >= REPORT_EVERY_BYTES) {
                            onChunk(sinceReport)
                            sinceReport = 0
                        }
                    }
                    if (sinceReport > 0) onChunk(sinceReport)
                }
            }
        } catch (e: SourceUnreadable) {
            target.delete()
            throw e
        } catch (e: CopyCancelled) {
            target.delete()
            throw e
        }
        return written
    }

    companion object {
        private const val BUFFER_BYTES = 64 * 1024
        private const val REPORT_EVERY_BYTES = 512 * 1024L

        /** A name safe for any file system and short enough for all of them. */
        fun stagedName(name: String): String {
            val cleaned = name.replace(Regex("[^A-Za-z0-9._ -]"), "_").trim().ifEmpty { "audio" }
            if (cleaned.length <= MAX_NAME) return cleaned
            val extension = extensionOf(cleaned)
            val keep = MAX_NAME - (if (extension.isEmpty()) 0 else extension.length + 1)
            val stem = cleaned.substring(0, keep.coerceAtLeast(1))
            return if (extension.isEmpty()) stem else "$stem.$extension"
        }

        private const val MAX_NAME = 100

        internal fun looksLikeFullDisk(e: IOException): Boolean {
            val text = (e.message ?: "").lowercase()
            return "enospc" in text || "no space" in text
        }

        /** Whether [needed] bytes fit in [usable], leaving a margin for the app itself. */
        fun hasRoom(usable: Long, needed: Long, margin: Long = 64L * 1024 * 1024): Boolean =
            usable - needed >= margin
    }
}
