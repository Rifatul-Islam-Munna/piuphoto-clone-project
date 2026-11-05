package com.nikofly.app

import java.io.ByteArrayOutputStream
import java.util.ArrayDeque
import org.junit.Assert.*
import org.junit.Test

class PtpWireProtocolTest {
    private class FakeUsb(vararg fragments: ByteArray) : PtpBulkIo {
        private val incoming = ArrayDeque<ByteArray>().apply { fragments.forEach(::addLast) }
        private var offset = 0
        val writes = mutableListOf<ByteArray>()
        var maxWrite = Int.MAX_VALUE
        var closed = false
        var onRead: (() -> Unit)? = null
        override val outputPacketSize = 64
        override fun isClosed() = closed
        override fun read(buffer: ByteArray, offset: Int, length: Int, timeoutMillis: Int): Int {
            onRead?.invoke()
            if (incoming.isEmpty()) return -1
            val head = incoming.first
            val count = minOf(length, head.size - this.offset)
            head.copyInto(buffer, offset, this.offset, this.offset + count)
            this.offset += count
            if (this.offset == head.size) { incoming.removeFirst(); this.offset = 0 }
            return count
        }
        override fun write(buffer: ByteArray, offset: Int, length: Int, timeoutMillis: Int): Int {
            val count = minOf(length, maxWrite)
            writes.add(buffer.copyOfRange(offset, offset + count))
            return count
        }
    }

    private fun u32(value: Long) = ByteArray(4) { (value ushr (it * 8)).toByte() }
    private fun frame(type: Int, code: Int, transaction: Long, payload: ByteArray = byteArrayOf()) =
        PtpWireCodec.header((12 + payload.size).toLong(), type, code, transaction) + payload
    private fun response(transaction: Long, code: Int = 0x2001, payload: ByteArray = byteArrayOf()) = frame(3, code, transaction, payload)
    private fun failure(code: String, block: () -> Unit) {
        try { block(); fail("Expected $code") } catch (error: PtpWireException) { assertEquals(code, error.code) }
    }

    @Test fun fragmentedHeadersAndCoalescedDataResponsePreserveEveryByte() {
        val bytes = byteArrayOf(0, 1, 2, 3, 4, 0xff.toByte())
        val wire = frame(2, 0x1009, 1, bytes) + response(1, payload = u32(0xffffffffL))
        val usb = FakeUsb(wire.copyOfRange(0, 3), byteArrayOf(), wire.copyOfRange(3, 9), wire.copyOfRange(9, wire.size))
        val reply = PtpWireProtocol(usb).transact(0x1009, listOf(0xffffc001L))
        assertArrayEquals(bytes, reply.data)
        assertEquals(listOf(0xffffffffL), reply.parameters)
        assertEquals(6L, reply.receivedBytes)
        assertEquals(0xffffc001L, PtpWireCodec.uint32(usb.writes.first(), 12))
    }

    @Test fun initialCommandsUseZeroAndFirstSessionCommandUsesOne() {
        val usb = FakeUsb(response(0), response(0), response(1))
        val protocol = PtpWireProtocol(usb)
        protocol.initialTransaction(0x1001)
        protocol.initialTransaction(0x1002, listOf(1))
        protocol.transact(0x1005)
        assertEquals(listOf(0L, 0L, 1L), usb.writes.map { PtpWireCodec.parseHeader(it).transactionId })
    }

    @Test fun cameraErrorResponseWithoutDataIsReturnedAccurately() {
        val reply = PtpWireProtocol(FakeUsb(response(1, 0x2019))).transact(0x1009, listOf(9))
        assertEquals(0x2019, reply.responseCode)
        assertEquals(0L, reply.receivedBytes)
        assertTrue(reply.data.isEmpty())
    }

    @Test fun transactionMismatchCannotBeAcceptedAsAnotherShot() {
        failure("PTP_TRANSACTION_MISMATCH") { PtpWireProtocol(FakeUsb(response(2))).transact(0x1009, listOf(9)) }
    }

    @Test fun wrongOperationDataPhaseIsRejected() {
        failure("PTP_SEQUENCE_ERROR") { PtpWireProtocol(FakeUsb(frame(2, 0x1008, 1))).transact(0x1009, listOf(9)) }
    }

    @Test fun metadataLimitIsCheckedBeforeReadingThePayload() {
        val oversized = PtpWireCodec.header(PtpWireProtocol.MAX_METADATA_BYTES + 13L, 2, 0x1001, 1)
        failure("PTP_TRANSFER_TOO_LARGE") { PtpWireProtocol(FakeUsb(oversized)).transact(0x1001) }
    }

    @Test fun rawPhotoLargerThanMetadataLimitStreamsWithoutChannelDataAllocation() {
        val bytes = ByteArray(PtpWireProtocol.MAX_METADATA_BYTES + 17) { (it % 251).toByte() }
        val usb = FakeUsb(frame(2, 0x1009, 1, bytes), response(1))
        val output = ByteArrayOutputStream()
        val reply = PtpWireProtocol(usb).receiveTo(0x1009, listOf(1), output, PtpWireProtocol.MAX_FILE_BYTES)
        assertArrayEquals(bytes, output.toByteArray())
        assertTrue(reply.data.isEmpty())
        assertEquals(bytes.size.toLong(), reply.receivedBytes)
    }

    @Test fun outgoingDataEndsAlignedUsbPacketWithZlpAndHandlesShortWrites() {
        val usb = FakeUsb(response(1)).apply { maxWrite = 7 }
        PtpWireProtocol(usb).transact(0x9207, listOf(0xd25a), ByteArray(52) { it.toByte() })
        assertEquals(0, usb.writes.last().size)
        val joined = usb.writes.fold(byteArrayOf()) { acc, part -> acc + part }
        assertEquals(16 + 64, joined.size)
        assertEquals(1L, PtpWireCodec.parseHeader(joined).transactionId)
        assertEquals(PtpWireCodec.DATA, PtpWireCodec.parseHeader(joined, 16).type)
    }

    @Test fun invalidOutgoingLimitIsRejectedBeforeAnyUsbWrite() {
        val usb = FakeUsb()
        failure("PTP_INVALID_ARGUMENT") { PtpWireProtocol(usb).transact(0x9207, outData = ByteArray(65537)) }
        assertTrue(usb.writes.isEmpty())
    }

    @Test fun readTimeoutIsBoundedAndNeverReportedAsSuccess() {
        var clock = 0L
        val usb = FakeUsb().apply { onRead = { clock += 500 } }
        failure("PTP_TIMEOUT") { PtpWireProtocol(usb, { clock }, {}).transact(0x1005, timeoutMillis = 1000) }
    }

    @Test fun responseParametersMustBeCompleteUnsignedWords() {
        failure("PTP_INVALID_PACKET") { PtpWireProtocol(FakeUsb(response(1, payload = byteArrayOf(1)))).transact(0x1005) }
    }

    @Test fun interruptFramingHandlesSplitAndMultipleEvents() {
        val a = frame(4, 0x4002, 0xffffffffL, u32(0xffffc001L))
        val b = frame(4, 0xc203, 17, u32(0xd215))
        val framer = PtpEventFramer()
        assertTrue(framer.accept(a.copyOfRange(0, 5)).isEmpty())
        val events = framer.accept(a.copyOfRange(5, a.size) + b)
        assertEquals(2, events.size)
        assertArrayEquals(a, events[0])
        assertArrayEquals(b, events[1])
    }

    @Test fun malformedEventCannotBeDeliveredAsANewPhoto() {
        failure("PTP_INVALID_EVENT") { PtpEventFramer().accept(response(1)) }
    }
}
