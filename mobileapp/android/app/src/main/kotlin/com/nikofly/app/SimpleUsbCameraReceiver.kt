package com.nikofly.app

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.mtp.MtpDevice
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/**
 * USB enumeration and MTP/PTP file access ONLY after the user starts receiving.
 * Never sends capture commands, proprietary remote commands, or Mass Storage.
 * A camera may still enter import mode when its firmware exposes MTP/PTP.
 */
internal class SimpleUsbCameraReceiver(private val activity: MainActivity) : EventChannel.StreamHandler {
    private val manager = activity.getSystemService(Context.USB_SERVICE) as UsbManager
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor { task ->
        Thread(task, "airpix-usb-mtp-reader").apply { isDaemon = true }
    }
    private val permissionAction = "${activity.packageName}.SIMPLE_CAMERA_PERMISSION"
    private var receiverRegistered = false
    private var sink: EventChannel.EventSink? = null
    private var sessionId: String? = null
    private var selected: UsbDevice? = null
    private var uploadMode = "newShotsOnly"
    private var opening: MethodChannel.Result? = null
    private var ready = false
    private var closing = false
    private val stopCallbacks = arrayListOf<(String?) -> Unit>()

    // Only the single USB worker owns this mutable photo catalog.
    private var mtp: MtpDevice? = null
    private val seen = hashSetOf<String>()
    private val pending = linkedMapOf<String, Photo>()
    private val staged = hashMapOf<String, File>()
    private data class Photo(val id: String, val handle: Int, val name: String, val size: Long)

