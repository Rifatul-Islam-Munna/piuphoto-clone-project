package com.nikofly.app

import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class PtpShootingSafetyTest {
    @Test fun blocksRemoteShutterUiLockAndDeletion() {
        for (opcode in listOf(
            0x100b, 0x100e, 0x100f, 0x1010,
            0x910f, 0x911b, 0x9128, 0x9129, 0x9151, 0x9207,
        )) {
            try {
                PtpShootingSafety.requirePassive(opcode)
                fail("Expected opcode $opcode to be blocked")
            } catch (error: PtpWireException) {
                assertEquals("PTP_SHOOTING_COMMAND_BLOCKED", error.code)
            }
        }
    }

    @Test fun allowsReadOnlyTetherProtocolAndCameraPriorityCommands() {
        for (opcode in listOf(
            0x1001, 0x1004, 0x1007, 0x1008, 0x1009, 0x101b,
            0x9114, 0x9115, 0x9116, 0x90c2, 0x90c7,
            0x941c, 0x9201, 0x9202, 0x9205, 0x9209,
        )) {
            PtpShootingSafety.requirePassive(opcode)
        }
    }
}
