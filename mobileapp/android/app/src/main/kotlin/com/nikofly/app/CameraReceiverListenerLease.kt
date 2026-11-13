package com.nikofly.app

/** Event listener ownership is independent of USB session ownership. */
internal class CameraReceiverListenerLease(private val schedule: (() -> Unit) -> Unit) {
    private var generation = 0L
    var sessionId: String? = null
        private set
    var attached = false
        private set

    fun attach(id: String?) {
        generation++
        sessionId = id
        attached = true
    }

    fun detach(onExpired: () -> Unit) {
        val detachedGeneration = ++generation
        sessionId = null
        attached = false
        schedule {
            if (!attached && generation == detachedGeneration) {
                generation++
                onExpired()
            }
        }
    }

    fun shouldReleaseOrphan(activeId: String?, requestedId: String): Boolean =
        attached && sessionId == requestedId && activeId != null && activeId != requestedId
}
