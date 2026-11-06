package com.amaia23.hydracam.court

import java.io.InterruptedIOException
import kotlin.math.min

/**
 * R10: paces segment bytes to `upload.policy.maxKbps` so the live preview keeps uplink headroom.
 *
 * Each [acquire] books its bytes on one shared timeline and sleeps until its slot starts, so the
 * long-run rate never exceeds [maxKbps]. Idle time earns no burst credit. 0 means unlimited.
 * C1 1.11: master bytes book at [masterKbps], which also honours `masterMaxKbps`.
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

    /**
     * C1 1.11 `upload.policy.masterMaxKbps`; null means no master-only cap. 0 holds the master lane,
     * which [UploadPolicy.mastersMayMove] enforces before any master byte reaches the throttle.
     */
    @Volatile
    var masterMaxKbps: Int? = null
        set(value) {
            field = value?.coerceAtLeast(0)
        }

    private val lock = Any()
    private var nextFreeNs = nanoClock()

    /** The master rate: the shared budget, lowered to a positive [masterMaxKbps]; 0 means unlimited. */
    fun masterKbps(): Int {
        val limits = listOfNotNull(maxKbps, masterMaxKbps).filter { it > 0 }
        return limits.minOrNull() ?: 0
    }

    /** Blocks until [bytes] may be sent. Throws [InterruptedIOException] when interrupted. */
    fun acquire(bytes: Int, master: Boolean = false) {
        val kbps = rate(master)
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
    fun expectedNanos(bytes: Long, master: Boolean = false): Long {
        val kbps = rate(master)
        return if (kbps == 0) 0 else nanosFor(bytes, kbps)
    }

    /**
     * C4 v1.7: while the preview flows, uploads get [policyKbps] minus the preview rate measured on
     * the wire, never less than [MIN_SHARED_KBPS] (0 would mean unlimited) and never more than
     * [policyKbps]: a policy below the floor is kept as is. 0 policy stays unlimited.
     */
    fun shareWithPreview(policyKbps: Int, measuredPreviewKbps: Int) {
        maxKbps = budgetKbps(policyKbps, measuredPreviewKbps)
    }

    /** [shareWithPreview] for [policy]'s `maxKbps`, plus its 1.11 `masterMaxKbps` cap. */
    fun share(policy: UploadPolicy, measuredPreviewKbps: Int) {
        shareWithPreview(policy.maxKbps, measuredPreviewKbps)
        masterMaxKbps = policy.masterMaxKbps
    }

    private fun rate(master: Boolean): Int = if (master) masterKbps() else maxKbps

    companion object {
        const val MIN_SHARED_KBPS = 64

        fun budgetKbps(policyKbps: Int, measuredPreviewKbps: Int): Int = when {
            policyKbps <= 0 -> 0
            else -> (policyKbps - measuredPreviewKbps.coerceAtLeast(0))
                .coerceAtLeast(min(MIN_SHARED_KBPS, policyKbps))
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
