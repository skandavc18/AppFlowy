package io.appflowy.appflowy

import android.content.Context
import android.content.res.AssetManager
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Unpacks the built-in office editor, which the APK carries under
 * `assets/office_editor`.
 *
 * AppFlowy serves the editor to a WebView from a loopback dart:io server, and
 * that server can only read real files, so the first time a document opens
 * the assets are copied into app storage. The copy is kept while it matches
 * the bundle in the APK and replaced when an update brings a different one.
 *
 * Methods:
 * - `packaged` says whether the APK carries the editor.
 * - `status` also says whether the `target` folder holds a current copy, and
 *   how large the bundle is.
 * - `extract` makes `target` a current copy (`force` copies regardless) and
 *   calls `progress` on the Dart side while it copies.
 */
class OfficeEditorBundle(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private class BundleException(
        val code: String,
        message: String,
        val details: Any? = null,
    ) : Exception(message)

    private val context: Context = context.applicationContext
    private val assets: AssetManager = this.context.assets
    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "packaged" -> answer(prober, call, result) { readAsset(MANIFEST) != null }
            "status" -> {
                val target = targetOf(call, result) ?: return
                answer(prober, call, result) { status(target) }
            }
            "extract" -> {
                val target = targetOf(call, result) ?: return
                val force = call.argument<Boolean>("force") == true
                answer(unpacker, call, result) { extract(target, force) }
            }
            else -> result.notImplemented()
        }
    }

    /** Runs [work] on [executor] and answers on the main thread, whatever happens. */
    private fun answer(
        executor: ExecutorService,
        call: MethodCall,
        result: MethodChannel.Result,
        work: () -> Any?,
    ) {
        executor.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (error: BundleException) {
                Log.w(TAG, error.message ?: error.code)
                main.post { result.error(error.code, error.message, error.details) }
            } catch (error: Throwable) {
                // Anything else, including running out of memory, must still
                // answer, or the editor would wait forever.
                Log.e(TAG, "Unable to ${call.method} the office editor", error)
                main.post { result.error("failed", error.message ?: error.toString(), null) }
            }
        }
    }

    private fun targetOf(call: MethodCall, result: MethodChannel.Result): File? {
        val target = targetOf(call.argument<String>("target"))
        if (target == null) {
            result.error(
                "invalid_target",
                "The office editor can only be unpacked into app storage.",
                null,
            )
        }
        return target
    }

    /**
     * Only a folder named like the bundle, inside this app's own storage, is
     * ever deleted or replaced.
     */
    private fun targetOf(path: String?): File? {
        if (path.isNullOrEmpty()) return null
        return try {
            val target = File(path).canonicalFile
            val storage = context.dataDir.canonicalFile
            val inside = target.path.startsWith(storage.path + File.separator)
            if (inside && target.name == ASSET_ROOT) target else null
        } catch (error: IOException) {
            null
        }
    }

    private fun status(target: File): Map<String, Any?> {
        val manifest = readAsset(MANIFEST)
            ?: return mapOf("packaged" to false, "installed" to false)
        return mapOf(
            "packaged" to true,
            "installed" to isCurrent(target, identityOf(manifest)),
            "bytes" to bundleBytes(manifest),
        )
    }

    private fun extract(target: File, force: Boolean): Map<String, Any?> {
        val manifest = readAsset(MANIFEST)
            ?: throw BundleException("not_packaged", "This build does not include the office editor.")
        val identity = identityOf(manifest)
        val parent = target.parentFile ?: throw IOException("$target has no parent folder.")
        removeLeftovers(parent, target.name)
        if (!force && isCurrent(target, identity)) {
            return mapOf("path" to target.path, "extracted" to false)
        }

        // Tells Dart a copy is under way before the slower steps below.
        report(0L, 0L)
        // A copy of another bundle is of no further use, and removing it
        // first means unpacking never needs room for two.
        discard(target)
        val files = listAssetFiles()
        val total = files.sumOf { it.second }.takeIf { it > 0 } ?: bundleBytes(manifest) ?: 0L
        ensureSpace(parent, total)

        val staging = File(parent, "${target.name}$PARTIAL${System.currentTimeMillis()}")
        val started = SystemClock.elapsedRealtime()
        try {
            val copied = copyAll(files, staging, total)
            // Written last, so only a finished copy carries it.
            File(staging, MARKER).writeText(
                JSONObject()
                    .put("identity", identity)
                    .put("files", files.size)
                    .put("bytes", copied)
                    .toString(),
            )
            if (!staging.renameTo(target)) {
                throw IOException("Could not move the unpacked office editor into $target.")
            }
            Log.i(
                TAG,
                "Unpacked ${files.size} files (${copied / MB} MB) into $target " +
                    "in ${SystemClock.elapsedRealtime() - started} ms",
            )
            return mapOf(
                "path" to target.path,
                "extracted" to true,
                "files" to files.size,
                "bytes" to copied,
            )
        } catch (error: Throwable) {
            staging.deleteRecursively()
            throw error
        }
    }

    /**
     * Whether [target] holds a finished copy of the bundle [identity] names.
     *
     * The marker is written last and counts the files next to it, so neither
     * a copy that was cut short nor one that lost files since passes.
     */
    private fun isCurrent(target: File, identity: String): Boolean {
        val marker = File(target, MARKER)
        val recorded = try {
            JSONObject(marker.readText())
        } catch (error: Exception) {
            return false
        }
        if (recorded.optString("identity") != identity) return false
        var files = 0
        var bytes = 0L
        target.walkTopDown().filter { it.isFile && it != marker }.forEach { file ->
            files++
            bytes += file.length()
        }
        return files == recorded.optInt("files", -1) && bytes == recorded.optLong("bytes", -1L)
    }

    /** The bundle's manifest and build identity, and how copies are laid out. */
    private fun identityOf(manifest: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update("layout $LAYOUT\n".toByteArray(Charsets.UTF_8))
        for (part in listOf(manifest, readAsset(BUILD_IDENTITY) ?: ByteArray(0))) {
            digest.update("${part.size}\n".toByteArray(Charsets.UTF_8))
            digest.update(part)
        }
        return digest.digest().joinToString("") { byte ->
            ((byte.toInt() and 0xff) + 0x100).toString(16).substring(1)
        }
    }

    /** The unpacked size the fetch tool recorded, if any. */
    private fun bundleBytes(manifest: ByteArray): Long? = try {
        JSONObject(String(manifest, Charsets.UTF_8)).optLong("bytes", 0L).takeIf { it > 0 }
    } catch (error: Exception) {
        null
    }

    private fun readAsset(name: String): ByteArray? = try {
        assets.open("$ASSET_ROOT/$name").use { it.readBytes() }
    } catch (error: IOException) {
        null
    }

    /** Every file of the bundle, relative to it, with its unpacked size. */
    private fun listAssetFiles(): List<Pair<String, Long>> {
        val files = ArrayList<Pair<String, Long>>()
        val pending = ArrayList<String>()
        pending.add("")
        while (pending.isNotEmpty()) {
            val relative = pending.removeAt(pending.size - 1)
            val path = if (relative.isEmpty()) ASSET_ROOT else "$ASSET_ROOT/$relative"
            val children = assets.list(path).orEmpty()
            if (children.isEmpty() && relative.isNotEmpty()) {
                // The APK keeps no empty folders, so this is a file.
                files.add(relative to sizeOf(path))
            } else {
                for (child in children) {
                    pending.add(if (relative.isEmpty()) child else "$relative/$child")
                }
            }
        }
        return files
    }

    private fun sizeOf(path: String): Long =
        assets.open(path, AssetManager.ACCESS_STREAMING).use { it.available().toLong() }

    private fun copyAll(files: List<Pair<String, Long>>, staging: File, total: Long): Long {
        val buffer = ByteArray(BUFFER_BYTES)
        var copied = 0L
        var reported = SystemClock.elapsedRealtime()
        report(0L, total)
        for ((relative, _) in files) {
            if (relative.split('/').any { it.isEmpty() || it == "." || it == ".." }) {
                throw IOException("Unexpected office editor asset $relative.")
            }
            val destination = File(staging, relative)
            destination.parentFile?.mkdirs()
            assets.open("$ASSET_ROOT/$relative", AssetManager.ACCESS_STREAMING).use { input ->
                FileOutputStream(destination).use { output ->
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        copied += read
                        val now = SystemClock.elapsedRealtime()
                        if (now - reported >= REPORT_INTERVAL_MS) {
                            reported = now
                            report(copied, total)
                        }
                    }
                }
            }
        }
        report(copied, total)
        return copied
    }

    private fun ensureSpace(folder: File, bytes: Long) {
        folder.mkdirs()
        val available = StatFs(folder.path).availableBytes
        val required = bytes + SPACE_MARGIN_BYTES
        if (available < required) {
            throw BundleException(
                "no_space",
                "Unpacking the office editor needs ${required / MB} MB, " +
                    "but only ${available / MB} MB are free.",
                mapOf("required" to required, "available" to available),
            )
        }
    }

    /** Copies a crash cut short, and old copies whose removal it did. */
    private fun removeLeftovers(parent: File, name: String) {
        parent.listFiles()?.forEach { file ->
            if (file.name.startsWith(name + PARTIAL) || file.name.startsWith(name + DISCARDED)) {
                file.deleteRecursively()
            }
        }
    }

    private fun discard(target: File) {
        if (!target.exists()) return
        // Moved aside first, so the folder is gone at once even if deleting
        // its contents is interrupted; removeLeftovers finishes that later.
        val aside = File(target.parentFile, "${target.name}$DISCARDED${System.currentTimeMillis()}")
        (if (target.renameTo(aside)) aside else target).deleteRecursively()
    }

    private fun report(copied: Long, total: Long) {
        main.post {
            channel.invokeMethod("progress", mapOf("copied" to copied, "total" to total))
        }
    }

    companion object {
        const val CHANNEL = "io.appflowy.appflowy/office_editor_bundle"

        private const val TAG = "AppFlowyOfficeEditor"
        private const val ASSET_ROOT = "office_editor"
        private const val MANIFEST = "APPFLOWY_BUNDLE.json"
        private const val BUILD_IDENTITY = "build-identity.json"
        private const val MARKER = "APPFLOWY_EXTRACTED.json"
        private const val PARTIAL = ".partial-"
        private const val DISCARDED = ".discarded-"

        /** Bumped when the way copies are made changes, so older ones are redone. */
        private const val LAYOUT = 1

        private const val BUFFER_BYTES = 256 * 1024
        private const val REPORT_INTERVAL_MS = 100L
        private const val MB = 1024L * 1024L
        private const val SPACE_MARGIN_BYTES = 64L * MB

        /**
         * One copy at a time, across activities too: a second request waits,
         * then finds the copy current.
         */
        private val unpacker: ExecutorService =
            Executors.newSingleThreadExecutor { Thread(it, "office-editor-unpack") }

        /** Status checks never wait behind a copy. */
        private val prober: ExecutorService =
            Executors.newSingleThreadExecutor { Thread(it, "office-editor-status") }
    }
}
