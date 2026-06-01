package com.nikofly.app

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Intent
import android.content.IntentSender
import android.os.Build
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.ArrayDeque

class MainActivity : FlutterFragmentActivity() {
    private val otgChannel = "piuphoto/otg_picker"
    private val settingsChannel = "piuphoto/device_settings"
    private val galleryChannel = "piuphoto/gallery_import"
    private val downloadsChannel = "piuphoto/image_downloads"
    private val pickOtgRequest = 4817
    private val deleteImageRequest = 4818
    private val pickOtgSourceRequest = 4819
    private var pendingResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingSourceResult: MethodChannel.Result? = null
    private var pendingMultiPick = false
    private var otgSourceUri: Uri? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, otgChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImage" -> pickOtgImage(result)
                    "pickImages" -> pickOtgImages(result)
                    "pickSource" -> pickOtgSource(result)
                    "recentSourceImages" -> {
                        val excludeIds = call.argument<List<String>>("excludeIds") ?: emptyList()
                        result.success(copyRecentOtgSourceImages(excludeIds.toSet()))
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openWifiSettings" -> {
                        openWifiSettings(result)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, galleryChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "recentImages" -> {
                        val sinceMs = call.argument<Number>("sinceMs")?.toLong() ?: 0L
                        val excludeIds = call.argument<List<String>>("excludeIds") ?: emptyList()
                        result.success(copyRecentImages(sinceMs, excludeIds.toSet()))
                    }
                    "deleteImage" -> {
                        val id = call.argument<String>("id")
                        if (id == null) {
                            result.error("INVALID_ID", "Image id is required", null)
                        } else {
                            deleteGalleryImage(id, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val filename = call.argument<String>("filename") ?: "event-image.jpg"
                        if (bytes == null) {
                            result.error("INVALID_BYTES", "Image bytes are required", null)
                        } else {
                            result.success(saveImageToPictures(bytes, filename))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openWifiSettings(result: MethodChannel.Result) {
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                Intent(Settings.Panel.ACTION_WIFI)
            } else {
                Intent(Settings.ACTION_WIFI_SETTINGS)
            }
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                result.success(null)
            } catch (fallbackError: Exception) {
                try {
                    startActivity(Intent(Settings.ACTION_SETTINGS))
                    result.success(null)
                } catch (finalError: Exception) {
                    result.error("OPEN_WIFI_FAILED", finalError.message, null)
                }
            }
        }
    }

    private fun pickOtgImage(result: MethodChannel.Result) {
        openOtgPicker(result, false)
    }

    private fun pickOtgImages(result: MethodChannel.Result) {
        openOtgPicker(result, true)
    }

    private fun openOtgPicker(result: MethodChannel.Result, allowMultiple: Boolean) {
        if (pendingResult != null) {
            result.error("PICK_IN_PROGRESS", "A file picker is already open", null)
            return
        }

        pendingResult = result
        pendingMultiPick = allowMultiple
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
        }
        startActivityForResult(intent, pickOtgRequest)
    }

    private fun pickOtgSource(result: MethodChannel.Result) {
        if (pendingSourceResult != null) {
            result.error("PICK_IN_PROGRESS", "A source picker is already open", null)
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        if (intent.resolveActivity(packageManager) == null) {
            result.error("NO_FOLDER_PICKER", "No folder picker available on this device", null)
            return
        }

        pendingSourceResult = result
        startActivityForResult(intent, pickOtgSourceRequest)
    }

    private fun imageUri(id: Long): Uri {
        return ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
    }

    private fun copyRecentImages(sinceMs: Long, excludeIds: Set<String>): List<Map<String, String>> {
        val copied = mutableListOf<Map<String, String>>()
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATE_ADDED
        )
        val sinceSeconds = sinceMs / 1000
        val selection = "${MediaStore.Images.Media.DATE_ADDED} >= ?"
        val selectionArgs = arrayOf(sinceSeconds.toString())
        val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"

        contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            sortOrder
        ).use { cursor ->
            if (cursor == null) return copied

            val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameIndex = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            while (cursor.moveToNext() && copied.size < 10) {
                val id = cursor.getLong(idIndex)
                val idText = id.toString()
                if (excludeIds.contains(idText)) continue

                val name = cursor.getString(nameIndex) ?: "gallery-image-$id.jpg"
                val uri = imageUri(id)
                val target = File(cacheDir, "gallery_${System.currentTimeMillis()}_${id}_$name")
                try {
                    val inputStream = contentResolver.openInputStream(uri) ?: continue
                    inputStream.use { input ->
                        FileOutputStream(target).use { output ->
                            input.copyTo(output)
                        }
                    }
                    copied.add(
                        mapOf(
                            "id" to idText,
                            "path" to target.absolutePath,
                            "name" to name
                        )
                    )
                } catch (_: Exception) {
                }
            }
        }

        return copied
    }

