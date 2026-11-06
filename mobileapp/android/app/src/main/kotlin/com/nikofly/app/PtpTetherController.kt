package com.nikofly.app

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Prevents all passive USB camera receivers from deleting, shooting, or UI-locking. */
internal object PtpShootingSafety {
    private val blocked = setOf(
        0x100b, 0x100c, 0x100d, 0x100e, 0x100f, 0x1010,
        0x1011, 0x1012, 0x1013, 0x1017, 0x1018, 0x1019, 0x101a, 0x101c,
        0x910f, 0x911b, 0x9128, 0x9129, 0x9151, 0x9207,
        0x1016, 0x9110, 0x9205, 0x9206, // Camera property writes
    )

    private val readOperations = setOf(
        0x1001, 0x1004, 0x1005, 0x1007, 0x1008, 0x1009, 0x100a,
        0x1014, 0x1015, 0x101b,
    )

    fun isAllowed(opcode: Int, vendorId: Int = 0,
        parameters: List<Long> = emptyList(), outgoing: ByteArray? = null): Boolean {
        val olympus = vendorId == 0x07b4 || vendorId == 0x33a2
        if (olympus && opcode == 0x1016) {
            return parameters == listOf(0xd052L) && outgoing != null &&
                (outgoing.contentEquals(byteArrayOf(1, 0)) ||
                 outgoing.contentEquals(byteArrayOf(2, 0)))
        }
        if (opcode in blocked || (outgoing != null && outgoing.isNotEmpty())) return false
        if (opcode in readOperations) return true
        // Default-deny vendor commands; USB identity and exact negotiation values
        // must match. Never allow host priority, capture or live-view as a fallback.
        return when (vendorId) {
            0x04a9 -> when (opcode) {
                0x9114, 0x9115 -> parameters == listOf(0L) || parameters == listOf(1L)
                0x9116 -> parameters.isEmpty()
                0x9127 -> parameters == listOf(0xd11cL)
                0x9117 -> parameters.size == 1 && parameters[0] in 1L until 0xffffffffL
                0x9107 -> true // Native download validates partial-read ranges.
                else -> false
            }
            0x04b0 -> (opcode == 0x90c2 && parameters == listOf(0L)) ||
                (opcode in setOf(0x90c7, 0x941c) && parameters.isEmpty())
            0x054c -> (opcode == 0x9201 &&
                parameters in listOf(listOf(1L, 0L, 0L), listOf(2L, 0L, 0L), listOf(3L, 0L, 0L))) ||
                (opcode == 0x9202 && parameters == listOf(0x12cL, 1L)) ||
                (opcode == 0x9209 && parameters.isEmpty())
            0x04da -> opcode == 0x940a && parameters == listOf(0x08000090L)
            else -> false
        }
    }

    fun requirePassive(opcode: Int, vendorId: Int = 0,
        parameters: List<Long> = emptyList(), outgoing: ByteArray? = null) {
        if (!isAllowed(opcode, vendorId, parameters, outgoing)) {
            throw PtpWireException(
                "PTP_SHOOTING_COMMAND_BLOCKED",
                "This command is not approved for this camera. Receiving stops without switching USB modes.",
                false,
            )
        }
    }
}

