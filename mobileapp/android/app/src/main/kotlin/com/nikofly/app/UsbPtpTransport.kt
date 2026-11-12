package com.nikofly.app

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.hardware.usb.UsbRequest
import android.os.Build
import java.io.OutputStream
import java.nio.ByteBuffer
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.locks.ReentrantLock

/** A single raw PTP owner. Never hand this connection to Android's MtpDevice. */
internal class UsbPtpTransport private constructor(
    private val connection: UsbDeviceConnection,
    private val usbInterface: UsbInterface,
    private val bulkIn: UsbEndpoint,
    private val bulkOut: UsbEndpoint,
    private val interruptIn: UsbEndpoint?,
) : PtpBulkIo {
    companion object {
        fun claim(manager: UsbManager, device: UsbDevice): UsbPtpTransport {
            val interfaces = (0 until device.interfaceCount).map { device.getInterface(it) }
                .filter { it.interfaceClass == UsbConstants.USB_CLASS_STILL_IMAGE ||
                    it.interfaceClass == UsbConstants.USB_CLASS_VENDOR_SPEC }
                .sortedBy { if (it.interfaceClass == UsbConstants.USB_CLASS_STILL_IMAGE) 0 else 1 }
            for (candidate in interfaces) {
                val endpoints = (0 until candidate.endpointCount).map { candidate.getEndpoint(it) }
                val input = endpoints.firstOrNull {
                    it.type == UsbConstants.USB_ENDPOINT_XFER_BULK && it.direction == UsbConstants.USB_DIR_IN
                } ?: continue
                val output = endpoints.firstOrNull {
                    it.type == UsbConstants.USB_ENDPOINT_XFER_BULK && it.direction == UsbConstants.USB_DIR_OUT
                } ?: continue
                val events = endpoints.firstOrNull {
                    it.type == UsbConstants.USB_ENDPOINT_XFER_INT && it.direction == UsbConstants.USB_DIR_IN
                }
                val descriptor = manager.openDevice(device) ?: throw PtpWireException(
                    "USB_PERMISSION_REQUIRED", "Android could not open the camera. Allow USB access and reconnect.", false,
                )
                try {
                    // Do not forcibly detach another application's/kernel driver's owner.
                    if (!descriptor.claimInterface(candidate, false)) {
                        descriptor.close()
                        continue
                    }
                    return UsbPtpTransport(descriptor, candidate, input, output, events)
                } catch (error: Exception) {
                    descriptor.close()
                    throw error
                }
            }
            throw PtpWireException(
                "PTP_INTERFACE_UNAVAILABLE",
                "The camera has no available PTP command interface in this USB mode. Close other camera apps and select the camera's shooting-capable USB mode.", false,
            )
        }
    }

    private val closed = AtomicBoolean(false)
    private val closeStarted = AtomicBoolean(false)
    private val transactionLock = ReentrantLock()
    private val protocol = PtpWireProtocol(this)
    @Volatile private var sessionOpened = false
    @Volatile private var eventRequest: UsbRequest? = null
    @Volatile var eventReaderRunning = false
        private set

    override val outputPacketSize: Int get() = bulkOut.maxPacketSize
    override fun isClosed(): Boolean = closed.get()
    override fun read(buffer: ByteArray, offset: Int, length: Int, timeoutMillis: Int): Int =
        connection.bulkTransfer(bulkIn, buffer, offset, length, timeoutMillis)
    override fun write(buffer: ByteArray, offset: Int, length: Int, timeoutMillis: Int): Int =
        connection.bulkTransfer(bulkOut, buffer, offset, length, timeoutMillis)

    private fun <T> transaction(block: () -> T): T {
        transactionLock.lock()
        try {
            if (closed.get() || closeStarted.get()) throw PtpWireException("PTP_SESSION_CLOSED", "The camera session has ended.")
            return block()
        } finally {
            transactionLock.unlock()
        }
    }

    fun openSession(): ByteArray = transaction {
        // Both operations occur outside a session and use transaction zero.
        val deviceInfo = protocol.initialTransaction(0x1001)
        if (deviceInfo.responseCode != PtpWireCodec.OK || deviceInfo.data.isEmpty()) {
            throw PtpWireException("PTP_DEVICE_INFO_FAILED", "The camera did not supply its PTP capabilities.", responseCode = deviceInfo.responseCode)
        }
        val opened = protocol.initialTransaction(0x1002, listOf(1L))
        if (opened.responseCode != PtpWireCodec.OK) {
            val message = if (opened.responseCode == 0x201e) {
                "The camera already has an open PTP session. Close other camera apps, disconnect the cable, then reconnect."
            } else {
                "The camera refused to open its PTP session (0x${opened.responseCode.toString(16)}). Check its USB shooting mode."
            }
            throw PtpWireException("PTP_SESSION_OPEN_FAILED", message, responseCode = opened.responseCode)
        }
        sessionOpened = true
        deviceInfo.data
    }

    fun command(opcode: Int, parameters: List<Long>, outData: ByteArray?): PtpReply = transaction {
        protocol.transact(opcode, parameters, outData)
    }

    fun receiveObject(opcode: Int, parameters: List<Long>, output: OutputStream, maxBytes: Long): PtpReply = transaction {
        protocol.receiveTo(opcode, parameters, output, maxBytes)
    }

    /** Event transfers have a separate endpoint and never hold the command lock. */
    fun startEvents(onEvent: (ByteArray) -> Unit, onUnavailable: (Exception) -> Unit) {
        val endpoint = interruptIn ?: return
        // requestWait(timeout) was added in API 26. Earlier phones keep the
        // vendor/standard polling path instead of owning an unbounded wait.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        Thread({
            val request = UsbRequest()
            val framer = PtpEventFramer()
            try {
                if (closed.get() || closeStarted.get()) return@Thread
                if (!request.initialize(connection, endpoint)) throw PtpWireException("PTP_EVENTS_UNAVAILABLE", "The USB event endpoint is unavailable.", false)
                eventRequest = request
                if (closed.get() || closeStarted.get()) return@Thread
                eventReaderRunning = true
                val buffer = ByteBuffer.allocateDirect(PtpWireProtocol.USB_CHUNK)
                while (!closed.get() && !closeStarted.get()) {
                    buffer.clear()
                    if (!request.queue(buffer)) throw PtpWireException("PTP_EVENTS_UNAVAILABLE", "The camera event request could not be queued.", false)
                    var completed: UsbRequest? = null
                    while (completed == null && !closed.get() && !closeStarted.get()) {
                        try {
                            completed = connection.requestWait(1_000L)
                            if (completed == null) throw PtpWireException("PTP_EVENTS_UNAVAILABLE", "The camera event endpoint stopped responding.", false)
                        } catch (_: TimeoutException) {
                            // Keep this request pending; a timeout is not an empty event.
                        }
                    }
                    if (closed.get() || closeStarted.get()) break
                    if (completed !== request) throw PtpWireException("PTP_EVENTS_UNAVAILABLE", "Another USB owner supplied an unexpected event request.", false)
                    val count = buffer.position()
                    if (count == 0) continue
                    buffer.flip()
                    val bytes = ByteArray(count)
                    buffer.get(bytes)
                    framer.accept(bytes).forEach(onEvent)
                }
            } catch (error: Exception) {
                if (!closed.get() && !closeStarted.get()) onUnavailable(error)
            } finally {
                eventReaderRunning = false
                if (eventRequest === request) eventRequest = null
                try { request.cancel() } catch (_: Exception) { }
                try { request.close() } catch (_: Exception) { }
            }
        }, "AirPixPtpEvents").apply { isDaemon = true }.start()
    }

    /** Called off the UI thread. If a transfer owns the lock, close aborts it immediately. */
    fun close(graceful: Boolean) {
        if (!closeStarted.compareAndSet(false, true)) return
        try { eventRequest?.cancel() } catch (_: Exception) { }
        if (graceful && transactionLock.tryLock()) {
            try {
                if (!closed.get() && sessionOpened) {
                    try { protocol.transact(0x1003, timeoutMillis = 1_000) } catch (_: Exception) { }
                }
            } finally {
                transactionLock.unlock()
            }
        }
        if (closed.compareAndSet(false, true)) {
            // Closing the descriptor also unblocks outstanding bulk/event reads.
            try { connection.releaseInterface(usbInterface) } catch (_: Exception) { }
            try { connection.close() } catch (_: Exception) { }
        }
        sessionOpened = false
    }
}
