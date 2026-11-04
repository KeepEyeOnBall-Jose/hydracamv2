package com.amaia23.hydracam.court

import kotlin.math.max
import kotlin.math.min

/**
 * C1 1.7: `kbps` caps the measured on-wire preview rate. H8 found encoders that cannot go below
 * ≈ 900 kbps at 640x360/20, so the bitrate alone cannot hold a 700 cap:
 *
 * - [admit] is the hard limit. A one-second token bucket bounds any span, and a [windowMs] sliding
 *   window keeps [measuredKbps] at or below the cap. Refused frames are dropped by the caller.
 *   A frame bigger than the bucket or the window (a key frame at a low cap) still goes once the
 *   bucket is full and the window empty; the bucket then runs a debt that later frames repay.
 * - [adjust] is the soft loop: it lowers the encoder bitrate toward [floorKbps], then the camera
 *   fps, so drops stay rare; with headroom it restores fps first, then bitrate.
 *
 * Not thread-safe: the preview controller calls it from one executor.
 */
class PreviewRateGovernor(
    capKbps: Int,
    private val overheadPct: Int = 8,
    private val windowMs: Long = 2_000,
    private val settleMs: Long = 2_000,
) {
    private val admitted = ArrayDeque<Pair<Long, Int>>()
    private var windowBytes = 0L
    private var tokens = 0.0
    private var refilledAt = 0L
    private var resetAt = 0L
    private var changedAt = 0L

    var capKbps: Int = capKbps
        set(value) {
            require(value > 0) { "cap must be positive" }
            val old = field
            field = value
            encoderKbps = (encoderKbps.toLong() * value / old).toInt().coerceIn(floorKbps(value), target(value))
            tokens = min(tokens, capacity())
        }

    var encoderKbps: Int = target(capKbps)
        private set

    var fps: Int = MAX_FPS
        private set

    init {
        require(capKbps > 0) { "cap must be positive" }
        tokens = capacity()
    }

    fun wireBytes(payloadBytes: Int): Int = (payloadBytes.toLong() * (PERCENT + overheadPct) / PERCENT).toInt()

    /** True when a frame of [payloadBytes] may go on the wire now; it is then counted as sent. */
    fun admit(payloadBytes: Int, nowMs: Long): Boolean {
        refill(nowMs)
        expire(nowMs)
        val wire = wireBytes(payloadBytes)
        val windowLimit = capKbps.toLong() * windowMs / BITS_PER_BYTE
        // A full bucket and an empty window let one oversized frame through: refusing it forever
        // would drop every key frame bigger than the bucket and the preview would never start.
        val bucketOk = wire <= tokens || tokens >= capacity()
        val windowOk = windowBytes + wire <= windowLimit || windowBytes == 0L
        if (!bucketOk || !windowOk) {
            return false
        }
        tokens -= wire
        admitted.addLast(nowMs to wire)
        windowBytes += wire
        return true
    }

    /** Admitted wire bytes over the last [windowMs] (shorter right after [reset]), in kbps. */
    fun measuredKbps(nowMs: Long): Int {
        expire(nowMs)
        val divisor = min(windowMs, max(nowMs - resetAt, MIN_MEASURE_MS))
        return (windowBytes * BITS_PER_BYTE / divisor).toInt()
    }

    /** One step of the soft loop; true when [encoderKbps] or [fps] changed. */
    fun adjust(nowMs: Long): Boolean {
        if (nowMs - changedAt < settleMs) {
            return false
        }
        val measured = measuredKbps(nowMs)
        val changed = when {
            measured * PERCENT > capKbps.toLong() * HIGH_PCT -> lower(measured)
            measured * PERCENT < capKbps.toLong() * LOW_PCT -> raise()
            else -> false
        }
        if (changed) {
            changedAt = nowMs
        }
        return changed
    }

    /** Forgets the rate history (a new publish); the levels stay. */
    fun reset(nowMs: Long) {
        admitted.clear()
        windowBytes = 0
        tokens = capacity()
        refilledAt = nowMs
        resetAt = nowMs
        changedAt = nowMs
    }

    private fun lower(measured: Int): Boolean {
        val floor = floorKbps(capKbps)
        return when {
            encoderKbps > floor -> {
                val scaled = (encoderKbps.toLong() * capKbps * AIM_PCT / PERCENT / measured).toInt()
                encoderKbps = max(floor, min(scaled, encoderKbps - 1))
                true
            }
            fps > MIN_FPS -> {
                fps = max(MIN_FPS, fps - FPS_STEP)
                true
            }
            else -> false
        }
    }

    private fun raise(): Boolean {
        val target = target(capKbps)
        return when {
            fps < MAX_FPS -> {
                fps = min(MAX_FPS, fps + FPS_STEP)
                true
            }
            encoderKbps < target -> {
                encoderKbps = min(target, encoderKbps * RAISE_PCT / PERCENT + 1)
                true
            }
            else -> false
        }
    }

    private fun refill(nowMs: Long) {
        if (nowMs > refilledAt) {
            tokens = min(capacity(), tokens + (nowMs - refilledAt) * capKbps.toDouble() / BITS_PER_BYTE)
            refilledAt = nowMs
        }
    }

    private fun expire(nowMs: Long) {
        while (admitted.isNotEmpty() && admitted.first().first <= nowMs - windowMs) {
            windowBytes -= admitted.removeFirst().second
        }
    }

    private fun capacity(): Double = capKbps.toDouble() * BURST_MS / BITS_PER_BYTE

    /** Encoder target: the cap less the wire overhead, with 10 % headroom. */
    private fun target(cap: Int): Int =
        max(1, (cap.toLong() * PERCENT * AIM_PCT / (PERCENT + overheadPct) / PERCENT).toInt())

    companion object {
        /**
         * The bucket holds one second at the cap: any span carries at most cap × span plus the larger
         * of one second at the cap and the biggest frame admitted.
         */
        const val BURST_MS = 1_000L
        const val MAX_FPS = 20
        const val MIN_FPS = 10
        private const val FPS_STEP = 5
        private const val PERCENT = 100
        private const val AIM_PCT = 90
        private const val HIGH_PCT = 95
        private const val LOW_PCT = 75
        private const val RAISE_PCT = 110
        private const val BITS_PER_BYTE = 8
        private const val MIN_MEASURE_MS = 250L
        private const val FLOOR_DIVISOR = 4

        /** The lowest encoder bitrate the loop asks for; below it only fps drops. */
        fun floorKbps(capKbps: Int): Int = max(1, capKbps / FLOOR_DIVISOR)
    }
}
