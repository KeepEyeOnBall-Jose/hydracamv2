package com.amaia23.hydracam.court

import java.io.InterruptedIOException

/**
 * R10: paces segment bytes to `upload.policy.maxKbps` so the live preview keeps uplink headroom.
 *
 * Each [acquire] books its bytes on one shared timeline and sleeps until its slot starts, so the
 * long-run rate never exceeds [maxKbps]. Idle time earns no burst credit. 0 means unlimited.
 */
class UploadThrottle(
    maxKbps: Int = UploadPolicy.DEFAULT.maxKbps,
    private val nanoClock: () -> Long = System::nanoTime,
    private val sleeper: (Long) -> Unit = ::sleepNanos,
) {
    @Volatile
    var maxKbps: Int = maxKbps.coerceAtLeast(0)
        set(value) {
            field = value.coerceAtLeast(0)
        }

    private val lock = Any()
    private var nextFreeNs = nanoClock()

    /** Blocks until [bytes] may be sent. Throws [InterruptedIOException] when interrupted. */
    fun acquire(bytes: Int) {
        val kbps = maxKbps
        if (kbps == 0 || bytes <= 0) {
            return
        }
        val waitNs: Long
        synchronized(lock) {
            val now = nanoClock()
            // nanoTime values compare only by difference.
            val start = if (nextFreeNs - now > 0) nextFreeNs else now
            nextFreeNs = start + nanosFor(bytes.toLong(), kbps)
            waitNs = start - now
        }
        if (waitNs > 0) {
            sleeper(waitNs)
        }
    }

    /** Time [bytes] take at the current rate; 0 when unlimited. */
    fun expectedNanos(bytes: Long): Long {
        val kbps = maxKbps
        return if (kbps == 0) 0 else nanosFor(bytes, kbps)
    }

    /**
     * C4 v1.7: while the preview flows, uploads get [policyKbps] minus the preview rate measured on
     * the wire, never less than [MIN_SHARED_KBPS] (0 would mean unlimited). 0 policy stays unlimited.
     */
    fun shareWithPreview(policyKbps: Int, measuredPreviewKbps: Int) {
        maxKbps = budgetKbps(policyKbps, measuredPreviewKbps)
    }

    companion object {
        const val MIN_SHARED_KBPS = 64

        fun budgetKbps(policyKbps: Int, measuredPreviewKbps: Int): Int = when {
            policyKbps <= 0 -> 0
            else -> (policyKbps - measuredPreviewKbps.coerceAtLeast(0)).coerceAtLeast(MIN_SHARED_KBPS)
        }

        /** One byte (8 bits) at 1 kbps (1000 bit/s) takes 8 ms. */
        private const val NANOS_PER_BYTE_AT_1_KBPS = 8_000_000L

        private fun nanosFor(bytes: Long, kbps: Int): Long = bytes * NANOS_PER_BYTE_AT_1_KBPS / kbps

        private fun sleepNanos(nanos: Long) {
            try {
                Thread.sleep(nanos / 1_000_000, (nanos % 1_000_000).toInt())
            } catch (error: InterruptedException) {
                Thread.currentThread().interrupt()
                throw InterruptedIOException("Upload throttle interrupted.")
            }
        }
    }
}
