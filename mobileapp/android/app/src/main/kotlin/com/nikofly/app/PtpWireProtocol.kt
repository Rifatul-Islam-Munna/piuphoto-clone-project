package com.nikofly.app

import java.io.ByteArrayOutputStream
import java.io.OutputStream

/** USB PTP framing, independent of Android so malformed/fragmented traffic is testable. */
internal interface PtpBulkIo {
    val outputPacketSize: Int
    fun read(buffer: ByteArray, offset: Int, length: Int, timeoutMillis: Int): Int
    fun write(buffer: ByteArray, offset: Int, length: Int, timeoutMillis: Int): Int
    fun isClosed(): Boolean
}

internal class PtpWireException(
    val code: String,
    message: String,
    val fatal: Boolean = true,
    val responseCode: Int? = null,
) : Exception(message)

internal data class PtpReply(
    val responseCode: Int,
    val parameters: List<Long>,
    val data: ByteArray,
    val receivedBytes: Long,
)

internal data class PtpHeader(
    val length: Long,
    val type: Int,
    val code: Int,
    val transactionId: Long,
)

internal object PtpWireCodec {
    const val HEADER_SIZE = 12
    const val COMMAND = 1
    const val DATA = 2
    const val RESPONSE = 3
    const val EVENT = 4
    const val OK = 0x2001
    const val MAX_PARAMETERS = 5

    fun uint16(bytes: ByteArray, offset: Int): Int =
        (bytes[offset].toInt() and 0xff) or ((bytes[offset + 1].toInt() and 0xff) shl 8)

    fun uint32(bytes: ByteArray, offset: Int): Long =
        (bytes[offset].toLong() and 0xffL) or
            ((bytes[offset + 1].toLong() and 0xffL) shl 8) or
            ((bytes[offset + 2].toLong() and 0xffL) shl 16) or
            ((bytes[offset + 3].toLong() and 0xffL) shl 24)

    private fun put16(bytes: ByteArray, offset: Int, value: Int) {
        bytes[offset] = value.toByte()
        bytes[offset + 1] = (value ushr 8).toByte()
    }

    private fun put32(bytes: ByteArray, offset: Int, value: Long) {
        require(value in 0..0xffffffffL) { "PTP values must fit an unsigned 32-bit integer." }
        for (index in 0..3) bytes[offset + index] = (value ushr (index * 8)).toByte()
    }

    fun header(length: Long, type: Int, code: Int, transactionId: Long): ByteArray {
        require(length in HEADER_SIZE.toLong()..0xffffffffL)
        require(code in 0..0xffff)
        return ByteArray(HEADER_SIZE).also {
            put32(it, 0, length)
            put16(it, 4, type)
            put16(it, 6, code)
            put32(it, 8, transactionId)
        }
    }

    fun command(opcode: Int, transactionId: Long, parameters: List<Long>): ByteArray {
        require(opcode in 1..0xffff)
        require(parameters.size <= MAX_PARAMETERS)
        val bytes = header((HEADER_SIZE + parameters.size * 4).toLong(), COMMAND, opcode, transactionId)
            .copyOf(HEADER_SIZE + parameters.size * 4)
        parameters.forEachIndexed { index, parameter -> put32(bytes, HEADER_SIZE + index * 4, parameter) }
        return bytes
    }

    fun parseHeader(bytes: ByteArray, offset: Int = 0): PtpHeader {
        if (offset < 0 || bytes.size - offset < HEADER_SIZE) {
            throw PtpWireException("PTP_INVALID_PACKET", "The camera sent an incomplete PTP header.")
        }
        val length = uint32(bytes, offset)
        if (length < HEADER_SIZE) {
            throw PtpWireException("PTP_INVALID_PACKET", "The camera sent an invalid PTP container length.")
        }
        return PtpHeader(length, uint16(bytes, offset + 4), uint16(bytes, offset + 6), uint32(bytes, offset + 8))
    }

    fun responseParameters(bytes: ByteArray): List<Long> {
        if (bytes.size % 4 != 0 || bytes.size > MAX_PARAMETERS * 4) {
            throw PtpWireException("PTP_INVALID_PACKET", "The camera sent an invalid PTP response parameter list.")
        }
        return (bytes.indices step 4).map { uint32(bytes, it) }
    }
}

