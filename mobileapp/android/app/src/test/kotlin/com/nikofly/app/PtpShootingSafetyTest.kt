package com.nikofly.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Assert.fail
import org.junit.Test

class PtpShootingSafetyTest {
    @Test fun rejectsCrossBrandUnknownAndUnsafeModeCommands() {
        val approved = listOf(
            Triple(0x4a9, 0x9114, listOf<Long>(0x0L)),
            Triple(0x4a9, 0x9114, listOf<Long>(0x1L)),
            Triple(0x4a9, 0x9115, listOf<Long>(0x0L)),
            Triple(0x4a9, 0x9115, listOf<Long>(0x1L)),
            Triple(0x4a9, 0x9116, listOf<Long>()),
            Triple(0x4a9, 0x9127, listOf<Long>(0xd11cL)),
            Triple(0x4a9, 0x9117, listOf<Long>(0x2aL)),
            Triple(0x4a9, 0x9107, listOf<Long>()),
            Triple(0x4b0, 0x90c2, listOf<Long>(0x0L)),
            Triple(0x4b0, 0x90c7, listOf<Long>()),
            Triple(0x4b0, 0x941c, listOf<Long>()),
            Triple(0x54c, 0x9201, listOf<Long>(0x1L, 0x0L, 0x0L)),
            Triple(0x54c, 0x9201, listOf<Long>(0x2L, 0x0L, 0x0L)),
            Triple(0x54c, 0x9201, listOf<Long>(0x3L, 0x0L, 0x0L)),
            Triple(0x54c, 0x9202, listOf<Long>(0x12cL, 0x1L)),
            Triple(0x54c, 0x9209, listOf<Long>()),
            Triple(0x4da, 0x940a, listOf<Long>(0x8000090L)),
        )
        val vendors = listOf(0, 0x1234, 0x04a9, 0x04b0, 0x054c, 0x04cb, 0x04da, 0x33a2, 0x0a17)
        for ((vendor, opcode, params) in approved) {
            assertTrue(PtpShootingSafety.isAllowed(opcode, vendor, params))
            for (other in vendors.filter { it != vendor }) {
                assertFalse(PtpShootingSafety.isAllowed(opcode, other, params))
            }
        }
        for ((vendor, opcode, params) in listOf(
            Triple(0x4a9, 0x9114, listOf<Long>()),
            Triple(0x4a9, 0x9114, listOf<Long>(0x2L)),
            Triple(0x4a9, 0x9115, listOf<Long>(0x2L)),
            Triple(0x4a9, 0x9117, listOf<Long>(0x0L)),
            Triple(0x4a9, 0x9127, listOf<Long>(0xd1b0L)),
            Triple(0x4b0, 0x90c2, listOf<Long>(0x1L)),
            Triple(0x4b0, 0x90c2, listOf<Long>()),
            Triple(0x54c, 0x9201, listOf<Long>(0x1L, 0x1L, 0x0L)),
            Triple(0x54c, 0x9201, listOf<Long>(0x4L, 0x0L, 0x0L)),
            Triple(0x54c, 0x9202, listOf<Long>()),
            Triple(0x54c, 0x9209, listOf<Long>(0x1L)),
        )) {
            assertFalse(PtpShootingSafety.isAllowed(opcode, vendor, params))
        }
        for (vendor in vendors) {
            for (opcode in listOf(0x1002, 0x1003, 0x90c0, 0x90c1, 0x920a, 0x920b, 0x9152, 0x9999)) {
                assertFalse(PtpShootingSafety.isAllowed(opcode, vendor))
            }
            assertFalse(PtpShootingSafety.isAllowed(0x1009, vendor, outgoing = byteArrayOf(1)))
        }
    }

    @Test fun scopesVendorCommandsAndOMHandshake() {
        for (vendor in listOf(0x04da, 0x07b4, 0x33a2, 0x0a17, 0x25fb)) {
            for (opcode in listOf(0x100c, 0x100d, 0x1013, 0x1017, 0x101c,
                0x9403, 0x9404, 0x940b, 0x9412, 0x9704,
                0x9107, 0x910b, 0x9481, 0x9489, 0x948c, 0x94be)) {
                assertFalse(PtpShootingSafety.isAllowed(opcode, vendor))
            }
            assertTrue(PtpShootingSafety.isAllowed(0x1009, vendor))
            assertTrue(PtpShootingSafety.isAllowed(0x101b, vendor))
        }
        assertTrue(PtpShootingSafety.isAllowed(0x940a, 0x04da, listOf(0x08000090L)))
        assertFalse(PtpShootingSafety.isAllowed(0x940a, 0x04da))
        for (vendor in listOf(0x07b4, 0x33a2)) {
            for (value in listOf(1, 2)) {
                assertTrue(PtpShootingSafety.isAllowed(0x1016, vendor,
                    listOf(0xd052L), byteArrayOf(value.toByte(), 0)))
            }
            for (bytes in listOf(byteArrayOf(), byteArrayOf(0, 0),
                byteArrayOf(3, 0), byteArrayOf(1), byteArrayOf(1, 1), byteArrayOf(1, 0, 0))) {
                assertFalse(PtpShootingSafety.isAllowed(0x1016, vendor, listOf(0xd052L), bytes))
            }
            assertFalse(PtpShootingSafety.isAllowed(0x1016, vendor, listOf(0xd0dcL), byteArrayOf(2, 0)))
        }
        assertFalse(PtpShootingSafety.isAllowed(0x1016, 0x04da, listOf(0xd052L), byteArrayOf(1, 0)))
    }

    @Test fun blocksRemoteShutterUiLockAndDeletion() {
        for (opcode in listOf(
            0x100b, 0x100e, 0x100f, 0x1010,
            0x910f, 0x911b, 0x9128, 0x9129, 0x9151, 0x9207,
            0x1016, 0x9110, 0x9205, 0x9206,
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
        )) {
            PtpShootingSafety.requirePassive(opcode)
        }
    }
}