/** Owns permission, raw USB lifetime and native file staging for one Dart session. */
internal class PtpTetherController(
    private val activity: Activity,
    private val commands: ExecutorService,
    val permissionAction: String,
    private val destroyed: () -> Boolean,
    private val setAwake: (String, Boolean) -> Unit,
    private val emit: (Map<String, Any>) -> Unit,
) {
    companion object {
        fun cameraIdentifier(device: UsbDevice): String {
            val serial = try { device.serialNumber } catch (_: Exception) { null }
            val identity = "${device.vendorId}:${device.productId}:${serial ?: device.deviceName}"
            return "usb-" + MessageDigest.getInstance("SHA-256").digest(identity.toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it) }.take(24)
        }
    }

    private class Pending(val id: String, val device: UsbDevice, val result: MethodChannel.Result, val expectedCameraId: String?) {
        val cancelled = AtomicBoolean(false)
        val completed = AtomicBoolean(false)
        val opening = AtomicBoolean(false)
        @Volatile var transport: UsbPtpTransport? = null
        val stopResults = mutableListOf<MethodChannel.Result>()
    }
    private class Session(val id: String, val device: UsbDevice, val transport: UsbPtpTransport, val cameraId: String, val name: String) {
        val stopped = AtomicBoolean(false)
    }
    @Volatile private var pending: Pending? = null
    @Volatile private var session: Session? = null
    private val closing = AtomicInteger(0)
    private val queued = AtomicInteger(0)
    private val files = PtpObjectTransferStore(File(activity.cacheDir, "ptp-tether"))
    private val manager get() = activity.getSystemService(Context.USB_SERVICE) as UsbManager

    val isBusy: Boolean get() = pending != null || session != null || closing.get() > 0
    val activeDevice: UsbDevice? get() = session?.device ?: pending?.device
    val activeSessionId: String? get() = session?.id ?: pending?.id
    val activeName: String? get() = session?.name

    fun open(requestedId: String?, device: UsbDevice, result: MethodChannel.Result, expectedCameraId: String? = null) {
        if (isBusy) {
            result.error("CAMERA_LIVE_SESSION_ACTIVE", "The previous USB camera session is still active or closing.", null)
            return
        }
        val id = requestedId?.takeIf { it.isNotBlank() && it.length <= 1024 } ?: UUID.randomUUID().toString()
        val request = Pending(id, device, result, expectedCameraId)
        pending = request
        event(id, "status", "starting", "Opening the camera's tether connection.")
        if (manager.hasPermission(device)) {
            beginOpen(request)
        } else {
            try {
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                val intent = Intent(permissionAction).setPackage(activity.packageName)
                    .setData(Uri.parse("airpix://usb-tether-permission/${Uri.encode(id)}"))
                    .putExtra("ptpSessionId", id)
                manager.requestPermission(device, PendingIntent.getBroadcast(activity, id.hashCode(), intent, flags))
            } catch (error: Exception) {
                cancelPending(request, "USB_PERMISSION_REQUIRED", error.message ?: "Android could not request camera access.")
            }
        }
    }

    fun permissionResult(sessionId: String?, device: UsbDevice?, granted: Boolean) {
        val request = pending ?: return
        if (request.id != sessionId || request.cancelled.get() || device?.deviceId != request.device.deviceId) return
        if (granted) beginOpen(request)
        else cancelPending(request, "USB_PERMISSION_DENIED", "USB camera access was denied. Reconnect and allow access.")
    }

    private fun attached(device: UsbDevice): Boolean = manager.deviceList.values.any {
        it.deviceId == device.deviceId && it.deviceName == device.deviceName
    } && manager.hasPermission(device)

    private fun beginOpen(request: Pending) {
        if (pending !== request || request.cancelled.get() || !request.opening.compareAndSet(false, true)) return
        try {
            commands.execute {
                var transport: UsbPtpTransport? = null
                try {
                    if (request.cancelled.get() || destroyed()) throw PtpWireException("CAMERA_SESSION_CANCELLED", "Camera connection cancelled.", false)
                    if (!attached(request.device)) throw PtpWireException("USB_CAMERA_DISCONNECTED", "The camera disconnected before its tether session opened.", false)
                    // Serial numbers may become readable only after Android USB
                    // permission. Verify a requested stable ID before claiming it.
                    val cameraId = cameraIdentifier(request.device)
                    if (request.expectedCameraId != null && request.expectedCameraId != cameraId) {
                        throw PtpWireException("PTP_CAMERA_CHANGED", "The connected camera differs from the selected camera. Select this camera again.", false)
                    }
                    val openedTransport = UsbPtpTransport.claim(manager, request.device)
                    transport = openedTransport
                    request.transport = openedTransport
                    if (request.cancelled.get() || destroyed()) throw PtpWireException("CAMERA_SESSION_CANCELLED", "Camera connection cancelled.", false)
                    val deviceInfo = openedTransport.openSession()
                    val name = listOfNotNull(request.device.manufacturerName, request.device.productName).joinToString(" ").trim().ifBlank { "USB camera" }
                    val opened = Session(request.id, request.device, openedTransport, cameraId, name)
                    activity.runOnUiThread {
                        if (pending !== request || request.cancelled.get() || destroyed()) {
                            // Opening may have completed just before Stop/hot
                            // restart. Release an idle PTP session cleanly so
                            // the camera is not left owned until cable removal.
                            closeTransport(openedTransport, true) { finishPending(request) }
                            return@runOnUiThread
                        }
                        pending = null
                        session = opened
                        setAwake("usb:${opened.id}", true)
                        opened.transport.startEvents(
                            onEvent = { bytes ->
                                if (current(opened)) emit(mapOf("type" to "ptpEvent", "sessionId" to opened.id, "data" to bytes))
                            },
                            onUnavailable = { error ->
                                if (current(opened)) event(opened.id, "status", "polling", error.message ?: "Camera notifications are unavailable; polling continues.")
                            },
                        )
                        if (request.completed.compareAndSet(false, true)) request.result.success(mapOf(
                            "sessionId" to opened.id, "cameraId" to cameraId, "name" to name,
                            "vendorId" to request.device.vendorId, "productId" to request.device.productId,
                            "physicalShutter" to "unknown", "transport" to "usb-ptp", "deviceInfo" to deviceInfo,
                        ))
                    }
                } catch (error: Exception) {
                    transport?.close(false)
                    activity.runOnUiThread {
                        if (request.completed.compareAndSet(false, true)) fail(request.result, error)
                        finishPending(request)
                    }
                }
            }
        } catch (error: RejectedExecutionException) {
            if (request.completed.compareAndSet(false, true)) fail(request.result, error)
            finishPending(request)
        }
    }

    private fun finishPending(request: Pending) {
        if (pending === request) pending = null
        request.stopResults.forEach { it.success(true) }
        request.stopResults.clear()
    }

    private fun cancelPending(request: Pending, code: String, message: String, stopResult: MethodChannel.Result? = null, graceful: Boolean = true) {
        if (pending !== request) { stopResult?.success(false); return }
        request.cancelled.set(true)
        if (request.completed.compareAndSet(false, true)) request.result.error(code, message, null)
        if (stopResult != null) request.stopResults.add(stopResult)
        if (!request.opening.get()) finishPending(request)
        else request.transport?.let { closeTransport(it, graceful) }
    }

    private fun current(candidate: Session): Boolean = !destroyed() && !candidate.stopped.get() && session === candidate

    fun detached(device: UsbDevice) {
        pending?.takeIf { it.device.deviceId == device.deviceId }?.let {
            cancelPending(it, "USB_CAMERA_DISCONNECTED", "The camera disconnected while its tether session was opening.", graceful = false)
        }
        session?.takeIf { it.device.deviceId == device.deviceId }?.let {
            disconnect(it, "USB_CAMERA_DISCONNECTED", "The USB camera disconnected. Reconnect to resume new shots.")
        }
    }

    fun listenerClosed(sessionId: String?) {
        pending?.takeIf { it.id == sessionId }?.let {
            cancelPending(it, "CAMERA_SESSION_CANCELLED", "The camera receiver closed.")
        }
        session?.takeIf { it.id == sessionId }?.let {
            disconnect(it, "CAMERA_SESSION_CANCELLED", "The camera receiver closed.", graceful = true)
        }
    }

    fun destroy() {
        pending?.let { cancelPending(it, "CAMERA_SESSION_CANCELLED", "The camera screen closed.") }
        session?.let { disconnect(it, "CAMERA_SESSION_CANCELLED", "The camera screen closed.", graceful = true) }
    }

    private fun disconnect(candidate: Session, code: String, message: String, graceful: Boolean = false) {
        candidate.stopped.set(true)
        activity.runOnUiThread {
            if (session !== candidate) return@runOnUiThread
            session = null
            setAwake("usb:${candidate.id}", false)
            event(candidate.id, "disconnected", "disconnected", message, code)
            // Graceful close only acquires an idle command lock and has a
            // one-second deadline. An active/failed transfer is aborted by
            // descriptor close; no CloseSession enters its response stream.
            closeTransport(candidate.transport, graceful)
        }
    }

    private fun closeTransport(transport: UsbPtpTransport, graceful: Boolean, completion: (() -> Unit)? = null) {
        closing.incrementAndGet()
        Thread({
            try { transport.close(graceful) } finally {
                activity.runOnUiThread {
                    closing.decrementAndGet()
                    completion?.invoke()
                }
            }
        }, "AirPixPtpClose").apply { isDaemon = true }.start()
    }

    fun handleMethod(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "closePtpTetherSession" -> {
                val id = call.argument<String>("sessionId")
                val request = pending
                if (request != null && request.id == id) cancelPending(request, "CAMERA_SESSION_CANCELLED", "Camera connection cancelled.", result)
                else {
                    val active = session
                    if (active == null || active.id != id) result.success(false)
                    else {
                        active.stopped.set(true)
                        session = null
                        setAwake("usb:${active.id}", false)
                        closeTransport(active.transport, true) { result.success(true) }
                    }
                }
                return true
            }
            "sendPtpTetherCommand", "downloadPtpTetherObject", "acknowledgePtpTetherFiles" -> {
                try {
                    val id = call.argument<String>("sessionId")?.takeIf { it.isNotBlank() }
                        ?: throw PtpWireException("PTP_INVALID_ARGUMENT", "A camera session ID is required.", false)
                    val active = session?.takeIf { it.id == id }
                    if (call.method == "acknowledgePtpTetherFiles") {
                        val ids = call.argument<List<*>>("ids")?.map {
                            it as? String ?: throw PtpWireException("PTP_INVALID_ARGUMENT", "Transfer IDs must be strings.", false)
                        } ?: emptyList()
                        submit(result, null) { files.acknowledge(id, ids); true }
                    } else if (call.method == "sendPtpTetherCommand") {
                        val opcode = uint(call.argument<Any>("opcode"), "opcode").toInt()
                        if (opcode !in 1..0xffff || opcode == 0x1002 || opcode == 0x1003) {
                            throw PtpWireException("PTP_INVALID_ARGUMENT", "Open and close are owned by the native USB session.", false)
                        }
                        if (opcode == 0x1009 || opcode == 0x101b || opcode == 0x9107) {
                            throw PtpWireException("PTP_STREAM_REQUIRED", "Camera photos must use the native file transfer method.", false)
                        }
                        val parameters = call.argument<List<*>>("params")?.map { uint(it, "parameter") } ?: emptyList()
                        val outData = call.argument<ByteArray>("outData")
                        PtpShootingSafety.requirePassive(opcode, active?.device?.vendorId ?: 0, parameters, outData)
                        submit(result, active) {
                            val selected = active?.takeIf(::current) ?: throw PtpWireException("PTP_SESSION_CLOSED", "The camera session has ended.", false)
                            val reply = selected.transport.command(opcode, parameters, outData)
                            mapOf("responseCode" to reply.responseCode, "parameters" to reply.parameters, "data" to reply.data)
                        }
                    } else {
                        val transferId = call.argument<String>("transferId") ?: throw PtpWireException("PTP_INVALID_ARGUMENT", "A stable photo transfer ID is required.", false)
                        val handle = uint(call.argument<Any>("handle"), "handle")
                        val name = call.argument<String>("name") ?: "camera-image.jpg"
                        val size = uint(call.argument<Any>("expectedSize") ?: 0L, "expectedSize")
                        val partial = call.argument<Any>("partialOpcode")?.let { uint(it, "partialOpcode").toInt() }
                        submit(result, active) {
                            files.download(id, transferId, handle, name, size, partial,
                                consumptiveHandle = active?.device?.vendorId == 0x054c && handle == 0xffffc001L,
                                allowStart = active != null && current(active),
                            ) { opcode, parameters, output, maximum ->
                                val selected = active?.takeIf(::current) ?: throw PtpWireException("PTP_SESSION_CLOSED", "The camera session has ended.", false)
                                PtpShootingSafety.requirePassive(opcode, selected.device.vendorId, parameters)
                                selected.transport.receiveObject(opcode, parameters, output, maximum)
                            }
                        }
                    }
                } catch (error: Exception) { fail(result, error) }
                return true
            }
            else -> return false
        }
    }

    private fun uint(value: Any?, field: String): Long {
        if (value !is Int && value !is Long) throw PtpWireException("PTP_INVALID_ARGUMENT", "$field must be an unsigned integer.", false)
        val number = (value as Number).toLong()
        if (number !in 0..0xffffffffL) throw PtpWireException("PTP_INVALID_ARGUMENT", "$field must fit an unsigned 32-bit integer.", false)
        return number
    }

    private fun submit(result: MethodChannel.Result, active: Session?, operation: () -> Any) {
        if (queued.incrementAndGet() > 64) {
            queued.decrementAndGet()
            throw PtpWireException("PTP_QUEUE_BUSY", "Wait for the current camera command to finish.", false)
        }
        try {
            commands.execute {
                try {
                    val value = operation()
                    // A completed file may finish delivery after stop. Its
                    // original transferId remains valid until Dart acknowledges it.
                    activity.runOnUiThread { result.success(value) }
                } catch (error: Exception) {
                    if (active != null && current(active) && (error !is PtpWireException || error.fatal)) {
                        disconnect(active, (error as? PtpWireException)?.code ?: "PTP_TRANSPORT_FAILED", error.message ?: "The camera transfer failed. Reconnect the camera.")
                    }
                    activity.runOnUiThread { fail(result, error) }
                } finally { queued.decrementAndGet() }
            }
        } catch (error: RejectedExecutionException) {
            queued.decrementAndGet()
            throw PtpWireException("PTP_SESSION_CLOSED", "The camera screen has closed.", false)
        }
    }

    private fun fail(result: MethodChannel.Result, error: Exception) {
        val failure = error as? PtpWireException
        result.error(failure?.code ?: "PTP_TRANSPORT_FAILED", error.message ?: "The camera operation failed.",
            failure?.responseCode?.let { mapOf("responseCode" to it) })
    }

    private fun event(id: String, type: String, status: String, message: String, code: String? = null) {
        val payload = mutableMapOf<String, Any>("type" to type, "sessionId" to id, "status" to status, "message" to message)
        if (code != null) payload["code"] = code
        emit(payload)
    }
}
