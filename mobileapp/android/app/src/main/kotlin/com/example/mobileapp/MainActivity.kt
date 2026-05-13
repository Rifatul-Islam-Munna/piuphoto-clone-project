package com.example.mobileapp

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val otgChannel = "piuphoto/otg_picker"
    private val pickOtgRequest = 4817
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, otgChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImage" -> pickOtgImage(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickOtgImage(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("PICK_IN_PROGRESS", "A file picker is already open", null)
            return
        }

        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivityForResult(intent, pickOtgRequest)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != pickOtgRequest) return

        val result = pendingResult
        pendingResult = null

        if (result == null) return
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return
        }

        try {
            val name = getDisplayName(uri)
            val target = File(cacheDir, "otg_${System.currentTimeMillis()}_$name")
            val inputStream = contentResolver.openInputStream(uri)
                ?: throw IllegalArgumentException("Unable to open selected image")

            inputStream.use { input ->
                FileOutputStream(target).use { output ->
                    input.copyTo(output)
                }
            }

            result.success(
                mapOf(
                    "path" to target.absolutePath,
                    "name" to name
                )
            )
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