/**
 * One command/data/response transaction at a time. USB read boundaries are not
 * container boundaries: the retained buffer handles split headers, coalesced
 * data/response packets and optional zero-length USB packets.
 */
internal class PtpWireProtocol(
    private val io: PtpBulkIo,
    private val nowMillis: () -> Long = { System.nanoTime() / 1_000_000L },
    private val idleWait: () -> Unit = { Thread.sleep(1) },
) {
    companion object {
        const val MAX_METADATA_BYTES = 8 * 1024 * 1024
        const val MAX_OUT_DATA_BYTES = 64 * 1024
        const val MAX_FILE_BYTES = 512L * 1024 * 1024
        const val USB_CHUNK = 16 * 1024
    }

    private var nextTransactionId = 1L
    private val readBuffer = ByteArray(USB_CHUNK)
    private var readStart = 0
    private var readEnd = 0

    fun initialTransaction(opcode: Int, parameters: List<Long> = emptyList()): PtpReply {
        require(opcode == 0x1001 || opcode == 0x1002) { "Only initial GetDeviceInfo/OpenSession use transaction zero." }
        return execute(opcode, parameters, null, null, MAX_METADATA_BYTES.toLong(), 15_000, 0L)
    }

    fun transact(
        opcode: Int,
        parameters: List<Long> = emptyList(),
        outData: ByteArray? = null,
        timeoutMillis: Int = 15_000,
    ): PtpReply = execute(opcode, parameters, outData, null, MAX_METADATA_BYTES.toLong(), timeoutMillis, allocateTransaction())

    fun receiveTo(
        opcode: Int,
        parameters: List<Long>,
        output: OutputStream,
        maxBytes: Long,
        timeoutMillis: Int = 120_000,
    ): PtpReply = execute(opcode, parameters, null, output, maxBytes, timeoutMillis, allocateTransaction())

    private fun allocateTransaction(): Long {
        val current = nextTransactionId
        nextTransactionId = if (current >= 0xfffffffeL) 1L else current + 1L
        return current
    }

    private fun execute(
        opcode: Int,
        parameters: List<Long>,
        outData: ByteArray?,
        output: OutputStream?,
        maxBytes: Long,
        timeoutMillis: Int,
        transactionId: Long,
    ): PtpReply {
        if (opcode !in 1..0xffff || parameters.size > PtpWireCodec.MAX_PARAMETERS ||
            parameters.any { it !in 0..0xffffffffL } ||
            (outData?.size ?: 0) > MAX_OUT_DATA_BYTES ||
            maxBytes !in 0..MAX_FILE_BYTES || timeoutMillis !in 1..120_000) {
            throw PtpWireException("PTP_INVALID_ARGUMENT", "Invalid PTP command or transfer limit.", fatal = false)
        }
        val deadline = nowMillis() + timeoutMillis
        writeFrame(PtpWireCodec.command(opcode, transactionId, parameters), deadline)
        if (outData != null) {
            val frame = PtpWireCodec.header(
                (PtpWireCodec.HEADER_SIZE + outData.size).toLong(), PtpWireCodec.DATA, opcode, transactionId,
            ).copyOf(PtpWireCodec.HEADER_SIZE + outData.size)
            outData.copyInto(frame, PtpWireCodec.HEADER_SIZE)
            writeFrame(frame, deadline)
        }

        var header = readHeader(deadline)
        validateTransaction(header, transactionId)
        var receivedBytes = 0L
        val collected = if (output == null) ByteArrayOutputStream() else null
        if (header.type == PtpWireCodec.DATA) {
            if (outData != null || header.code != opcode) {
                throw PtpWireException("PTP_SEQUENCE_ERROR", "Unexpected camera data phase; the USB session must be restarted.")
            }
            receivedBytes = header.length - PtpWireCodec.HEADER_SIZE
            if (receivedBytes > maxBytes) {
                throw PtpWireException("PTP_TRANSFER_TOO_LARGE", "The camera transfer exceeds the supported size limit.")
            }
            val sink = output ?: collected!!
            var remaining = receivedBytes
            while (remaining > 0) {
                refill(deadline)
                val count = minOf(remaining, (readEnd - readStart).toLong()).toInt()
                sink.write(readBuffer, readStart, count)
                readStart += count
                remaining -= count
            }
            header = readHeader(deadline)
            validateTransaction(header, transactionId)
        }
        if (header.type != PtpWireCodec.RESPONSE || header.length > PtpWireCodec.HEADER_SIZE + 20L) {
            throw PtpWireException("PTP_SEQUENCE_ERROR", "The camera did not finish the expected command response.")
        }
        val payload = ByteArray((header.length - PtpWireCodec.HEADER_SIZE).toInt())
        readExactly(payload, deadline)
        return PtpReply(
            header.code, PtpWireCodec.responseParameters(payload), collected?.toByteArray() ?: ByteArray(0), receivedBytes,
        )
    }

    private fun validateTransaction(header: PtpHeader, transactionId: Long) {
        if (header.transactionId != transactionId) {
            throw PtpWireException("PTP_TRANSACTION_MISMATCH", "The camera replied to another USB transaction. Reconnect the camera.")
        }
    }

    private fun readHeader(deadline: Long): PtpHeader {
        val bytes = ByteArray(PtpWireCodec.HEADER_SIZE)
        readExactly(bytes, deadline)
        return PtpWireCodec.parseHeader(bytes)
    }

    private fun readExactly(target: ByteArray, deadline: Long) {
        var offset = 0
        while (offset < target.size) {
            refill(deadline)
            val length = minOf(target.size - offset, readEnd - readStart)
            readBuffer.copyInto(target, offset, readStart, readStart + length)
            offset += length
            readStart += length
        }
    }

    private fun refill(deadline: Long) {
        while (readStart == readEnd) {
            val timeout = remainingTimeout(deadline)
            val count = io.read(readBuffer, 0, readBuffer.size, timeout)
            if (count > readBuffer.size) {
                throw PtpWireException("PTP_INVALID_PACKET", "The USB driver returned an invalid transfer length.")
            }
            if (count > 0) {
                readStart = 0
                readEnd = count
                return
            }
            // -1 can mean a USB read timeout, while 0 is a valid USB ZLP.
            // Neither is a successful PTP response; both remain bounded by the
            // transaction deadline and the connection's cancellation flag.
            remainingTimeout(deadline)
            idleWait()
        }
    }

    private fun writeFrame(frame: ByteArray, deadline: Long) {
        var offset = 0
        while (offset < frame.size) {
            val requested = minOf(USB_CHUNK, frame.size - offset)
            val count = io.write(frame, offset, requested, remainingTimeout(deadline))
            if (count <= 0 || count > requested) {
                throw PtpWireException("PTP_WRITE_FAILED", "The camera did not accept the complete USB command.")
            }
            offset += count
        }
        if (io.outputPacketSize > 0 && frame.size % io.outputPacketSize == 0) {
            if (io.write(ByteArray(0), 0, 0, remainingTimeout(deadline)) < 0) {
                throw PtpWireException("PTP_WRITE_FAILED", "The camera data phase could not be terminated.")
            }
        }
    }

    private fun remainingTimeout(deadline: Long): Int {
        if (io.isClosed()) throw PtpWireException("PTP_SESSION_CLOSED", "The USB camera connection was closed.")
        val remaining = deadline - nowMillis()
        if (remaining <= 0) throw PtpWireException("PTP_TIMEOUT", "The camera did not finish its USB response in time.")
        return minOf(remaining, 1_000L).toInt().coerceAtLeast(1)
    }
}

/** Interrupt transfers can split an event or contain several events. */
internal class PtpEventFramer {
    private var buffered = ByteArray(0)

    fun accept(bytes: ByteArray): List<ByteArray> {
        if (buffered.size + bytes.size > 64 * 1024) {
            throw PtpWireException("PTP_INVALID_EVENT", "The camera event exceeds its size limit.")
        }
        buffered += bytes
        val events = mutableListOf<ByteArray>()
        var offset = 0
        while (buffered.size - offset >= PtpWireCodec.HEADER_SIZE) {
            val header = PtpWireCodec.parseHeader(buffered, offset)
            if (header.type != PtpWireCodec.EVENT || header.length > 64 * 1024) {
                throw PtpWireException("PTP_INVALID_EVENT", "The camera sent an invalid interrupt event.")
            }
            if (header.length > buffered.size - offset) break
            val length = header.length.toInt()
            events.add(buffered.copyOfRange(offset, offset + length))
            offset += length
        }
        if (offset > 0) buffered = buffered.copyOfRange(offset, buffered.size)
        return events
    }
}
