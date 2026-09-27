package com.tradeerp.trade_erp

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    /** File waiting for the "save as" screen (Android 9 and older). */
    private var pendingSave: Pair<String, MethodChannel.Result>? = null

    /** Folder the picked file is copied into, and who is waiting for it. */
    private var pendingPick: Pair<String, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "damardash/files").setMethodCallHandler { call, result ->
            when (call.method) {
                // Copies a file of the app into the phone's Downloads folder.
                // Returns {uri, downloads}, or null when the user cancels.
                "saveToDownloads" -> {
                    val path = call.argument<String>("path")!!
                    val name = call.argument<String>("name")!!
                    val mime = call.argument<String>("mime")!!
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        try {
                            result.success(mapOf("uri" to saveWithMediaStore(path, name, mime), "downloads" to true))
                        } catch (e: Exception) {
                            result.error("save_failed", e.message, null)
                        }
                    } else {
                        // No MediaStore downloads before Android 10: the system
                        // "save as" screen needs no storage permission.
                        pendingSave?.second?.success(null)
                        pendingSave = path to result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = mime
                            putExtra(Intent.EXTRA_TITLE, name)
                        }
                        try {
                            startActivityForResult(intent, SAVE_REQUEST)
                        } catch (e: ActivityNotFoundException) {
                            pendingSave = null
                            result.error("save_failed", e.message, null)
                        }
                    }
                }
                // Lets the user pick a file (restoring a backup). The file is
                // copied into the app and its path is returned, or null when
                // the user picks nothing.
                "pickFile" -> {
                    pendingPick?.second?.success(null)
                    pendingPick = call.argument<String>("dir")!! to result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = call.argument<String>("mime") ?: "*/*"
                    }
                    try {
                        startActivityForResult(intent, PICK_REQUEST)
                    } catch (e: ActivityNotFoundException) {
                        pendingPick = null
                        result.error("pick_failed", e.message, null)
                    }
                }
                // Opens a saved file with whatever app the phone has for it.
                "open" -> {
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(Uri.parse(call.argument<String>("uri")!!), call.argument<String>("mime")!!)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    try {
                        startActivity(intent)
                        result.success(true)
                    } catch (e: ActivityNotFoundException) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveWithMediaStore(path: String, name: String, mime: String): String {
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Downloads is not available")
        try {
            contentResolver.openOutputStream(uri)!!.use { out -> File(path).inputStream().use { it.copyTo(out) } }
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            throw e
        }
        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        contentResolver.update(uri, values, null, null)
        return uri.toString()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == PICK_REQUEST) {
            val (dir, result) = pendingPick ?: return
            pendingPick = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) {
                result.success(null)
                return
            }
            try {
                val name = displayName(uri) ?: "backup.json"
                val out = File(dir, name)
                contentResolver.openInputStream(uri)!!.use { input ->
                    out.outputStream().use { input.copyTo(it) }
                }
                result.success(out.absolutePath)
            } catch (e: Exception) {
                result.error("pick_failed", e.message, null)
            }
            return
        }
        if (requestCode != SAVE_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val (path, result) = pendingSave ?: return
        pendingSave = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.openOutputStream(uri)!!.use { out -> File(path).inputStream().use { it.copyTo(out) } }
            result.success(mapOf("uri" to uri.toString(), "downloads" to false))
        } catch (e: Exception) {
            // Don't leave an empty file behind.
            try {
                DocumentsContract.deleteDocument(contentResolver, uri)
            } catch (_: Exception) {
            }
            result.error("save_failed", e.message, null)
        }
    }

    /** The file's own name, so a restored backup keeps it. */
    private fun displayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }

    companion object {
        private const val SAVE_REQUEST = 7301
        private const val PICK_REQUEST = 7302
    }
}
