package com.nikofly.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CameraReceiverListenerLeaseTest {
    @Test fun lostListenerExpiresOnceAndReleasesItsOwner() {
        val tasks = mutableListOf<() -> Unit>()
        val lease = CameraReceiverListenerLease { tasks.add(it) }
        var expired = 0
        lease.attach("camera-session")
        lease.detach { expired++ }
        assertFalse(lease.attached)
        assertEquals(null, lease.sessionId)
        tasks.single()()
        tasks.single()()
        assertEquals(1, expired)
    }

    @Test fun reattachingInvalidatesAnOldCleanupTimer() {
        val tasks = mutableListOf<() -> Unit>()
        val lease = CameraReceiverListenerLease { tasks.add(it) }
        var expired = 0
        lease.attach("same-session")
        lease.detach { expired++ }
        lease.attach("same-session")
        tasks.single()()
        assertEquals(0, expired)
        assertTrue(lease.attached)
    }

    @Test fun secondDetachGetsItsOwnGracePeriod() {
        val tasks = mutableListOf<() -> Unit>()
        val lease = CameraReceiverListenerLease { tasks.add(it) }
        val expired = mutableListOf<String>()
        lease.attach("first")
        lease.detach { expired.add("first") }
        lease.attach("second")
        lease.detach { expired.add("second") }
        tasks[0]()
        assertTrue(expired.isEmpty())
        tasks[1]()
        assertEquals(listOf("second"), expired)
    }

    @Test fun onlyTheCurrentNewListenerCanReplaceAnOrphan() {
        val lease = CameraReceiverListenerLease { }
        lease.attach("new")
        assertTrue(lease.shouldReleaseOrphan("old", "new"))
        assertFalse(lease.shouldReleaseOrphan("new", "new"))
        assertFalse(lease.shouldReleaseOrphan("old", "unrelated"))
        assertFalse(lease.shouldReleaseOrphan(null, "new"))
        lease.detach { }
        assertFalse(lease.shouldReleaseOrphan("old", "new"))
    }
}
