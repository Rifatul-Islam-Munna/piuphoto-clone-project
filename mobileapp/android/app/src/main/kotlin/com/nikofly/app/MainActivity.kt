package com.airpix.app

import android.app.Activity
import android.app.PendingIntent
import android.app.RecoverableSecurityException
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.IntentSender
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.mtp.MtpDevice
import android.mtp.MtpObjectInfo
import android.os.Build
import android.os.ParcelFileDescriptor
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
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
    private val usbPermissionAction = "com.airpix.app.USB_CAMERA_PERMISSION"
    private var pendingResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingSourceResult: MethodChannel.Result? = null
    private var pendingCameraListResult: MethodChannel.Result? = null
    private var pendingCameraListLimit: Int? = null
    private var pendingMultiPick = false
    private var otgSourceUri: Uri? = null
    private var usbReceiverRegistered = false
    private val cameraUsbHints = setOf(
        "canon", "nikon", "sony", "fujifilm", "fuji", "panasonic", "lumix",
        "olympus", "om digital", "pentax", "ricoh", "leica", "hasselblad",
        "gopro", "dji", "sigma", "kodak", "phase one", "camera"
    )
    private val cameraUsbVendorIds = setOf(
        0x04A9, // Canon
        0x04B0, // Nikon
        0x054C, // Sony
        0x04CB, // Fujifilm
        0x04DA, // Panasonic / Lumix
        0x07B4, // Olympus / OM System legacy USB vendor
        0x05CA, // Ricoh
    )

    private val usbPermissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != usbPermissionAction) return
            val result = pendingCameraListResult ?: return
            val limit = pendingCameraListLimit
            pendingCameraListResult = null
            pendingCameraListLimit = null
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            if (!granted) {
                result.error("USB_PERMISSION_DENIED", "Camera USB permission was denied", null)
                return
            }
            listConnectedCameraImages(limit, result)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (!usbReceiverRegistered) {
            val filter = IntentFilter(usbPermissionAction)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(usbPermissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(usbPermissionReceiver, filter)
            }
            usbReceiverRegistered = true
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, otgChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImage" -> pickOtgImage(result)
                    "pickImages" -> pickOtgImages(result)
                    "connectedCameraDevices" -> listConnectedCameraDevices(result)
                    "connectedCameraImages" -> {
                        val limit = call.argument<Number>("limit")?.toInt()
                        listConnectedCameraImages(limit, result)
                    }
                    "importConnectedCameraImages" -> {
                        val ids = call.argument<List<String>>("ids") ?: emptyList()
                        importConnectedCameraImages(ids, result)
                    }
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

    private fun hasStillImageInterface(device: UsbDevice): Boolean {
        return device.deviceClass == UsbConstants.USB_CLASS_STILL_IMAGE ||
            (0 until device.interfaceCount).any { index ->
                device.getInterface(index).interfaceClass == UsbConstants.USB_CLASS_STILL_IMAGE
            }
    }

    private fun usbDeviceLabel(device: UsbDevice): String {
        val manufacturer = try { device.manufacturerName } catch (_: Exception) { null }
        val product = try { device.productName } catch (_: Exception) { null }
        return listOfNotNull(manufacturer, product)
            .joinToString(" ")
            .ifBlank { "USB ${device.vendorId}:${device.productId}" }
    }

    private fun looksLikeCameraUsbDevice(device: UsbDevice): Boolean {
        if (hasStillImageInterface(device)) return true
        if (device.vendorId in cameraUsbVendorIds) return true
        val label = usbDeviceLabel(device).lowercase()
        return cameraUsbHints.any { hint -> label.contains(hint) }
    }

    private fun cameraUsbDevices(): List<UsbDevice> {
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        // The user explicitly opened the camera/OTG flow, so do not reject an
        // otherwise valid PTP/MTP camera just because it reports a vendor-specific
        // USB class or an unknown vendor ID. Known camera devices stay first; any
        // other attached non-hub USB device is probed as a safe fallback.
        return manager.deviceList.values
            .filter { device -> device.deviceClass != UsbConstants.USB_CLASS_HUB }
            .sortedWith(
                compareByDescending<UsbDevice> { looksLikeCameraUsbDevice(it) }
                    .thenByDescending { hasStillImageInterface(it) }
            )
    }

    private fun supportsDirectMtp(device: UsbDevice): Boolean {
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        if (!manager.hasPermission(device)) return hasStillImageInterface(device)
        val mtp = openMtpDevice(device) ?: return false
        return try {
            mtp.deviceInfo != null || mtp.storageIds != null
        } catch (_: Exception) {
            false
        } finally {
            mtp.close()
        }
    }

    private fun requestCameraUsbPermission(
        device: UsbDevice,
        limit: Int?,
        result: MethodChannel.Result,
    ) {
        if (pendingCameraListResult != null) {
            result.error("USB_PERMISSION_IN_PROGRESS", "Camera permission request is already open", null)
            return
        }
        pendingCameraListResult = result
        pendingCameraListLimit = limit
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        val intent = PendingIntent.getBroadcast(
            this,
            0,
            Intent(usbPermissionAction).setPackage(packageName),
            flags,
        )
        manager.requestPermission(device, intent)
    }

    private fun listConnectedCameraDevices(result: MethodChannel.Result) {
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        val devices = cameraUsbDevices()
        Thread {
            val payload = devices.map { device ->
                val hasPermission = manager.hasPermission(device)
                val directSupported = supportsDirectMtp(device)
                val name = usbDeviceLabel(device)
                Log.i(
                    "PiuPhotoCamera",
                    "USB candidate name=$name id=${device.deviceId} permission=$hasPermission directMtp=$directSupported",
                )
                mapOf(
                    "id" to device.deviceId.toString(),
                    "name" to name,
                    "hasPermission" to hasPermission,
                    "directSupported" to directSupported,
                    "standardPtpClass" to hasStillImageInterface(device),
                )
            }
            runOnUiThread { result.success(payload) }
        }.start()
    }

    private fun listConnectedCameraImages(limit: Int?, result: MethodChannel.Result) {
        val devices = cameraUsbDevices()
        if (devices.isEmpty()) {
            result.success(emptyList<Map<String, String>>())
            return
        }
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        val denied = devices.firstOrNull { !manager.hasPermission(it) }
        if (denied != null) {
            requestCameraUsbPermission(denied, limit, result)
            return
        }
        Thread {
            try {
                val sorted = devices.flatMap { enumerateMtpImages(it) }
                    .sortedWith(
                        compareByDescending<Map<String, String>> {
                            it["modifiedMs"]?.toLongOrNull() ?: 0L
                        }.thenByDescending {
                            it["id"]?.substringAfter('|')?.toLongOrNull() ?: 0L
                        }
                    )
                val images = if (limit != null && limit > 0) sorted.take(limit) else sorted
                Log.i("PiuPhotoCamera", "USB/PTP images found=${images.size} total=${sorted.size} devices=${devices.size} limit=$limit")
                runOnUiThread { result.success(images) }
            } catch (error: Exception) {
                runOnUiThread { result.error("USB_CAMERA_READ_FAILED", error.message, null) }
            }
        }.start()
    }

    private fun openMtpDevice(device: UsbDevice): MtpDevice? {
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        val connection = manager.openDevice(device) ?: return null
        val mtp = MtpDevice(device)
        if (mtp.open(connection)) return mtp
        connection.close()
        return null
    }

    private fun enumerateMtpImages(device: UsbDevice): List<Map<String, String>> {
        val mtp = openMtpDevice(device) ?: return emptyList()
        return try {
            val result = mutableListOf<Map<String, String>>()
            val storageIds = mtp.storageIds ?: intArrayOf()
            for (storageId in storageIds) {
                val handles = mtp.getObjectHandles(storageId, 0, 0) ?: intArrayOf()
                for (handle in handles) {
                    val info = mtp.getObjectInfo(handle) ?: continue
                    val name = info.name ?: continue
                    if (!isCameraImageName(name)) continue
                    result.add(
                        mapOf(
                            "id" to "${device.deviceId}|$handle",
                            "name" to name,
                            "size" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) info.compressedSizeLong else info.compressedSize.toLong()).toString(),
                            "modifiedMs" to info.dateModified.toString(),
                        )
                    )
                }
            }
            result
        } finally {
            mtp.close()
        }
    }

    private fun isCameraImageName(name: String): Boolean {
        val ext = name.substringAfterLast('.', "").lowercase()
        return ext in setOf(
            "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff",
            "dng", "arw", "cr2", "cr3", "nef", "nrw", "raf", "rw2", "orf", "pef"
        )
    }

    private fun importConnectedCameraImages(ids: List<String>, result: MethodChannel.Result) {
        if (ids.isEmpty()) {
            result.success(emptyList<Map<String, String>>())
            return
        }
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        val devices = cameraUsbDevices().associateBy { it.deviceId }
        val requestedDeviceIds = ids.mapNotNull { it.substringBefore('|').toIntOrNull() }.toSet()
        val missingPermission = requestedDeviceIds
            .mapNotNull { devices[it] }
            .firstOrNull { !manager.hasPermission(it) }
        if (missingPermission != null) {
            result.error("USB_PERMISSION_REQUIRED", "Reconnect or tap OTG again to allow camera access", null)
            return
        }

        Thread {
            try {
                val imported = mutableListOf<Map<String, String>>()
                val grouped = ids.mapNotNull { id ->
                    val parts = id.split('|', limit = 2)
                    if (parts.size != 2) null
                    else {
                        val deviceId = parts[0].toIntOrNull()
                        val handle = parts[1].toIntOrNull()
                        if (deviceId == null || handle == null) null else deviceId to handle
                    }
                }.groupBy({ it.first }, { it.second })

                for ((deviceId, handles) in grouped) {
                    val device = devices[deviceId] ?: continue
                    val mtp = openMtpDevice(device) ?: continue
                    try {
                        for (handle in handles) {
                            val info = mtp.getObjectInfo(handle) ?: continue
                            importMtpObject(mtp, deviceId, handle, info)?.let(imported::add)
                        }
                    } finally {
                        mtp.close()
                    }
                }
                runOnUiThread { result.success(imported) }
            } catch (error: Exception) {
                runOnUiThread { result.error("USB_CAMERA_IMPORT_FAILED", error.message, null) }
            }
        }.start()
    }

    private fun importMtpObject(
        mtp: MtpDevice,
        deviceId: Int,
        handle: Int,
        info: MtpObjectInfo,
    ): Map<String, String>? {
        val name = (info.name ?: "camera-image.jpg").replace(Regex("[^A-Za-z0-9._-]"), "_")
        val target = File(cacheDir, "camera_${System.nanoTime()}_$name")
        val copied = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val descriptor = ParcelFileDescriptor.open(
                target,
                ParcelFileDescriptor.MODE_CREATE or
                    ParcelFileDescriptor.MODE_TRUNCATE or
                    ParcelFileDescriptor.MODE_READ_WRITE,
            )
            descriptor.use { mtp.importFile(handle, it) }
        } else {
            val size = info.compressedSize
            if (size <= 0) false
            else {
                val bytes = mtp.getObject(handle, size)
                if (bytes == null) false
                else {
                    FileOutputStream(target).use { it.write(bytes) }
                    true
                }
            }
        }
        if (!copied) {
            target.delete()
            return null
        }
        return mapOf(
            "id" to "$deviceId|$handle",
            "path" to target.absolutePath,
            "name" to name,
        )
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

    override fun onDestroy() {
        if (usbReceiverRegistered) {
            try {
                unregisterReceiver(usbPermissionReceiver)
            } catch (_: Exception) {
            }
            usbReceiverRegistered = false
        }
        super.onDestroy()
    }
}
