package com.nikofly.app

import android.app.Activity
import android.app.PendingIntent
import android.app.RecoverableSecurityException
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.IntentSender
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.mtp.MtpDevice
import android.mtp.MtpEvent
import android.mtp.MtpObjectInfo
import android.os.Build
import android.os.CancellationSignal
import android.os.OperationCanceledException
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.FileOutputStream
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.security.MessageDigest

class MainActivity : FlutterFragmentActivity() {
    private val otgChannel = "airpix/otg_picker"
    private val settingsChannel = "airpix/device_settings"
    private val galleryChannel = "airpix/gallery_import"
    private val downloadsChannel = "airpix/image_downloads"
    private val pickOtgRequest = 4817
    private val deleteImageRequest = 4818
    private val pickOtgSourceRequest = 4819
    private val usbPermissionAction = "com.nikofly.app.USB_CAMERA_PERMISSION"
    private val liveUsbPermissionAction = "com.nikofly.app.LIVE_USB_CAMERA_PERMISSION"
    private val ptpUsbPermissionAction = "com.nikofly.app.PTP_TETHER_USB_PERMISSION"
    // PTP transactions share one command/data endpoint. Event reads use the
    // separate interrupt endpoint and must never block this command executor.
    private val cameraIo = Executors.newSingleThreadExecutor { task ->
        Thread(task, "AirPixUsbCommands").apply { isDaemon = true }
    }
    @Volatile private var activityDestroyed = false
    private val manualCameraOperations = AtomicInteger(0)
    private val ptpTether by lazy {
        PtpTetherController(this, cameraIo, ptpUsbPermissionAction,
            destroyed = { activityDestroyed },
            setAwake = { owner, enabled -> setScreenAwake(owner, enabled) },
            emit = { payload ->
                runOnUiThread {
                    if (!activityDestroyed && (liveEventSinkSessionId == null || liveEventSinkSessionId == payload["sessionId"])) {
                        liveEventSink?.success(payload)
                    }
                }
            },
        )
    }
    @Volatile private var pendingLiveStart: PendingLiveStart? = null
    @Volatile private var liveCameraSession: LiveCameraSession? = null
    private var liveEventSink: EventChannel.EventSink? = null
    private var liveEventSinkSessionId: String? = null
    private val screenAwakeOwners = mutableSetOf<String>()
    private var previousScreenOnFlag = false
    // Accessed only by cameraIo. A cable unplug must not remove a staging file
    // while Dart is copying it into its durable, event-scoped upload queue.
    private val stagedLiveDownloads = hashMapOf<String, MutableMap<String, String>>()
    private var pendingResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingSourceResult: MethodChannel.Result? = null
    private var pendingCameraListResult: MethodChannel.Result? = null
    private var pendingCameraListLimit: Int? = null
    private var pendingMultiPick = false
    private var otgSourceUri: Uri? = null
    private var usbReceiverRegistered = false

    private class LiveCameraException(val code: String, message: String) : Exception(message)

    private class PendingLiveStart(
        val id: String,
        val device: UsbDevice,
        val result: MethodChannel.Result,
    ) {
        val cancelled = AtomicBoolean(false)
        val completed = AtomicBoolean(false)
        val opening = AtomicBoolean(false)
    }

    private class LiveCameraImage(
        val id: String,
        val handle: Int,
        var info: MtpObjectInfo,
    ) {
        var removed = false
        var downloaded: Map<String, String>? = null
    }

