package meditofoundation.medito.folder

import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.DocumentsContract
import androidx.activity.result.ActivityResultLauncher
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * `meditejo/folder`: importing a folder of audio on Android through the
 * Storage Access Framework. Since Android 11 an app cannot list a folder by
 * path, so the user grants one folder (`ACTION_OPEN_DOCUMENT_TREE`) and the
 * audio inside it is copied into the app's cache, where the ordinary import
 * takes over.
 *
 * Calls, one at a time:
 *  - `pick`     opens the system folder picker. `{treeUri, name}`, or null if
 *               the user backed out.
 *  - `scan`     lists the picked folder's audio (nested folders included, in
 *               natural name order). `{audioCount, totalBytes, entriesSeen,
 *               unreadableFolders, truncated}`. The list stays here.
 *  - `copy`     copies what `scan` found into `cache/folder_import`, off the
 *               main thread, pushing `progress` to Dart as it goes.
 *               `{files:[{path,name,mimeType,size}], skipped:[name]}`.
 *  - `cancel`   stops a scan or copy; it then fails with code `cancelled`.
 *  - `discard`  removes whatever was staged.
 *
 * Errors carry a short code: `busy`, `no_picker`, `no_folder`, `cancelled`,
 * `no_space`, `unreadable`, `copy_failed`. The permission the user granted is
 * temporary on purpose: it is never persisted.
 */