    private fun deleteGalleryImage(id: String, result: MethodChannel.Result) {
        val imageId = id.toLongOrNull()
        if (imageId == null) {
            result.error("INVALID_ID", "Invalid image id", null)
            return
        }

        val uri = imageUri(imageId)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                if (pendingDeleteResult != null) {
                    result.error("DELETE_IN_PROGRESS", "Another delete request is open", null)
                    return
                }
                pendingDeleteResult = result
                val request = MediaStore.createDeleteRequest(contentResolver, listOf(uri))
                startIntentSenderForResult(
                    request.intentSender,
                    deleteImageRequest,
                    null,
                    0,
                    0,
                    0
                )
            } else {
                val deleted = contentResolver.delete(uri, null, null) > 0
                result.success(deleted)
            }
        } catch (error: RecoverableSecurityException) {
            if (pendingDeleteResult != null) {
                result.error("DELETE_IN_PROGRESS", "Another delete request is open", null)
                return
            }
            pendingDeleteResult = result
            try {
                startIntentSenderForResult(
                    error.userAction.actionIntent.intentSender,
                    deleteImageRequest,
                    null,
                    0,
                    0,
                    0
                )
            } catch (sendError: IntentSender.SendIntentException) {
                pendingDeleteResult = null
                result.error("DELETE_FAILED", sendError.message, null)
            }
        } catch (error: Exception) {
            result.error("DELETE_FAILED", error.message, null)
        }
    }

    private fun copyRecentOtgSourceImages(excludeIds: Set<String>): List<Map<String, String>> {
        val sourceUri = otgSourceUri ?: return emptyList()
        val root = DocumentFile.fromTreeUri(this, sourceUri) ?: return emptyList()
        val copied = mutableListOf<Map<String, String>>()
        val stack = ArrayDeque<DocumentFile>()
        stack.add(root)

        while (stack.isNotEmpty() && copied.size < 10) {
            val current = stack.removeFirst()
            val children: Array<DocumentFile> = try {
                current.listFiles()
            } catch (_: Exception) {
                emptyArray<DocumentFile>()
            }

            for (child in children) {
                if (copied.size >= 10) break

                if (child.isDirectory) {
                    stack.addLast(child)
                    continue
                }

                val mimeType = child.type ?: ""
                if (!mimeType.startsWith("image/")) continue

                val uriText = child.uri.toString()
                val lastModified = child.lastModified()
                val length = child.length()
                val id = "$uriText|$lastModified|$length"
                if (excludeIds.contains(id)) continue

                val name = child.name ?: "otg-image-${System.currentTimeMillis()}.jpg"
                val safeName = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
                val target = File(cacheDir, "otg_auto_${System.currentTimeMillis()}_$safeName")

                try {
                    val inputStream = contentResolver.openInputStream(child.uri) ?: continue
                    inputStream.use { input ->
                        FileOutputStream(target).use { output ->
                            input.copyTo(output)
                        }
                    }
                    copied.add(
                        mapOf(
                            "id" to id,
                            "path" to target.absolutePath,
                            "name" to name,
                            "modifiedMs" to lastModified.toString()
                        )
                    )
                } catch (_: Exception) {
                }
            }
        }

        return copied.sortedByDescending { it["modifiedMs"]?.toLongOrNull() ?: 0L }
    }

    private fun saveImageToPictures(bytes: ByteArray, filename: String): Boolean {
        return try {
            val values = android.content.ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, filename)
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/PiuPhoto")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            }

            val uri = contentResolver.insert(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                values
            ) ?: return false

            contentResolver.openOutputStream(uri)?.use { output ->
                output.write(bytes)
            } ?: return false

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val completeValues = android.content.ContentValues().apply {
                    put(MediaStore.Images.Media.IS_PENDING, 0)
                }
                contentResolver.update(uri, completeValues, null, null)
            }

            true
        } catch (_: Exception) {
            false
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == deleteImageRequest) {
            val result = pendingDeleteResult
            pendingDeleteResult = null
            result?.success(resultCode == Activity.RESULT_OK)
            return
        }

        if (requestCode == pickOtgSourceRequest) {
            val result = pendingSourceResult
            pendingSourceResult = null

            if (result == null) return
            if (resultCode != Activity.RESULT_OK) {
                result.success(null)
                return
            }

            val uri = data?.data
            if (uri == null) {
                result.error("NO_OTG_SOURCE", "No source folder was selected", null)
                return
            }

            try {
                val flags = data.flags and
                    (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                contentResolver.takePersistableUriPermission(
                    uri,
                    flags or Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: Exception) {
            }

            otgSourceUri = uri
            val document = DocumentFile.fromTreeUri(this, uri)
            result.success(
                mapOf(
                    "id" to uri.toString(),
                    "name" to (document?.name ?: "OTG source")
                )
            )
            return
        }

        if (requestCode != pickOtgRequest) return

        val result = pendingResult
        pendingResult = null
        val allowMultiple = pendingMultiPick
        pendingMultiPick = false

        if (result == null) return
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        try {
            val uris = mutableListOf<Uri>()
            data?.clipData?.let { clipData ->
                for (index in 0 until clipData.itemCount) {
                    uris.add(clipData.getItemAt(index).uri)
                }
            }
            data?.data?.let { uris.add(it) }

            if (uris.isEmpty()) {
                result.success(null)
                return
            }

            val files = uris.map { uri ->
                val name = getDisplayName(uri)
                val target = File(cacheDir, "otg_${System.currentTimeMillis()}_$name")
                val inputStream = contentResolver.openInputStream(uri)
                    ?: throw IllegalArgumentException("Unable to open selected image")

                inputStream.use { input ->
                    FileOutputStream(target).use { output ->
                        input.copyTo(output)
                    }
                }

                mapOf(
                    "path" to target.absolutePath,
                    "name" to name
                )
            }

            if (allowMultiple) {
                result.success(files)
            } else {
                result.success(files.first())
            }
        } catch (error: Exception) {
            result.error("PICK_FAILED", error.message, null)
        }
    }

    private fun getDisplayName(uri: Uri): String {
        contentResolver.query(uri, null, null, null, null).use { cursor ->
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    return cursor.getString(index)
                }
            }
        }

        return "otg-image-${System.currentTimeMillis()}.jpg"
    }
}
