package com.nikofly.app

import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.util.UUID

/** Owned by the command executor; delivery records survive a USB disconnect. */
internal class PtpObjectTransferStore(private val directory: File) {
    private enum class State { RECEIVING, RECEIVED, COMPLETE, FAILED }
    private class Record(
        val handle: Long,
        val name: String,
        val expectedSize: Long,
        val file: File,
        var state: State = State.RECEIVING,
        var receivedSize: Long = 0,
    )
    private val sessions = hashMapOf<String, MutableMap<String, Record>>()
    private val acknowledged = hashMapOf<String, MutableSet<String>>()

    fun acknowledge(sessionId: String, ids: List<String>) {
        val delivered = acknowledged.getOrPut(sessionId) { hashSetOf() }
        for (id in ids) {
            sessions[sessionId]?.remove(id)
            delivered.add(id)
        }
        if (sessions[sessionId]?.isEmpty() == true) sessions.remove(sessionId)
        // Dart owns the file after persistence. Do not delete it from an ACK.
    }

    fun download(
        sessionId: String,
        transferId: String,
        handle: Long,
        originalName: String,
        expectedSize: Long,
        partialOpcode: Int?,
        consumptiveHandle: Boolean,
        allowStart: Boolean = true,
        receive: (Int, List<Long>, OutputStream, Long) -> PtpReply,
    ): Map<String, Any> {
        if (transferId.isBlank() || transferId.length > 1024 || handle !in 1..0xffffffffL ||
            expectedSize !in 0..PtpWireProtocol.MAX_FILE_BYTES ||
            (partialOpcode != null && partialOpcode != 0x101b && partialOpcode != 0x9107) ||
            (consumptiveHandle && partialOpcode != null)) {
            throw PtpWireException("PTP_INVALID_ARGUMENT", "Invalid camera photo transfer request.", false)
        }
        if (transferId in (acknowledged[sessionId] ?: emptySet())) {
            throw PtpWireException("PTP_TRANSFER_ACKNOWLEDGED", "This photo was already handed to the upload queue.", false)
        }
        val name = originalName.substringAfterLast('/').substringAfterLast('\\')
            .replace(Regex("[^A-Za-z0-9._-]"), "_").take(180).ifBlank { "camera-image.jpg" }
        val records = sessions.getOrPut(sessionId) { hashMapOf() }
        val existing = records[transferId]
        if (existing != null) {
            if (existing.handle != handle || existing.name != name || existing.expectedSize != expectedSize) {
                throw PtpWireException("PTP_TRANSFER_ID_REUSED", "A transfer ID cannot be reused for a different photo.", false)
            }
            if (existing.state == State.FAILED || existing.state == State.RECEIVING) {
                throw PtpWireException(
                    "PTP_TRANSFER_NOT_RECOVERABLE",
                    "This camera transfer was interrupted after it may have consumed the photo. Import the saved camera copy manually; the app will not substitute a later shot.", false,
                )
            }
            validateStoredFile(existing)
            if (existing.state == State.RECEIVED) {
                FileOutputStream(existing.file, true).use { it.fd.sync() }
                existing.state = State.COMPLETE
            }
            return payload(existing)
        }
        if (!allowStart) throw PtpWireException("PTP_SESSION_CLOSED", "The camera session has ended.", false)
        if (!directory.exists() && !directory.mkdirs()) {
            throw PtpWireException("PTP_STORAGE_UNAVAILABLE", "The phone cannot create camera transfer storage.", false)
        }
        val record = Record(handle, name, expectedSize, File(directory, "ptp_${UUID.randomUUID()}_$name"))
        records[transferId] = record
        var explicitRejectionWithoutData = false
        var objectCommandStarted = false
        val request: (Int, List<Long>, OutputStream, Long) -> PtpReply = { opcode, parameters, output, limit ->
            objectCommandStarted = true
            receive(opcode, parameters, output, limit)
        }
        try {
            FileOutputStream(record.file).use { output ->
                var received = 0L
                if (partialOpcode != null && expectedSize > 0) {
                    while (received < expectedSize) {
                        val requested = minOf(1024L * 1024, expectedSize - received)
                        val reply = request(partialOpcode, listOf(handle, received, requested), output, requested)
                        if (received == 0L && reply.receivedBytes == 0L && reply.responseCode == 0x2005) {
                            // Only an explicit first-command OperationNotSupported
                            // permits switching to full GetObject without ambiguity.
                            val full = request(0x1009, listOf(handle), output, PtpWireProtocol.MAX_FILE_BYTES)
                            explicitRejectionWithoutData = full.responseCode != PtpWireCodec.OK && full.receivedBytes == 0L
                            requireSuccess(full)
                            received = full.receivedBytes
                            break
                        }
                        explicitRejectionWithoutData = received == 0L && reply.receivedBytes == 0L && reply.responseCode != PtpWireCodec.OK
                        requireSuccess(reply)
                        if (reply.receivedBytes !in 1..requested ||
                            (partialOpcode == 0x101b && reply.parameters.isNotEmpty() && reply.parameters[0] != reply.receivedBytes)) {
                            throw PtpWireException("PTP_FILE_SIZE_MISMATCH", "The camera reported inconsistent partial-photo byte counts.", false)
                        }
                        received += reply.receivedBytes
                    }
                } else {
                    val reply = request(0x1009, listOf(handle), output, PtpWireProtocol.MAX_FILE_BYTES)
                    explicitRejectionWithoutData = reply.responseCode != PtpWireCodec.OK && reply.receivedBytes == 0L
                    requireSuccess(reply)
                    received = reply.receivedBytes
                }
                record.receivedSize = received
                if (received <= 0 || received > PtpWireProtocol.MAX_FILE_BYTES ||
                    record.file.length() != received || (expectedSize > 0 && received != expectedSize)) {
                    throw PtpWireException("PTP_FILE_SIZE_MISMATCH", "The transferred photo does not match the camera's reported file size.", false)
                }
                // Mark complete camera delivery before fsync/close: retrying a
                // Sony fixed RAM handle after a phone disk error reads another shot.
                record.state = State.RECEIVED
                output.flush()
                output.fd.sync()
            }
            record.state = State.COMPLETE
            return payload(record)
        } catch (error: Exception) {
            if (record.state != State.RECEIVED && record.state != State.COMPLETE) {
                if (consumptiveHandle && objectCommandStarted && !explicitRejectionWithoutData) {
                    record.state = State.FAILED
                } else {
                    records.remove(transferId)
                    if (records.isEmpty()) sessions.remove(sessionId)
                }
                record.file.delete()
            }
            throw error
        }
    }

    private fun requireSuccess(reply: PtpReply) {
        if (reply.responseCode != PtpWireCodec.OK) {
            throw PtpWireException(
                "PTP_COMMAND_REJECTED", "The camera rejected the photo transfer (0x${reply.responseCode.toString(16)}).",
                false, reply.responseCode,
            )
        }
    }

    private fun validateStoredFile(record: Record) {
        if (!record.file.isFile || record.file.length() != record.receivedSize || record.receivedSize <= 0) {
            throw PtpWireException(
                "PTP_STAGED_FILE_MISSING",
                "The previously downloaded photo is missing from phone storage. Import the saved camera copy manually; a later shot will not be substituted.", false,
            )
        }
    }

    private fun payload(record: Record): Map<String, Any> = mapOf(
        "path" to record.file.absolutePath, "name" to record.name, "size" to record.receivedSize,
    )
}
