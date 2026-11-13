package com.nikofly.app

import java.io.File
import java.io.OutputStream
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class PtpObjectTransferStoreTest {
    @get:Rule val folder = TemporaryFolder()
    private fun reply(output: OutputStream, bytes: ByteArray, response: Int = 0x2001, parameters: List<Long> = emptyList()): PtpReply {
        output.write(bytes)
        return PtpReply(response, parameters, byteArrayOf(), bytes.size.toLong())
    }
    private fun failure(code: String, block: () -> Unit) {
        try { block(); fail("Expected $code") } catch (error: PtpWireException) { assertEquals(code, error.code) }
    }

    @Test fun sonyRetryReusesCompletedFileAndNeverConsumesTheNextShot() {
        val store = PtpObjectTransferStore(folder.root)
        var calls = 0
        fun download() = store.download("session", "shot1", 0xffffc001, "DSC0001.JPG", 3, null, true) { opcode, _, output, _ ->
            calls++
            assertEquals(0x1009, opcode)
            reply(output, byteArrayOf(7, 8, 9))
        }
        val first = download()
        val repeated = download()
        assertEquals(first, repeated)
        assertEquals(1, calls)
        assertArrayEquals(byteArrayOf(7, 8, 9), File(first["path"] as String).readBytes())
        store.acknowledge("session", listOf("shot1"))
        assertTrue(File(first["path"] as String).exists()) // ACK leaves deletion to Dart.
        failure("PTP_TRANSFER_ACKNOWLEDGED") { download() }
        assertEquals(1, calls)
    }

    @Test fun missingStagedSonyFileIsAnErrorInsteadOfDownloadingAnotherShot() {
        val store = PtpObjectTransferStore(folder.root)
        var calls = 0
        fun download() = store.download("s", "photo", 0xffffc001, "a.jpg", 1, null, true) { _, _, output, _ ->
            calls++; reply(output, byteArrayOf(1))
        }
        val record = download()
        File(record["path"] as String).delete()
        failure("PTP_STAGED_FILE_MISSING") { download() }
        assertEquals(1, calls)
    }

    @Test fun ambiguousSonyTransferFailureCannotBeRetriedAgainstFixedHandle() {
        val store = PtpObjectTransferStore(folder.root)
        var calls = 0
        fun download() = store.download("s", "photo", 0xffffc001, "a.jpg", 1, null, true) { _, _, _, _ ->
            calls++
            throw PtpWireException("PTP_TIMEOUT", "response lost")
        }
        failure("PTP_TIMEOUT") { download() }
        failure("PTP_TRANSFER_NOT_RECOVERABLE") { download() }
        assertEquals(1, calls)
    }

    @Test fun explicitBusyWithoutDataAllowsSafeRetry() {
        val store = PtpObjectTransferStore(folder.root)
        var calls = 0
        fun download() = store.download("s", "photo", 0xffffc001, "a.jpg", 1, null, true) { _, _, output, _ ->
            calls++
            if (calls == 1) reply(output, byteArrayOf(), 0x2019) else reply(output, byteArrayOf(1))
        }
        failure("PTP_COMMAND_REJECTED") { download() }
        download()
        assertEquals(2, calls)
    }

    @Test fun partialReadsAdvanceByActualBytesAndRespectExpectedTotal() {
        val store = PtpObjectTransferStore(folder.root)
        val offsets = mutableListOf<Long>()
        val result = store.download("s", "photo", 3, "a.jpg", 7, 0x101b, false) { opcode, params, output, maximum ->
            assertEquals(0x101b, opcode)
            offsets.add(params[1])
            val bytes = if (params[1] == 0L) byteArrayOf(1, 2, 3) else byteArrayOf(4, 5, 6, 7)
            assertTrue(bytes.size <= maximum)
            reply(output, bytes, parameters = listOf(bytes.size.toLong()))
        }
        assertEquals(listOf(0L, 3L), offsets)
        assertEquals(7L, result["size"])
        assertArrayEquals(byteArrayOf(1, 2, 3, 4, 5, 6, 7), File(result["path"] as String).readBytes())
    }

    @Test fun onlyFirstUnsupportedPartialResponseCanFallBackToFullObject() {
        val store = PtpObjectTransferStore(folder.root)
        val opcodes = mutableListOf<Int>()
        store.download("s", "photo", 3, "a.jpg", 3, 0x9107, false) { opcode, _, output, _ ->
            opcodes.add(opcode)
            if (opcode == 0x9107) reply(output, byteArrayOf(), 0x2005) else reply(output, byteArrayOf(1, 2, 3))
        }
        assertEquals(listOf(0x9107, 0x1009), opcodes)
    }

    @Test fun partialErrorAfterReceivingBytesMustNotRestartAsFullObject() {
        val store = PtpObjectTransferStore(folder.root)
        val opcodes = mutableListOf<Int>()
        failure("PTP_COMMAND_REJECTED") {
            store.download("s", "photo", 3, "a.jpg", 3, 0x9107, false) { opcode, _, output, _ ->
                opcodes.add(opcode)
                if (opcodes.size == 1) reply(output, byteArrayOf(1)) else reply(output, byteArrayOf(), 0x2005)
            }
        }
        assertEquals(listOf(0x9107, 0x9107), opcodes)
        assertTrue(folder.root.listFiles()!!.isEmpty())
    }

    @Test fun cachedPhotoCanBeDeliveredAfterSessionStopsButFreshPhotoCannot() {
        val store = PtpObjectTransferStore(folder.root)
        val first = store.download("old-session", "photo", 1, "a.jpg", 1, null, false) { _, _, output, _ -> reply(output, byteArrayOf(1)) }
        val recovered = store.download("old-session", "photo", 1, "a.jpg", 1, null, false, allowStart = false) { _, _, _, _ -> error("Must not access USB") }
        assertEquals(first, recovered)
        failure("PTP_SESSION_CLOSED") {
            store.download("old-session", "next", 2, "b.jpg", 1, null, false, allowStart = false) { _, _, _, _ -> error("Must not access USB") }
        }
        store.acknowledge("old-session", listOf("photo"))
        assertTrue(File(first["path"] as String).exists())
    }

    @Test fun staleIdCannotAliasAnotherHandleOrFilename() {
        val store = PtpObjectTransferStore(folder.root)
        store.download("s", "photo", 1, "a.jpg", 1, null, false) { _, _, output, _ -> reply(output, byteArrayOf(1)) }
        failure("PTP_TRANSFER_ID_REUSED") {
            store.download("s", "photo", 2, "b.jpg", 1, null, false) { _, _, _, _ -> error("Must not access USB") }
        }
    }
}