    private class LiveCameraSession(
        val id: String,
        val device: UsbDevice,
        val mtp: MtpDevice,
        val cameraId: String,
        val name: String,
        val storageIds: Set<Int>,
        initialHandles: Set<Int>,
        val supportsObjectEvents: Boolean?,
        val supportsHostTransferEvents: Boolean?,
        val supportsRemoteCapture: Boolean?,
    ) {
        val stopped = AtomicBoolean(false)
        val closed = AtomicBoolean(false)
        val eventCancellation = CancellationSignal()
        // Every existing handle is baselined, including files beyond the first
        // 500 and formats the app cannot upload. No old card photos are armed.
        val baselineHandles = initialHandles.toMutableSet()
        val observedHandles = initialHandles.toMutableSet()
        val baselineCount = initialHandles.size
        val unresolvedHandles = linkedSetOf<Int>()
        val pending = linkedMapOf<String, LiveCameraImage>()
        val pendingByHandle = hashMapOf<Int, String>()
        val acknowledgedIds = hashSetOf<String>()
        var lastReconcileMs = SystemClock.elapsedRealtime()
        @Volatile var pendingCount = 0
        @Volatile var eventReaderRunning = false
    }
    // Selected manually by the photographer after inspecting USB diagnostics.
    // Never probe arbitrary accessories without an explicit tap.
    private var manuallySelectedUsbDeviceId: Int? = null
    private val cameraUsbHints = setOf(
        "canon", "nikon", "sony", "fujifilm", "fuji", "panasonic", "lumix",
        "olympus", "om digital", "pentax", "ricoh", "leica", "hasselblad",
        "gopro", "dji", "sigma", "kodak", "phase one", "camera", "ptp", "mtp", "imaging"
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
            if (intent?.action == UsbManager.ACTION_USB_DEVICE_DETACHED) {
                val device = usbDeviceFromIntent(intent) ?: return
                ptpTether.detached(device)
                pendingLiveStart?.takeIf { it.device.deviceId == device.deviceId }?.let {
                    cancelPendingLiveStart(it, "USB_CAMERA_DISCONNECTED", "The camera disconnected while live shooting was starting.")
                }
                liveCameraSession?.takeIf { it.device.deviceId == device.deviceId }?.let {
                    disconnectLiveCamera(it, "USB_CAMERA_DISCONNECTED", "USB camera disconnected. Reconnect it and start live shooting again.")
                }
                return
            }
            if (intent?.action == ptpUsbPermissionAction) {
                ptpTether.permissionResult(intent.getStringExtra("ptpSessionId"), usbDeviceFromIntent(intent),
                    intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false))
                return
            }
            if (intent?.action == liveUsbPermissionAction) {
                val request = pendingLiveStart ?: return
                if (intent.getStringExtra("liveSessionId") != request.id || request.cancelled.get()) return
                val device = usbDeviceFromIntent(intent) ?: return
                if (device.deviceId != request.device.deviceId) return
                if (!intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                    cancelPendingLiveStart(request, "USB_PERMISSION_DENIED", "USB camera access was denied. Start live shooting again and allow access.")
                    return
                }
                openLiveCameraSession(request)
                return
            }
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
            val filter = IntentFilter(usbPermissionAction).apply {
                addAction(liveUsbPermissionAction)
                addAction(ptpUsbPermissionAction)
                addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(usbPermissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(usbPermissionReceiver, filter)
            }
            usbReceiverRegistered = true
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "airpix/otg_live")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val sessionId = (arguments as? Map<*, *>)?.get("sessionId")?.toString()
                    liveEventSink = events
                    liveEventSinkSessionId = sessionId
                    liveCameraSession?.takeIf { sessionId == null || it.id == sessionId }?.let { session ->
                        emitLiveEvent(session.id, "status", "waiting-for-shot", liveCameraMessage())
                    }
                }

                override fun onCancel(arguments: Any?) {
                    // Flutter supplies null when replacing a listener during
                    // hot restart. That cancellation owns the current sink.
                    val sessionId = (arguments as? Map<*, *>)?.get("sessionId")?.toString()
                        ?: liveEventSinkSessionId
                    // An old controller may cancel after a new one subscribes.
                    // Never clear the new controller's listener in that case.
                    if (sessionId != liveEventSinkSessionId) return
                    liveEventSink = null
                    liveEventSinkSessionId = null
                    ptpTether.listenerClosed(sessionId)
                    // A disposed/hot-restarted Dart controller must not leave
                    // its camera claimed. Completed staging files are retained
                    // by disconnectLiveCamera until their delivery is acked.
                    pendingLiveStart?.takeIf { it.id == sessionId }?.let {
                        cancelPendingLiveStart(it, "CAMERA_SESSION_CANCELLED", "Live shooting stopped when its listener closed.")
                    }
                    liveCameraSession?.takeIf { it.id == sessionId }?.let {
                        disconnectLiveCamera(it, "CAMERA_SESSION_CANCELLED", "Live shooting stopped when its listener closed.")
                    }
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, otgChannel)
            .setMethodCallHandler { call, result ->
                if (activityDestroyed) {
                    result.error("CAMERA_SESSION_ENDED", "The camera screen has closed.", null)
                    return@setMethodCallHandler
                }
                if (ptpTether.handleMethod(call, result)) return@setMethodCallHandler
                if (ptpTether.isBusy) {
                    when (call.method) {
                        "cameraConnectionDiagnostics" -> {
                            result.success(ptpTetherDiagnostics())
                            return@setMethodCallHandler
                        }
                        "connectedCameraDevices" -> {
                            val device = ptpTether.activeDevice
                            result.success(if (device == null) emptyList<Map<String, Any>>() else listOf(mapOf(
                                "id" to device.deviceId.toString(), "name" to (ptpTether.activeName ?: usbDeviceLabel(device)),
                                "hasPermission" to true, "directSupported" to true, "physicalShutter" to "unknown",
                            )))
                            return@setMethodCallHandler
                        }
                        "connectedCameraImages", "importConnectedCameraImages", "useUsbDeviceAsCamera", "startLiveCameraSession" -> {
                            result.error("CAMERA_LIVE_SESSION_ACTIVE", "Stop tethered shooting before opening a manual camera transfer session.", null)
                            return@setMethodCallHandler
                        }
                    }
                }
                // Manual imports must not open a second MTP session while live
                // capture owns the camera. Diagnostics only inspect its state.
                if (pendingLiveStart != null || liveCameraSession != null) {
                    val live = liveCameraSession
                    when (call.method) {
                        "cameraConnectionDiagnostics" -> {
                            if (live != null) result.success(liveCameraDiagnostics(live))
                            else result.error("CAMERA_LIVE_SESSION_STARTING", "Live shooting is still preparing the camera.", null)
                            return@setMethodCallHandler
                        }
                        "connectedCameraDevices" -> {
                            if (live != null) result.success(listOf(mapOf(
                                "id" to live.device.deviceId.toString(),
                                "name" to live.name,
                                "hasPermission" to true,
                                "directSupported" to true,
                                "physicalShutter" to "unknown",
                            )))
                            else result.error("CAMERA_LIVE_SESSION_STARTING", "Live shooting is still preparing the camera.", null)
                            return@setMethodCallHandler
                        }
                        "connectedCameraImages", "importConnectedCameraImages", "useUsbDeviceAsCamera" -> {
                            result.error("CAMERA_LIVE_SESSION_ACTIVE", "Stop live shooting before browsing or importing existing camera photos.", null)
                            return@setMethodCallHandler
                        }
                    }
                }
                when (call.method) {
                    "openPtpTetherSession" -> openPtpTetherSession(
                        call.argument<String>("sessionId"), call.argument<String>("cameraId"), result,
                    )
                    "setTransferScreenAwake" -> {
                        val owner = call.argument<String>("owner")
                        if (owner.isNullOrBlank()) {
                            result.error("INVALID_OWNER", "A transfer owner is required.", null)
                        } else {
                            setScreenAwake(owner, call.argument<Boolean>("enabled") == true)
                            result.success(null)
                        }
                    }
                    "startLiveCameraSession" -> startLiveCameraSession(call.argument<String>("sessionId"), result)
                    "stopLiveCameraSession" -> stopLiveCameraSession(call.argument<String>("sessionId"), result)
                    "pendingLiveCameraImages" -> pendingLiveCameraImages(call.argument<String>("sessionId"), result)
                    "downloadLiveCameraImage" -> downloadLiveCameraImage(
                        call.argument<String>("sessionId"), call.argument<String>("id"), result,
                    )
                    "acknowledgeLiveCameraImages" -> acknowledgeLiveCameraImages(
                        call.argument<String>("sessionId"), call.argument<List<String>>("ids") ?: emptyList(), result,
                    )
                    "pickImage" -> pickOtgImage(result)
                    "pickImages" -> pickOtgImages(result)
                    "connectedCameraDevices" -> listConnectedCameraDevices(result)
                    "useUsbDeviceAsCamera" -> {
                        val id = call.argument<String>("deviceId")?.toIntOrNull()
                        selectUsbDeviceAsCamera(id, result)
                    }
                    "cameraConnectionDiagnostics" -> cameraConnectionDiagnostics(result)
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

    @Suppress("DEPRECATION")
    private fun usbDeviceFromIntent(intent: Intent): UsbDevice? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }
    }

    private fun liveCameraMessage(): String =
        "Live monitoring is ready. Take a test photo with the camera shutter. " +
            "If USB transfer mode locks shooting, disconnect and select a shooting-capable " +
            "tether mode supported by that camera model. Reading saved photos alone does not confirm live shooting."

    private fun emitLiveEvent(
        sessionId: String,
        type: String,
        status: String? = null,
        message: String? = null,
        code: String? = null,
    ) {
        val payload = mutableMapOf<String, Any>("type" to type, "sessionId" to sessionId)
        if (status != null) payload["status"] = status
        if (message != null) payload["message"] = message
        if (code != null) payload["code"] = code
        runOnUiThread {
            if (!activityDestroyed && (liveEventSinkSessionId == null || liveEventSinkSessionId == sessionId)) {
                liveEventSink?.success(payload)
            }
        }
    }

    private fun liveCameraDiagnostics(session: LiveCameraSession): Map<String, Any?> {
        return mapOf(
            "status" to "live-ready",
            "message" to liveCameraMessage(),
            "discoveryOnly" to false,
            "totalImages" to session.pendingCount,
            "liveSessionActive" to true,
            "cameras" to listOf(mapOf(
                "id" to session.cameraId,
                "name" to session.name,
                "sessionOpen" to !session.stopped.get(),
                "catalogReady" to true,
                "catalogProgress" to 100,
                "imageCount" to session.pendingCount,
                "baselineObjectCount" to session.baselineCount,
                "sessionError" to "",
                "transportType" to "USB/PTP",
                "usbVendorId" to session.device.vendorId,
                "usbProductId" to session.device.productId,
                "wiredConfirmed" to true,
                // InitiateCapture is a remote command, not proof that the
                // physical shutter is usable. Android exposes no such flag.
                "physicalShutter" to "unknown",
                "supportsObjectEvents" to session.supportsObjectEvents,
                "supportsHostTransferEvents" to session.supportsHostTransferEvents,
                "supportsRemoteCapture" to session.supportsRemoteCapture,
                "supportsCapture" to (session.supportsRemoteCapture == true),
                "liveSessionActive" to true,
                "eventReaderActive" to session.eventReaderRunning,
            )),
        ) + usbConnectionOverview()
    }

    private fun storageOnlyDevice(device: UsbDevice): Boolean {
        if (hasStillImageInterface(device)) return false
        return device.deviceClass == UsbConstants.USB_CLASS_MASS_STORAGE ||
            (0 until device.interfaceCount).any {
                device.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_MASS_STORAGE
            }
    }

    private fun ptpTetherDiagnostics(): Map<String, Any?> {
        val device = ptpTether.activeDevice
        return mapOf(
            "status" to "tether-session", "discoveryOnly" to false, "liveSessionActive" to true,
            "message" to "The app owns a PTP tether session. Camera-specific shooting negotiation and new-shot monitoring use this same connection.",
            "totalImages" to 0,
            "cameras" to if (device == null) emptyList<Map<String, Any>>() else listOf(mapOf(
                "id" to device.deviceId.toString(), "name" to (ptpTether.activeName ?: usbDeviceLabel(device)),
                "sessionOpen" to true, "catalogReady" to false, "catalogProgress" to 0, "imageCount" to 0,
                "transportType" to "USB/PTP tether", "usbVendorId" to device.vendorId, "usbProductId" to device.productId,
                "wiredConfirmed" to true, "physicalShutter" to "unknown", "liveSessionActive" to true,
            )),
        ) + usbConnectionOverview()
    }

    private fun openPtpTetherSession(requestedId: String?, requestedCamera: String?, result: MethodChannel.Result) {
        if (pendingLiveStart != null || liveCameraSession != null || ptpTether.isBusy || manualCameraOperations.get() > 0) {
            result.error("CAMERA_LIVE_SESSION_ACTIVE", "Wait for the current camera operation to finish, then reconnect for tethered shooting.", null)
            return
        }
        if (pendingCameraListResult != null) {
            result.error("USB_PERMISSION_IN_PROGRESS", "Finish the existing USB permission request before starting tethered shooting.", null)
            return
        }
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)) {
            result.error("USB_HOST_UNSUPPORTED", "This phone does not support USB host camera connections.", null)
            return
        }
        val cameras = cameraUsbDevices()
        val specified = requestedCamera?.takeIf { it.isNotBlank() }
        val stableId = specified?.takeIf { it.matches(Regex("usb-[0-9a-f]{24}")) }
        val selected = if (specified != null) {
            cameras.firstOrNull {
                it.deviceId.toString() == specified || it.deviceName == specified || PtpTetherController.cameraIdentifier(it) == specified
            } ?: cameras.singleOrNull()?.takeIf { stableId != null }
        } else {
            cameras.firstOrNull { it.deviceId == manuallySelectedUsbDeviceId }
        }
        if (specified != null && selected == null) {
            result.error("USB_CAMERA_DISCONNECTED", "The selected camera is no longer attached. Select it again.", null)
            return
        }
        if (selected == null && cameras.size > 1) {
            result.error("CAMERA_SELECTION_REQUIRED", "Connect one camera or select the intended USB device in connection diagnostics.", null)
            return
        }
        val device = selected ?: cameras.firstOrNull()
        if (device == null || storageOnlyDevice(device)) {
            val manager = getSystemService(Context.USB_SERVICE) as UsbManager
            val storage = device != null || manager.deviceList.values.any(::storageOnlyDevice)
            result.error(if (storage) "CAMERA_TRANSFER_MODE" else "NO_CAMERA_CONNECTED",
                if (storage) "The device exposes storage/file transfer only. Select the camera's supported tethered-shooting USB mode and reconnect; a card reader cannot keep a camera shooting."
                else "No USB camera is attached. Connect a powered camera using a data cable and its shooting-capable USB mode.", null)
            return
        }
        ptpTether.open(requestedId, device, result, expectedCameraId = stableId)
    }

    private fun startLiveCameraSession(requestedId: String?, result: MethodChannel.Result) {
        if (pendingLiveStart != null || liveCameraSession != null || ptpTether.isBusy || manualCameraOperations.get() > 0) {
            result.error("CAMERA_LIVE_SESSION_ACTIVE", "A live camera connection is already starting or active. Stop it before reconnecting.", null)
            return
        }
        if (pendingCameraListResult != null) {
            result.error("USB_PERMISSION_IN_PROGRESS", "Finish the existing USB permission request before starting live shooting.", null)
            return
        }
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)) {
            result.error("USB_HOST_UNSUPPORTED", "This phone does not support USB host/OTG camera connections.", null)
            return
        }
        val candidates = cameraUsbDevices()
        val selected = candidates.firstOrNull { it.deviceId == manuallySelectedUsbDeviceId }
        if (selected == null && candidates.size > 1) {
            result.error("CAMERA_SELECTION_REQUIRED", "More than one USB camera is connected. Connect one camera, or select the intended device in USB diagnostics.", null)
            return
        }
        val device = selected ?: candidates.firstOrNull()
        if (device == null || storageOnlyDevice(device)) {
            if (manager.deviceList.values.any(::storageOnlyDevice)) {
                result.error("CAMERA_TRANSFER_MODE", "The USB device is in storage/file-transfer mode. This mode does not provide live camera shooting. Disconnect it and choose a compatible tether/remote-shooting USB mode on the camera; an SD reader cannot provide live shooting.", null)
            } else {
                result.error("NO_CAMERA_CONNECTED", "No compatible USB camera was found. Connect one camera with a data cable and select its supported tethered-shooting mode.", null)
            }
            return
        }
        val request = PendingLiveStart(requestedId?.takeIf { it.isNotBlank() } ?: UUID.randomUUID().toString(), device, result)
        pendingLiveStart = request
        emitLiveEvent(request.id, "status", "starting", "Preparing the USB camera. Wait for live shooting to be ready before taking photos.")
        if (manager.hasPermission(device)) {
            openLiveCameraSession(request)
            return
        }
        try {
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            val permissionIntent = Intent(liveUsbPermissionAction)
                .setPackage(packageName)
                .setData(Uri.parse("airpix://usb-live-permission/${Uri.encode(request.id)}"))
                .putExtra("liveSessionId", request.id)
            manager.requestPermission(device, PendingIntent.getBroadcast(this, request.id.hashCode(), permissionIntent, flags))
        } catch (error: Exception) {
            cancelPendingLiveStart(request, "USB_PERMISSION_REQUIRED", error.message ?: "Android could not request camera access.")
        }
    }

    private fun cancelPendingLiveStart(request: PendingLiveStart, code: String, message: String) {
        if (pendingLiveStart !== request) return
        pendingLiveStart = null
        request.cancelled.set(true)
        if (request.completed.compareAndSet(false, true)) request.result.error(code, message, null)
    }

    private fun cameraStillAttached(device: UsbDevice): Boolean {
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        return manager.deviceList.values.any {
            it.deviceId == device.deviceId && it.deviceName == device.deviceName
        } && manager.hasPermission(device)
    }

    private fun readCameraHandles(mtp: MtpDevice): Pair<Set<Int>, Set<Int>> {
        val storageIds = mtp.storageIds ?: throw LiveCameraException(
            "CAMERA_CATALOG_LOADING", "The camera has not supplied its storage list. Keep it awake and try live shooting again.",
        )
        val handles = linkedSetOf<Int>()
        for (storageId in storageIds) {
            val storageHandles = mtp.getObjectHandles(storageId, 0, 0) ?: throw LiveCameraException(
                "CAMERA_CATALOG_LOADING", "The camera has not finished listing its stored files. No existing photos have been armed for upload; keep it awake and retry.",
            )
            handles.addAll(storageHandles.toList())
        }
        return storageIds.toSet() to handles
    }

    private fun openLiveCameraSession(request: PendingLiveStart) {
        if (pendingLiveStart !== request || request.cancelled.get() || !request.opening.compareAndSet(false, true)) return
        cameraIo.execute {
            var mtp: MtpDevice? = null
            try {
                if (request.cancelled.get() || activityDestroyed) throw LiveCameraException("CAMERA_SESSION_CANCELLED", "Live shooting was cancelled.")
                if (!cameraStillAttached(request.device)) throw LiveCameraException("USB_CAMERA_DISCONNECTED", "The camera disconnected before its USB session opened.")
                val opened = openMtpDevice(request.device) ?: throw LiveCameraException(
                    "CAMERA_SESSION_FAILED", "The camera refused a USB/PTP session. Check its tethered-shooting mode and close other camera/USB apps. Some models require a manufacturer-specific protocol.",
                )
                mtp = opened
                val info = opened.deviceInfo ?: throw LiveCameraException("CAMERA_SESSION_FAILED", "The camera did not provide PTP device information in this USB mode.")
                val operations = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) info.operationsSupported?.toSet() else null
                val events = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) info.eventsSupported?.toSet() else null
                // Complete handle enumeration is the baseline. A null response
                // is a failed scan, not an empty card; never arm on partial data.
                val (storageIds, handles) = readCameraHandles(opened)
                if (request.cancelled.get() || activityDestroyed) throw LiveCameraException("CAMERA_SESSION_CANCELLED", "Live shooting was cancelled.")
                val identity = "${request.device.vendorId}:${request.device.productId}:" +
                    (info.serialNumber?.takeIf { it.isNotBlank() } ?: request.device.deviceName)
                val cameraId = "usb-" + MessageDigest.getInstance("SHA-256")
                    .digest(identity.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }.take(24)
                val name = listOfNotNull(info.manufacturer, info.model).joinToString(" ").trim().ifBlank { usbDeviceLabel(request.device) }
                val session = LiveCameraSession(
                    request.id, request.device, opened, cameraId, name, storageIds, handles,
                    events?.contains(0x4002), // ObjectAdded
                    events?.contains(0x4009), // RequestObjectTransfer
                    operations?.contains(0x100E), // InitiateCapture (remote, not the physical shutter)
                )
                runOnUiThread {
                    if (pendingLiveStart !== request || request.cancelled.get() || activityDestroyed) {
                        session.stopped.set(true)
                        releaseLiveCamera(session)
                        if (request.completed.compareAndSet(false, true)) request.result.error("CAMERA_SESSION_CANCELLED", "Live shooting was cancelled.", null)
                        return@runOnUiThread
                    }
                    pendingLiveStart = null
                    liveCameraSession = session
                    setScreenAwake("usb:${session.id}", true)
                    startLiveEventReader(session)
                    if (request.completed.compareAndSet(false, true)) {
                        request.result.success(mapOf(
                            "sessionId" to session.id,
                            "cameraId" to session.cameraId,
                            "name" to session.name,
                            "status" to "waiting-for-shot",
                            "physicalShutter" to "unknown",
                            "message" to liveCameraMessage(),
                            "baselineCount" to session.baselineCount,
                        ))
                    }
                    emitLiveEvent(session.id, "status", "waiting-for-shot", liveCameraMessage())
                }
            } catch (error: Exception) {
                try { mtp?.close() } catch (_: Exception) { }
                runOnUiThread {
                    if (pendingLiveStart === request) pendingLiveStart = null
                    if (request.completed.compareAndSet(false, true)) {
                        request.result.error(
                            (error as? LiveCameraException)?.code ?: "CAMERA_SESSION_FAILED",
                            error.message ?: "Unable to start live camera monitoring.", null,
                        )
                    }
                }
            }
        }
    }

    private fun stopLiveCameraSession(sessionId: String?, result: MethodChannel.Result) {
        val request = pendingLiveStart
        if (request != null && request.id == sessionId) {
            cancelPendingLiveStart(request, "CAMERA_SESSION_CANCELLED", "Live shooting was cancelled.")
            // Any in-progress open/baseline task observes the cancelled token
            // and closes its own MTP connection before the next queued start.
            cameraIo.execute { runOnUiThread { result.success(true) } }
            return
        }
        val session = liveCameraSession
        if (session == null || session.id != sessionId) {
            result.success(false)
            return
        }
        liveCameraSession = null
        session.stopped.set(true)
        session.eventCancellation.cancel()
        setScreenAwake("usb:${session.id}", false)
        releaseLiveCamera(session) { result.success(true) }
    }

    // Shared USB/wireless ownership keeps late cleanup from letting an active
    // receiving session sleep, even across Flutter page instances.
    private fun setScreenAwake(owner: String, enabled: Boolean) {
        if (enabled) {
            if (screenAwakeOwners.isEmpty()) {
                previousScreenOnFlag = (window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0
            }
            screenAwakeOwners.add(owner)
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else if (screenAwakeOwners.remove(owner) && screenAwakeOwners.isEmpty()) {
            if (!previousScreenOnFlag) window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            previousScreenOnFlag = false
        }
    }

    private fun releaseLiveCamera(session: LiveCameraSession, completion: (() -> Unit)? = null) {
        val release = Runnable {
            if (session.closed.compareAndSet(false, true)) {
                session.eventCancellation.cancel()
                // Only an explicit delivery acknowledgement deletes a fully
                // downloaded staging file, including after USB disconnect.
                session.pending.clear()
                session.pendingByHandle.clear()
                session.pendingCount = 0
                try { session.mtp.close() } catch (error: Exception) {
                    Log.w("AirPixCamera", "Could not close the live camera session", error)
                }
            }
            if (completion != null) runOnUiThread { completion() }
        }
        try {
            cameraIo.execute(release)
        } catch (_: RejectedExecutionException) {
            // onDestroy may have shut down the executor while USB open was
            // finishing. Release the late connection off the UI thread.
            Thread(release, "AirPixUsbClose").start()
        }
    }

    private fun disconnectLiveCamera(session: LiveCameraSession, code: String, message: String) {
        runOnUiThread {
            if (liveCameraSession !== session) return@runOnUiThread
            liveCameraSession = null
            session.stopped.set(true)
            session.eventCancellation.cancel()
            setScreenAwake("usb:${session.id}", false)
            emitLiveEvent(session.id, "disconnected", "disconnected", message, code)
            releaseLiveCamera(session)
        }
    }

    private fun isCurrentLiveSession(session: LiveCameraSession): Boolean =
        !activityDestroyed && !session.stopped.get() && liveCameraSession === session

    private fun startLiveEventReader(session: LiveCameraSession) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        Thread({
            session.eventReaderRunning = true
            try {
                while (isCurrentLiveSession(session)) {
                    // readEvent blocks until an interrupt event arrives. It
                    // must not hold the executor needed to download that shot.
                    val event = session.mtp.readEvent(session.eventCancellation)
                    if (!isCurrentLiveSession(session)) break
                    cameraIo.execute {
                        if (!isCurrentLiveSession(session)) return@execute
                        try {
                            handleLiveCameraEvent(session, event)
                        } catch (error: Exception) {
                            if (error is LiveCameraException && error.code == "CAMERA_STORAGE_CHANGED") {
                                disconnectLiveCamera(session, error.code, error.message ?: "Camera storage changed. Start live shooting again.")
                            } else if (!cameraStillAttached(session.device)) {
                                disconnectLiveCamera(session, "USB_CAMERA_DISCONNECTED", "USB camera disconnected. Reconnect it and start live shooting again.")
                            } else {
                                // Events can arrive while the camera is still
                                // writing metadata. Polling retries the handle.
                                Log.w("AirPixCamera", "Live camera event will be retried", error)
                            }
                        }
                    }
                }
            } catch (_: OperationCanceledException) {
                // Normal stop/disconnect cancellation.
            } catch (error: Exception) {
                if (isCurrentLiveSession(session)) {
                    if (!cameraStillAttached(session.device)) {
                        disconnectLiveCamera(session, "USB_CAMERA_DISCONNECTED", "USB camera disconnected. Reconnect it and start live shooting again.")
                    } else {
                        Log.w("AirPixCamera", "Camera interrupt events unavailable; keeping the USB session and polling", error)
                        emitLiveEvent(session.id, "status", "polling", "Camera event notifications are unavailable. The app is still checking for new shots through the same USB session.")
                    }
                }
            } finally {
                session.eventReaderRunning = false
            }
        }, "AirPixUsbEvents").apply { isDaemon = true }.start()
    }

    private fun handleLiveCameraEvent(session: LiveCameraSession, event: MtpEvent) {
        when (event.eventCode) {
            MtpEvent.EVENT_OBJECT_ADDED,
            MtpEvent.EVENT_REQUEST_OBJECT_TRANSFER,
            MtpEvent.EVENT_OBJECT_INFO_CHANGED -> {
                val handle = event.objectHandle
                if (handle !in session.baselineHandles) {
                    session.observedHandles.add(handle)
                    session.unresolvedHandles.add(handle)
                    queueLiveCameraObject(session, handle)
                }
            }
            MtpEvent.EVENT_OBJECT_REMOVED -> {
                val handle = event.objectHandle
                session.baselineHandles.remove(handle)
                session.observedHandles.remove(handle)
                session.unresolvedHandles.remove(handle)
                val id = session.pendingByHandle.remove(handle)
                val image = id?.let { session.pending[it] }
                if (image != null && image.downloaded == null) {
                    image.removed = true
                    emitLiveEvent(session.id, "status", "photo-unavailable", "${image.info.name ?: "A new photo"} was removed from the camera before transfer. Other photos can still be received.", "CAMERA_FILE_REMOVED")
                }
            }
            MtpEvent.EVENT_CAPTURE_COMPLETE,
            MtpEvent.EVENT_UNREPORTED_STATUS -> reconcileLiveCameraImages(session, force = true)
            MtpEvent.EVENT_DEVICE_RESET -> {
                // A new/replaced card may contain thousands of old photos.
                // Require a new baseline instead of uploading those as shots.
                throw LiveCameraException("CAMERA_STORAGE_CHANGED", "The camera reset or its memory card changed. Start live shooting again to skip the existing files on that card.")
            }
            MtpEvent.EVENT_STORE_ADDED -> {
                // Some cameras queued StoreAdded while the initial catalog
                // opened. The same already-baselined store is not a new card.
                if (event.storageId !in session.storageIds) throw LiveCameraException(
                    "CAMERA_STORAGE_CHANGED", "Camera storage was added. Start live shooting again to skip the existing files on that card.",
                )
                reconcileLiveCameraImages(session, force = true)
            }
            MtpEvent.EVENT_STORE_REMOVED -> {
                if (event.storageId in session.storageIds) throw LiveCameraException(
                    "CAMERA_STORAGE_CHANGED", "Camera storage was removed. Start live shooting again after the card is ready.",
                )
            }
            MtpEvent.EVENT_STORE_FULL -> emitLiveEvent(
                session.id, "status", "camera-storage-full", "The camera reports that its storage is full. Free space or change its recording destination before taking more photos.",
            )
        }
    }

    private fun mtpImageSize(info: MtpObjectInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) info.compressedSizeLong
        else info.compressedSize.toLong() and 0xFFFFFFFFL

    private fun liveImageId(session: LiveCameraSession, handle: Int, info: MtpObjectInfo): String =
        "${session.cameraId}|${info.storageId}|${handle.toLong() and 0xFFFFFFFFL}|${info.dateCreated}|${info.name}"

    // All calls to this function and all pending queue mutations run on cameraIo.
    private fun queueLiveCameraObject(session: LiveCameraSession, handle: Int) {
        if (handle in session.baselineHandles) {
            session.unresolvedHandles.remove(handle)
            return
        }
        val info = session.mtp.getObjectInfo(handle) ?: return
        val name = info.name ?: return
        if (!isCameraImageName(name)) {
            session.unresolvedHandles.remove(handle)
            return
        }
        if (mtpImageSize(info) <= 0) return // Camera is still writing this shot.
        val pendingId = session.pendingByHandle[handle]
        val pending = pendingId?.let { session.pending[it] }
        if (pending != null && !pending.removed) {
            // Some cameras revise file metadata after ObjectAdded. Preserve
            // the same delivery ID until Dart has durably saved and acked it.
            if (pending.downloaded == null) pending.info = info
            session.unresolvedHandles.remove(handle)
            return
        }
        val id = liveImageId(session, handle, info)
        session.unresolvedHandles.remove(handle)
        if (id in session.acknowledgedIds || id in session.pending) return
        session.pending[id] = LiveCameraImage(id, handle, info)
        session.pendingByHandle[handle] = id
        session.pendingCount = session.pending.size
        emitLiveEvent(session.id, "photosAvailable")
    }

    private fun reconcileLiveCameraImages(session: LiveCameraSession, force: Boolean = false) {
        val now = SystemClock.elapsedRealtime()
        if (force || now - session.lastReconcileMs >= 2500L) {
            val (storageIds, handles) = readCameraHandles(session.mtp)
            if (storageIds != session.storageIds) throw LiveCameraException(
                "CAMERA_STORAGE_CHANGED", "Camera storage changed. Start live shooting again to establish a new baseline before taking photos.",
            )
            for (handle in handles) {
                if (session.observedHandles.add(handle)) session.unresolvedHandles.add(handle)
            }
            // Do not remove baselined handles on an empty or temporarily stale
            // listing. Only an explicit ObjectRemoved or a new session does so.
            session.lastReconcileMs = now
        }
        for (handle in session.unresolvedHandles.toList()) {
            if (!isCurrentLiveSession(session)) break
            queueLiveCameraObject(session, handle)
        }
    }

    private fun withLiveCameraSession(
        sessionId: String?,
        result: MethodChannel.Result,
        deliverCompletedFile: Boolean = false,
        action: (LiveCameraSession) -> Any?,
    ) {
        val session = liveCameraSession
        if (session == null || session.id != sessionId || !isCurrentLiveSession(session)) {
            result.error("CAMERA_SESSION_ENDED", "This live camera session has ended. Start live shooting again.", null)
            return
        }
        cameraIo.execute {
            try {
                if (!isCurrentLiveSession(session)) throw LiveCameraException("CAMERA_SESSION_ENDED", "This live camera session has ended.")
                if (!cameraStillAttached(session.device)) throw LiveCameraException("USB_CAMERA_DISCONNECTED", "USB camera disconnected. Reconnect it and start live shooting again.")
                val payload = action(session)
                runOnUiThread {
                    // A fully downloaded file is still valid if the cable was
                    // unplugged immediately afterwards. Let Dart save it under
                    // the original session/event before acknowledging it.
                    if (isCurrentLiveSession(session) || deliverCompletedFile) result.success(payload)
                    else result.error("CAMERA_SESSION_ENDED", "This live camera session has ended.", null)
                }
            } catch (error: Exception) {
                val code = (error as? LiveCameraException)?.code ?: "USB_CAMERA_READ_FAILED"
                val message = error.message ?: "The camera could not complete the transfer. Keep it awake and retry."
                if (code == "USB_CAMERA_DISCONNECTED" || code == "CAMERA_STORAGE_CHANGED") {
                    disconnectLiveCamera(session, code, message)
                }
                runOnUiThread { result.error(code, message, null) }
            }
        }
    }

    private fun pendingLiveCameraImages(sessionId: String?, result: MethodChannel.Result) {
        withLiveCameraSession(sessionId, result) { session ->
            try {
                reconcileLiveCameraImages(session)
            } catch (error: Exception) {
                if (!isCurrentLiveSession(session)) throw LiveCameraException(
                    "CAMERA_SESSION_ENDED", "This live camera session has ended.",
                )
                if (!cameraStillAttached(session.device)) throw LiveCameraException(
                    "USB_CAMERA_DISCONNECTED", "USB camera disconnected. Reconnect it and start live shooting again.",
                )
                if (error is LiveCameraException && error.code == "CAMERA_STORAGE_CHANGED") throw error
                if (session.pending.isEmpty()) throw error
                // A temporary busy/storage-list failure must not hide shots
                // already retained in the pending queue (including cached
                // downloads that Dart can still save without another USB read).
                Log.w("AirPixCamera", "Catalog refresh will retry; returning retained live photos", error)
            }
            session.pending.values.map { image ->
                mapOf(
                    "id" to image.id,
                    "name" to (image.info.name ?: "camera-image.jpg"),
                    "size" to mtpImageSize(image.info),
                )
            }
        }
    }

    private fun downloadLiveCameraImage(sessionId: String?, id: String?, result: MethodChannel.Result) {
        withLiveCameraSession(sessionId, result, deliverCompletedFile = true) { session ->
            val image = session.pending[id] ?: throw LiveCameraException("CAMERA_FILE_MISSING", "This photo is no longer pending in the live camera session.")
            val cached = image.downloaded
            val cachedFile = cached?.get("path")?.let(::File)
            if (cached != null && cachedFile?.isFile == true && cachedFile.length() > 0L) {
                cached
            } else {
                if (image.removed) throw LiveCameraException("CAMERA_FILE_REMOVED", "This photo was removed from the camera before it could be saved in the app.")
                val info = session.mtp.getObjectInfo(image.handle) ?: throw LiveCameraException(
                    "CAMERA_FILE_NOT_READY", "The camera has not finished making this photo available. The app will retry it without dropping the shot.",
                )
                if (mtpImageSize(info) <= 0L) throw LiveCameraException("CAMERA_FILE_NOT_READY", "The camera is still writing this photo. Keep the camera connected.")
                image.info = info
                val imported = importMtpObject(session.mtp, session.device.deviceId, image.handle, info)
                    ?: throw LiveCameraException("CAMERA_FILE_NOT_READY", "The camera did not send a complete photo. It remains pending and will be retried.")
                (imported + ("id" to image.id)).also {
                    image.downloaded = it
                    stagedLiveDownloads.getOrPut(session.id) { hashMapOf() }[image.id] = it.getValue("path")
                }
            }
        }
    }

    private fun acknowledgeLiveCameraImages(sessionId: String?, ids: List<String>, result: MethodChannel.Result) {
        if (sessionId.isNullOrBlank()) {
            result.error("CAMERA_SESSION_ENDED", "A live camera session ID is required.", null)
            return
        }
        // Acknowledgement is local bookkeeping, not a USB operation: accept
        // the exact old token even after the camera was unplugged or stopped.
        cameraIo.execute {
            val session = liveCameraSession?.takeIf { it.id == sessionId }
            val staged = stagedLiveDownloads[sessionId]
            for (id in ids) {
                val image = session?.pending?.remove(id)
                if (session != null && image != null) {
                    session.acknowledgedIds.add(id)
                    if (session.pendingByHandle[image.handle] == id) session.pendingByHandle.remove(image.handle)
                }
                (staged?.remove(id) ?: image?.downloaded?.get("path"))?.let { File(it).delete() }
            }
            if (staged?.isEmpty() == true) stagedLiveDownloads.remove(sessionId)
            if (session != null) session.pendingCount = session.pending.size
            runOnUiThread { result.success(true) }
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
        val interfaceClasses = (0 until device.interfaceCount)
            .map { device.getInterface(it).interfaceClass }
        // Camera brands also ship card readers and UVC accessories; neither
        // exposes stored photos through PTP/MTP merely by being that brand.
        if (device.deviceClass == UsbConstants.USB_CLASS_MASS_STORAGE ||
            device.deviceClass == UsbConstants.USB_CLASS_VIDEO ||
            UsbConstants.USB_CLASS_MASS_STORAGE in interfaceClasses ||
            UsbConstants.USB_CLASS_VIDEO in interfaceClasses) return false
        if (device.vendorId in cameraUsbVendorIds) return true
        val label = usbDeviceLabel(device).lowercase()
        return cameraUsbHints.any { hint -> label.contains(hint) }
    }

    private fun selectUsbDeviceAsCamera(deviceId: Int?, result: MethodChannel.Result) {
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        val device = manager.deviceList.values.firstOrNull { it.deviceId == deviceId }
        if (device == null) {
            result.error("USB_CAMERA_DISCONNECTED", "USB device was unplugged. Reconnect it and run diagnostics again.", null)
            return
        }
        if (device.deviceClass == UsbConstants.USB_CLASS_HUB) {
            result.error("USB_UNSUPPORTED_DEVICE", "A USB hub is not itself a camera. Connect the camera to the hub.", null)
            return
        }
        manuallySelectedUsbDeviceId = device.deviceId
        Log.i("AirPixCamera", "Manually selected USB camera candidate id=${device.deviceId}")
        result.success(true)
    }

    private fun cameraUsbDevices(): List<UsbDevice> {
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        // Only request USB permission for an imaging/PTP/MTP candidate. Probing
        // unrelated devices (keyboards, hubs, chargers, SD readers) is misleading
        // and could prevent the real camera from being queried.
        return manager.deviceList.values
            .filter { device ->
                device.deviceClass != UsbConstants.USB_CLASS_HUB &&
                    (looksLikeCameraUsbDevice(device) ||
                        device.deviceId == manuallySelectedUsbDeviceId)
            }
            .sortedWith(
                compareByDescending<UsbDevice> { looksLikeCameraUsbDevice(it) }
                    .thenByDescending { hasStillImageInterface(it) }
            )
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

    // USB host can enumerate attached devices, including accessories which are
    // not cameras. No peripheral appearing here does NOT prove the cable is bad.
    private fun usbConnectionOverview(): Map<String, Any> {
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        val peripherals = manager.deviceList.values.sortedBy { it.deviceId }
        val summaries = peripherals.map { device ->
            val classes = (0 until device.interfaceCount)
                .map { device.getInterface(it).interfaceClass }
            val category = when {
                device.deviceClass == UsbConstants.USB_CLASS_HUB ||
                    UsbConstants.USB_CLASS_HUB in classes -> "USB hub"
                hasStillImageInterface(device) -> "PTP / still-image interface"
                UsbConstants.USB_CLASS_MASS_STORAGE in classes ||
                    device.deviceClass == UsbConstants.USB_CLASS_MASS_STORAGE -> "USB mass storage / SD reader"
                UsbConstants.USB_CLASS_VIDEO in classes ||
                    device.deviceClass == UsbConstants.USB_CLASS_VIDEO -> "USB video / webcam (UVC)"
                looksLikeCameraUsbDevice(device) -> "Camera-maker device (PTP not confirmed)"
                else -> "Other USB accessory (not confirmed as camera)"
            }
            mapOf<String, Any>(
                "id" to device.deviceId.toString(),
                "name" to usbDeviceLabel(device),
                "category" to category,
                "vendorId" to device.vendorId,
                "productId" to device.productId,
                "usbClass" to device.deviceClass,
                "interfaceClasses" to classes,
                "hasPermission" to manager.hasPermission(device),
                "cameraCandidate" to looksLikeCameraUsbDevice(device),
            )
        }
        return mapOf(
            "usbEnumerationAvailable" to true,
            "usbHostSupported" to packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST),
            "usbDevices" to summaries,
            "connectionNote" to "Android can list connected USB devices, but cannot detect an empty OTG adapter or guarantee a cable is passing data until a USB peripheral enumerates.",
        )
    }

    // Discovery must not open a PTP/MTP import session: doing so can put a
    // shooting camera into transfer mode even though the user only checked the
    // cable. Live/manual transfer opens its own session after an explicit action.
    private fun cameraConnectionDiagnostics(result: MethodChannel.Result) {
        try {
            val overview = usbConnectionOverview()
            val manager = getSystemService(Context.USB_SERVICE) as UsbManager
            val candidates = cameraUsbDevices()
            val hostSupported = packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)
            val otherUsbDevices = manager.deviceList.isNotEmpty()
            val needsPermission = candidates.any { !manager.hasPermission(it) }
            val cameras = candidates.map { device ->
                mapOf<String, Any>(
                    "id" to device.deviceId.toString(),
                    "name" to usbDeviceLabel(device),
                    "hasPermission" to manager.hasPermission(device),
                    "sessionOpen" to false,
                    "catalogReady" to false,
                    "catalogProgress" to 0,
                    "imageCount" to 0,
                    "sessionError" to "",
                    "transportType" to if (hasStillImageInterface(device)) "USB/PTP" else "USB (protocol unverified)",
                    "usbVendorId" to device.vendorId,
                    "usbProductId" to device.productId,
                    "wiredConfirmed" to true,
                    "physicalShutter" to "unknown",
                    "liveSessionActive" to false,
                    "standardPtpClass" to hasStillImageInterface(device),
                )
            }
            val status = when {
                !hostSupported -> "host-unsupported"
                candidates.isEmpty() && otherUsbDevices -> "unsupported-device"
                candidates.isEmpty() -> "no-camera"
                needsPermission -> "permission-required"
                else -> "camera-detected"
            }
            val message = when (status) {
                "host-unsupported" ->
                    "This Android device does not declare USB host/OTG support. Direct camera transfer may not be available on this phone."
                "unsupported-device" ->
                    "USB device(s) are detected, but none advertises a supported camera interface. Check the device type below and the camera model's shooting-capable USB mode."
                "no-camera" ->
                    "Android reports no attached USB peripheral. Check OTG host mode, data cable, camera power and USB mode. An empty adapter cannot be detected by this test."
                "permission-required" ->
                    "Android detected a possible USB camera. Start Live shooting and approve USB access to test automatic transfer, or choose manual import for stored photos. This connection check has not opened a camera session."
                else ->
                    "USB camera detected. Start Live shooting in the camera model's supported shooting mode and take a test photo. This connection check has not opened a camera session or read the memory card."
            }
            result.success(
                mapOf(
                    "status" to status,
                    "message" to message,
                    "discoveryOnly" to true,
                    "cameras" to cameras,
                    "totalImages" to 0,
                ) + overview,
            )
        } catch (error: Exception) {
            Log.e("AirPixCamera", "USB diagnostics failed", error)
            result.error("USB_DIAGNOSTICS_FAILED", error.message ?: "Could not inspect camera", null)
        }
    }

    private fun listConnectedCameraDevices(result: MethodChannel.Result) {
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        val devices = cameraUsbDevices()
        val payload = devices.map { device ->
            val hasPermission = manager.hasPermission(device)
            val advertisedPtp = hasStillImageInterface(device)
            val name = usbDeviceLabel(device)
            Log.i(
                "AirPixCamera",
                "USB candidate name=$name id=${device.deviceId} permission=$hasPermission advertisedPtp=$advertisedPtp",
            )
            mapOf(
                "id" to device.deviceId.toString(),
                "name" to name,
                "hasPermission" to hasPermission,
                // This is the advertised USB interface, not a probe that claims
                // the camera or proof that its physical shutter remains usable.
                "directSupported" to advertisedPtp,
                "standardPtpClass" to advertisedPtp,
                "physicalShutter" to "unknown",
            )
        }
        result.success(payload)
    }

    private fun executeManualCameraOperation(result: MethodChannel.Result, operation: () -> Unit) {
        manualCameraOperations.incrementAndGet()
        try {
            cameraIo.execute {
                try { operation() } finally { manualCameraOperations.decrementAndGet() }
            }
        } catch (_: RejectedExecutionException) {
            manualCameraOperations.decrementAndGet()
            result.error("CAMERA_SESSION_CANCELLED", "The camera screen has closed.", null)
        }
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
        executeManualCameraOperation(result) work@{
            try {
                val scanned = devices.map { device -> enumerateMtpImages(device) }
                if (scanned.all { it == null }) {
                    runOnUiThread {
                        result.error(
                            "USB_CAMERA_SESSION_FAILED",
                            "A USB camera is detected but its PTP/MTP photo-transfer session could not be opened. Check camera USB mode, cable and power.",
                            null,
                        )
                    }
                    return@work
                }
                val sorted = scanned.filterNotNull().flatten().sortedWith(
                        compareByDescending<Map<String, String>> {
                            it["modifiedMs"]?.toLongOrNull() ?: 0L
                        }.thenByDescending {
                            it["id"]?.substringAfter('|')?.toLongOrNull() ?: 0L
                        }
                    )
                val images = if (limit != null && limit > 0) sorted.take(limit) else sorted
                Log.i("AirPixCamera", "USB/PTP images found=${images.size} total=${sorted.size} devices=${devices.size} limit=$limit")
                runOnUiThread { result.success(images) }
            } catch (error: Exception) {
                runOnUiThread { result.error("USB_CAMERA_READ_FAILED", error.message, null) }
            }
        }
    }

    private fun openMtpDevice(device: UsbDevice): MtpDevice? {
        check(!ptpTether.isBusy) { "The tether session owns this USB camera. Stop it before opening MTP." }
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        val connection = manager.openDevice(device) ?: return null
        val mtp = MtpDevice(device)
        try {
            if (mtp.open(connection)) return mtp
        } catch (error: Exception) {
            connection.close()
            throw error
        }
        connection.close()
        return null
    }

    private fun enumerateMtpImages(device: UsbDevice): List<Map<String, String>>? {
        val mtp = openMtpDevice(device) ?: return null
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
        if (requestedDeviceIds.isEmpty()) {
            result.error("USB_CAMERA_SELECTION_INVALID", "Select photos from the connected camera again.", null)
            return
        }
        if (requestedDeviceIds.any { it !in devices }) {
            result.error("USB_CAMERA_DISCONNECTED", "The camera was disconnected. Reconnect it and refresh the photo list.", null)
            return
        }
        val missingPermission = requestedDeviceIds
            .mapNotNull { devices[it] }
            .firstOrNull { !manager.hasPermission(it) }
        if (missingPermission != null) {
            result.error("USB_PERMISSION_REQUIRED", "Reconnect or tap OTG again to allow camera access", null)
            return
        }

        executeManualCameraOperation(result) work@{
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
                    val device = devices[deviceId]
                        ?: throw IllegalStateException("Camera disconnected during transfer")
                    val mtp = openMtpDevice(device)
                        ?: throw IllegalStateException("Camera refused to open its USB photo-transfer session")
                    try {
                        for (handle in handles) {
                            val info = mtp.getObjectInfo(handle) ?: continue
                            importMtpObject(mtp, deviceId, handle, info)?.let(imported::add)
                        }
                    } finally {
                        mtp.close()
                    }
                }
                if (imported.isEmpty()) {
                    runOnUiThread {
                        result.error(
                            "USB_CAMERA_IMPORT_FAILED",
                            "The camera did not send any selected photos. Keep it awake, check cable/USB mode and available phone storage, then retry.",
                            null,
                        )
                    }
                } else {
                    runOnUiThread { result.success(imported) }
                }
            } catch (error: Exception) {
                Log.e("AirPixCamera", "USB camera import failed", error)
                runOnUiThread {
                    result.error("USB_CAMERA_IMPORT_FAILED", error.message ?: "USB camera photo transfer failed", null)
                }
            }
        }
    }

    private fun importMtpObject(
        mtp: MtpDevice,
        deviceId: Int,
        handle: Int,
        info: MtpObjectInfo,
    ): Map<String, String>? {
        val name = (info.name ?: "camera-image.jpg").replace(Regex("[^A-Za-z0-9._-]"), "_")
        val target = File(cacheDir, "camera_${System.nanoTime()}_$name")
        val expectedSize = mtpImageSize(info)
        val copied = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val descriptor = ParcelFileDescriptor.open(
                    target,
                    ParcelFileDescriptor.MODE_CREATE or
                        ParcelFileDescriptor.MODE_TRUNCATE or
                        ParcelFileDescriptor.MODE_READ_WRITE,
                )
                descriptor.use { mtp.importFile(handle, it) }
            } else {
                // The native path-based import streams to disk on older
                // Android too; do not allocate an entire RAW file in memory.
                mtp.importFile(handle, target.absolutePath)
            }
        } catch (error: Exception) {
            target.delete()
            throw error
        }
        if (!copied || !target.isFile || target.length() <= 0L ||
            (expectedSize > 0L && target.length() != expectedSize)) {
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
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/AirPix")
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
        activityDestroyed = true
        ptpTether.destroy()
        pendingLiveStart?.let {
            cancelPendingLiveStart(it, "CAMERA_SESSION_CANCELLED", "The camera screen closed before live shooting started.")
        }
        liveCameraSession?.let { session ->
            liveCameraSession = null
            session.stopped.set(true)
            session.eventCancellation.cancel()
            releaseLiveCamera(session)
        }
        screenAwakeOwners.toList().forEach { setScreenAwake(it, false) }
        liveEventSink = null
        liveEventSinkSessionId = null
        pendingCameraListResult?.error("CAMERA_SESSION_CANCELLED", "The camera screen has closed.", null)
        pendingCameraListResult = null
        pendingCameraListLimit = null
        if (usbReceiverRegistered) {
            try {
                unregisterReceiver(usbPermissionReceiver)
            } catch (_: Exception) {
            }
            usbReceiverRegistered = false
        }
        // Orderly shutdown lets in-flight USB operations release their own
        // descriptors before the executor exits; never wait on the UI thread.
        cameraIo.shutdown()
        super.onDestroy()
    }
}