    private val poll = object : Runnable {
        override fun run() {
            val token = sessionId ?: return
            if (!ready || closing) return
            io.execute {
                try {
                    val changed = scanNewPhotos()
                    main.post {
                        if (sessionId == token && ready && !closing) {
                            if (changed) emit("photosAvailable")
                            main.postDelayed(this, 1500L)
                        }
                    }
                } catch (error: Exception) {
                    main.post {
                        if (sessionId == token && !closing) {
                            emit("error", "Camera read failed: ${error.message}", "CAMERA_READ_FAILED")
                            stop(token) { }
                        }
                    }
                }
            }
        }
    }

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != permissionAction) return
            val target = selected ?: return
            val token = sessionId ?: return
            if (!manager.hasPermission(target)) {
                fail("USB_PERMISSION_DENIED", "USB access was denied.")
                return
            }
            openOnWorker(target, token)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
    override fun onCancel(arguments: Any?) {
        sink = null
        // Flutter cancels its listener before invoking explicit stop().
        // Defer lost-listener cleanup so the method call can await close.
        val token = sessionId
        main.postDelayed({
            if (sink == null && token != null && sessionId == token) {
                stop(token) { }
            }
        }, 1200L)
    }

    private fun emit(type: String, message: String = "", code: String? = null) {
        val id = sessionId ?: return
        val payload = mutableMapOf<String, Any>("sessionId" to id, "type" to type, "message" to message)
        if (code != null) payload["code"] = code
        sink?.success(payload)
    }

    private fun isCamera(device: UsbDevice): Boolean =
        device.deviceClass == UsbConstants.USB_CLASS_STILL_IMAGE ||
            (0 until device.interfaceCount).any {
                device.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_STILL_IMAGE
            }

    fun start(args: Map<*, *>?, result: MethodChannel.Result) {
        if (sessionId != null || closing) {
            result.error("LIVE_CAMERA_BUSY", "A USB camera session is already running or closing.", null)
            return
        }
        val token = args?.get("sessionId") as? String
        if (token.isNullOrBlank()) {
            result.error("LIVE_CAMERA_INVALID_SESSION", "Missing camera session ID.", null)
            return
        }
        // No USB enumeration ever occurs on MainActivity creation or app launch.
        val candidates = manager.deviceList.values.filter(::isCamera)
        if (candidates.isEmpty()) {
            result.error("NO_CAMERA_CONNECTED",
                "No USB still-image/PTP camera is visible. Check cable, adapter, and camera connection mode.", null)
            return
        }
        val device = candidates.first()
        selected = device
        sessionId = token
        ready = false
        opening = result
        uploadMode = if (args["uploadMode"] == "existingAndNew") "existingAndNew" else "newShotsOnly"
        emit("status", "Checking camera USB permission.")
        if (!manager.hasPermission(device)) {
            val filter = IntentFilter(permissionAction)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.registerReceiver(permissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                activity.registerReceiver(permissionReceiver, filter)
            }
            receiverRegistered = true
            val intent = Intent(permissionAction).setPackage(activity.packageName)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            val permission = PendingIntent.getBroadcast(activity, 0, intent, flags)
            manager.requestPermission(device, permission)
        } else {
            openOnWorker(device, token)
        }
    }

    private fun openOnWorker(device: UsbDevice, token: String) {
        emit("status", "Opening camera photo catalog.")
        io.execute {
            var opened: MtpDevice? = null
            try {
                val connection = manager.openDevice(device)
                    ?: throw IllegalStateException("Android could not open this USB camera.")
                opened = MtpDevice(device)
                if (!opened.open(connection)) {
                    connection.close()
                    throw IllegalStateException("MTP/PTP photo access is unavailable in this USB mode.")
                }
                mtp = opened
                seen.clear()
                pending.clear()
                staged.clear()
                val snapshot = collectPhotos(opened)
                for (photo in snapshot) {
                    seen.add(photo.id)
                    if (uploadMode == "existingAndNew") pending[photo.id] = photo
                }
                val count = snapshot.size
                main.post {
                    if (sessionId != token || closing) return@post
                    ready = true
                    val callback = opening
                    opening = null
                    callback?.success(mapOf(
                        "sessionId" to token,
                        "cameraId" to "${device.vendorId}:${device.productId}:${device.deviceId}",
                        "name" to (device.productName ?: device.deviceName),
                        "physicalShutter" to "unknown",
                        "baselineCount" to count,
                        "uploadMode" to uploadMode,
                        "message" to "Photo catalog available. Take a TEST photo using the camera shutter. If the camera display locks, stop and select a shooting-compatible camera USB mode."
                    ))
                    emit("status", "Watching for new saved photos.")
                    if (pending.isNotEmpty()) emit("photosAvailable")
                    main.removeCallbacks(poll)
                    main.postDelayed(poll, 1500L)
                }
            } catch (error: Exception) {
                try { opened?.close() } catch (_: Exception) {}
                mtp = null
                main.post {
                    if (sessionId == token && !closing) {
                        fail("CAMERA_SESSION_FAILED", error.message ?: "Unable to read camera files.")
                    }
                }
            }
        }
    }

    private fun collectPhotos(device: MtpDevice): List<Photo> {
        val photos = arrayListOf<Photo>()
        for (storage in (device.storageIds ?: intArrayOf())) {
            val handles = device.getObjectHandles(storage, 0, 0) ?: continue
            for (handle in handles) {
                val info = try { device.getObjectInfo(handle) } catch (_: Exception) { null } ?: continue
                val name = info.name ?: continue
                if (!isPhoto(name)) continue
                val size = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    info.compressedSizeLong
                } else {
                    (info.compressedSize.toLong() and 0xffffffffL)
                }
                if (size <= 0L) continue
                photos.add(Photo("$handle:$name:${info.dateCreated}", handle, name, size))
            }
        }
        return photos
    }

    private fun isPhoto(name: String): Boolean {
        val lower = name.lowercase()
        return listOf(".jpg", ".jpeg", ".heic", ".heif", ".png", ".tif", ".tiff",
            ".dng", ".cr2", ".cr3", ".nef", ".nrw", ".arw", ".raf",
            ".rw2", ".orf", ".pef", ".srw").any { lower.endsWith(it) }
    }

    private fun scanNewPhotos(): Boolean {
        val device = mtp ?: return false
        var found = false
        for (photo in collectPhotos(device)) {
            if (seen.add(photo.id)) {
                pending[photo.id] = photo
                found = true
            }
        }
        return found
    }

    fun pending(token: String?, result: MethodChannel.Result) {
        if (token != sessionId || !ready || closing) {
            result.error("LIVE_CAMERA_NOT_RUNNING", "Start a USB receiving session first.", null)
            return
        }
        io.execute {
            val snapshot = pending.values.map { mapOf("id" to it.id, "name" to it.name, "size" to it.size) }
            main.post {
                if (sessionId == token && !closing) result.success(snapshot)
                else result.error("LIVE_CAMERA_SESSION_ENDED", "Camera session ended.", null)
            }
        }
    }

    fun download(token: String?, imageID: String?, result: MethodChannel.Result) {
        if (token != sessionId || !ready || closing || imageID.isNullOrBlank()) {
            result.error("LIVE_CAMERA_NOT_RUNNING", "The camera receiving session is not active.", null)
            return
        }
        io.execute {
            val photo = pending[imageID]
            if (photo == null) {
                main.post { result.error("CAMERA_IMAGE_NOT_FOUND", "This camera photo is no longer available.", null) }
                return@execute
            }
            val existing = staged[imageID]
            if (existing != null && existing.exists() && existing.length() > 0) {
                main.post { result.success(mapOf("id" to photo.id, "name" to photo.name, "path" to existing.absolutePath)) }
                return@execute
            }
            val name = photo.name.replace(Regex("[^A-Za-z0-9._-]"), "_").take(100)
            val dest = File(activity.cacheDir, "airpix_${UUID.randomUUID()}_$name")
            try {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
                    throw IllegalStateException("Camera file transfer requires Android 7.0 or later.")
                }
                val descriptor = ParcelFileDescriptor.open(dest,
                    ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_TRUNCATE or ParcelFileDescriptor.MODE_WRITE_ONLY)
                val success = descriptor.use { fd ->
                    (mtp ?: throw IllegalStateException("Camera disconnected.")).importFile(photo.handle, fd)
                }
                if (!success || !dest.exists() || dest.length() == 0L) {
                    throw IllegalStateException("The camera did not deliver a complete photo.")
                }
                staged[imageID] = dest
                main.post {
                    if (sessionId == token && !closing) {
                        result.success(mapOf("id" to photo.id, "name" to photo.name, "path" to dest.absolutePath))
                    } else {
                        dest.delete()
                        result.error("LIVE_CAMERA_SESSION_ENDED", "The camera session ended.", null)
                    }
                }
            } catch (error: Exception) {
                dest.delete()
                main.post { result.error("CAMERA_IMPORT_FAILED", error.message, null) }
            }
        }
    }

    fun acknowledge(token: String?, ids: List<String>, result: MethodChannel.Result) {
        if (token != sessionId || closing) {
            result.error("LIVE_CAMERA_SESSION_ENDED", "The camera receiving session ended.", null)
            return
        }
        io.execute {
            for (id in ids) {
                pending.remove(id)
                staged.remove(id)?.delete()
            }
            main.post { result.success(null) }
        }
    }

    fun stop(token: String?, result: (String?) -> Unit) {
        if (sessionId == null) { result(null); return }
        if (token != null && token != sessionId) { result("LIVE_CAMERA_SESSION_MISMATCH"); return }
        if (closing) { stopCallbacks.add(result); return }
        closing = true
        stopCallbacks.add(result)
        val pendingStart = opening
        opening = null
        pendingStart?.error("LIVE_CAMERA_CANCELLED", "Camera receiving stopped.", null)
        main.removeCallbacks(poll)
        if (receiverRegistered) {
            try { activity.unregisterReceiver(permissionReceiver) } catch (_: Exception) {}
            receiverRegistered = false
        }
        io.execute {
            try { mtp?.close() } catch (_: Exception) {}
            mtp = null
            seen.clear()
            pending.clear()
            staged.clear()
            main.post {
                sessionId = null
                selected = null
                ready = false
                closing = false
                val callbacks = stopCallbacks.toList()
                stopCallbacks.clear()
                callbacks.forEach { it(null) }
            }
        }
    }

    private fun fail(code: String, message: String) {
        emit("error", message, code)
        opening?.error(code, message, null)
        opening = null
        stop(sessionId) { }
    }

    fun destroy() {
        main.removeCallbacks(poll)
        stop(sessionId) { io.shutdown() }
        if (sessionId == null) io.shutdown()
    }

    fun activeDevices(): List<Map<String, Any?>> {
        val camera = selected ?: return emptyList()
        if (!ready || closing) return emptyList()
        return listOf(mapOf("id" to camera.deviceId.toString(),
            "name" to (camera.productName ?: camera.deviceName),
            "hasPermission" to true, "directSupported" to true))
    }
}