class FolderImportBridge(
    private val context: Context,
    private val scope: CoroutineScope,
) {
    private var channel: MethodChannel? = null
    private var launcher: ActivityResultLauncher<Uri?>? = null
    private var pendingPick: MethodChannel.Result? = null
    private var job: Job? = null

    // Cleared on the main thread just before the answer is sent, so Dart's next
    // call never meets a job that has only just finished.
    private var running = false
    private val cancelled = AtomicBoolean(false)
    private val main = Handler(Looper.getMainLooper())

    // The picked folder and what its scan found; `copy` works from these.
    private var tree: Uri? = null
    @Volatile private var scanned: List<AudioFile> = emptyList()

    private var lastReportAt = 0L
    private var lastReportedFile = -1

    fun attach(messenger: BinaryMessenger, treePicker: ActivityResultLauncher<Uri?>) {
        launcher = treePicker
        channel = MethodChannel(messenger, NAME).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> pick(result)
                    "scan" -> scan(result)
                    "copy" -> copy(result)
                    "cancel" -> {
                        cancelled.set(true)
                        result.success(null)
                    }
                    "discard" -> discard(result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun dispose() {
        cancelled.set(true)
        job?.cancel()
        channel?.setMethodCallHandler(null)
        channel = null
        launcher = null
        pendingPick = null
    }

    /** Delivered by the activity-result launcher given to [attach]. */
    fun onTreePicked(uri: Uri?) {
        val result = pendingPick ?: return
        pendingPick = null
        if (uri == null) {
            result.success(null)
            return
        }
        tree = uri
        scanned = emptyList()
        scope.launch(Dispatchers.IO) {
            val name = displayName(uri)
            withContext(Dispatchers.Main) {
                result.success(mapOf("treeUri" to uri.toString(), "name" to name))
            }
        }
    }

    private fun busy(): Boolean = pendingPick != null || running

    private fun pick(result: MethodChannel.Result) {
        if (busy()) return result.error("busy", "A folder import is already running", null)
        val picker = launcher ?: return result.error("no_picker", "No folder picker is available", null)
        // One cancel flag per import: a Cancel tapped between the calls below
        // must survive until the copy sees it.
        cancelled.set(false)
        pendingPick = result
        try {
            picker.launch(null)
        } catch (e: ActivityNotFoundException) {
            pendingPick = null
            result.error("no_picker", "No folder picker is available", null)
        }
    }

    private fun scan(result: MethodChannel.Result) {
        val picked = tree ?: return result.error("no_folder", "No folder has been picked", null)
        background(result) {
            val scanner = AudioTreeScanner(
                ContentResolverTree(context.contentResolver, picked),
                isCancelled = { cancelled.get() },
            )
            val found = scanner.scan(DocumentsContract.getTreeDocumentId(picked))
            scanned = found.files
            mapOf(
                "audioCount" to found.files.size,
                "totalBytes" to found.totalBytes,
                "entriesSeen" to found.entriesSeen,
                "unreadableFolders" to found.unreadableFolders,
                "truncated" to found.truncated,
            )
        }
    }

    private fun copy(result: MethodChannel.Result) {
        val picked = tree
        val files = scanned
        if (picked == null || files.isEmpty()) {
            return result.error("no_folder", "There is nothing to copy", null)
        }
        background(result) {
            val staging = File(context.cacheDir, STAGING_DIR)
            staging.deleteRecursively()
            val needed = files.sumOf { if (it.size > 0) it.size else 0L }
            if (!FolderCopier.hasRoom(context.cacheDir.usableSpace, needed)) {
                throw StorageFull("Not enough free space for $needed bytes")
            }
            lastReportAt = 0
            lastReportedFile = -1
            val copier = FolderCopier(
                open = { file ->
                    context.contentResolver.openInputStream(
                        DocumentsContract.buildDocumentUriUsingTree(picked, file.documentId),
                    )
                },
                isCancelled = { cancelled.get() },
            )
            val copied = copier.copy(files, staging) { report(it) }
            mapOf(
                "files" to copied.copied.map {
                    mapOf(
                        "path" to it.path,
                        "name" to it.name,
                        "mimeType" to it.mimeType,
                        "size" to it.size,
                    )
                },
                "skipped" to copied.skipped,
            )
        }
    }

    private fun discard(result: MethodChannel.Result) {
        if (running) {
            // The running copy removes its own files when it stops.
            cancelled.set(true)
        } else {
            File(context.cacheDir, STAGING_DIR).deleteRecursively()
            scanned = emptyList()
        }
        result.success(null)
    }

    /** Runs [work] off the main thread and answers [result] on it. */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        if (busy()) return result.error("busy", "A folder import is already running", null)
        running = true
        job = scope.launch(Dispatchers.IO) {
            val outcome = runCatching { work() }
            withContext(Dispatchers.Main) {
                running = false
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { fail(result, it) },
                )
            }
        }
    }

    private fun fail(result: MethodChannel.Result, error: Throwable) {
        val message = error.message
        when (error) {
            is ScanCancelled, is CopyCancelled -> result.error("cancelled", message, null)
            is StorageFull -> result.error("no_space", message, null)
            is SecurityException -> result.error("unreadable", message, null)
            is IOException -> result.error("copy_failed", message, null)
            else -> result.error("copy_failed", message, null)
        }
    }

    /** Progress to Dart, at most a few times a second. */
    private fun report(progress: CopyProgress) {
        val now = SystemClock.elapsedRealtime()
        val newFile = progress.filesDone != lastReportedFile
        if (!newFile && now - lastReportAt < REPORT_INTERVAL_MS) return
        lastReportAt = now
        lastReportedFile = progress.filesDone
        val payload = mapOf(
            "filesDone" to progress.filesDone,
            "filesTotal" to progress.filesTotal,
            "bytesDone" to progress.bytesDone,
            "bytesTotal" to progress.bytesTotal,
            "name" to progress.name,
        )
        main.post { channel?.invokeMethod("progress", payload) }
    }

    private fun displayName(treeUri: Uri): String {
        val rootId = try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (e: Exception) {
            return treeUri.lastPathSegment ?: ""
        }
        try {
            context.contentResolver.query(
                DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId),
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val name = cursor.getString(0)
                    if (!name.isNullOrBlank()) return name
                }
            }
        } catch (e: Exception) {
            // Fall through to the document ID.
        }
        return rootId.substringAfterLast('/').substringAfterLast(':')
    }

    companion object {
        const val NAME = "meditejo/folder"

        /** Under the app's cache, so the system may reclaim it and Dart treats it as temporary. */
        const val STAGING_DIR = "folder_import"
        private const val REPORT_INTERVAL_MS = 150L
    }
}

/** Reads a picked tree through `DocumentsContract`, one query per folder. */
internal class ContentResolverTree(
    private val resolver: ContentResolver,
    private val treeUri: Uri,
) : DocumentTree {
    override fun children(directoryId: String): List<TreeEntry> {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, directoryId)
        val cursor = resolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
            ),
            null,
            null,
            null,
        ) ?: throw IOException("The folder could not be listed")
        val entries = ArrayList<TreeEntry>()
        cursor.use {
            while (it.moveToNext()) {
                val id = it.getString(0) ?: continue
                entries.add(
                    TreeEntry(
                        documentId = id,
                        name = it.getString(1) ?: "",
                        mimeType = it.getString(2) ?: "",
                        size = if (it.isNull(3)) -1L else it.getLong(3),
                    ),
                )
            }
        }
        return entries
    }
}
