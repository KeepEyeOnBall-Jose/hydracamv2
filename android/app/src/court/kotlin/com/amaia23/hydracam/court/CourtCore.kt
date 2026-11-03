package com.amaia23.hydracam.court

import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/** Logging seam: `android.util.Log` is not available in JVM unit tests. */
interface CourtLogger {
    fun info(tag: String, message: String)

    fun warn(tag: String, message: String, error: Throwable? = null)
}

object NoopCourtLogger : CourtLogger {
    override fun info(tag: String, message: String) = Unit

    override fun warn(tag: String, message: String, error: Throwable?) = Unit
}

/** Device wall clock in ms. Server time is `nowMs() + offsetMs` (see [ClockOffsetEstimator]). */
fun interface CourtClock {
    fun nowMs(): Long

    companion object {
        val SYSTEM = CourtClock { System.currentTimeMillis() }
    }
}

/** One `clock.ping` → `clock.pong` round trip: t0/t3 device ms, t1/t2 server ms. */
data class ClockSample(val t0: Long, val t1: Long, val t2: Long, val t3: Long) {
    val rttMs: Long get() = (t3 - t0) - (t2 - t1)

    /** server − device. */
    val offsetMs: Long get() = ((t1 - t0) + (t2 - t3)) / 2
}

data class ClockEstimate(val offsetMs: Long, val rttMs: Long, val sampledAtMs: Long)

/**
 * H10: offset to K2 from bursts of [burstSize] pings, keeping the lowest-RTT sample.
 * Until the first burst completes, the best sample so far is used.
 */
class ClockOffsetEstimator(private val burstSize: Int = 8) {
    private val burst = mutableListOf<ClockSample>()
    private var published: ClockEstimate? = null

    @Synchronized
    fun beginBurst() {
        burst.clear()
    }

    /** Returns true when this sample completed a burst. */
    @Synchronized
    fun add(sample: ClockSample): Boolean {
        if (sample.rttMs < 0) {
            return false
        }
        burst += sample
        val best = burst.minByOrNull { it.rttMs } ?: return false
        val estimate = ClockEstimate(best.offsetMs, best.rttMs, best.t3)
        val complete = burst.size >= burstSize
        if (complete || published == null) {
            published = estimate
        }
        if (complete) {
            burst.clear()
        }
        return complete
    }

    @Synchronized
    fun current(): ClockEstimate? = published

    fun offsetMs(): Long = current()?.offsetMs ?: 0

    fun toServerMs(deviceMs: Long): Long = deviceMs + offsetMs()

    fun toDeviceMs(serverMs: Long): Long = serverMs - offsetMs()
}

/** Jittered exponential reconnect delay ("equal jitter"), capped at [maxMs]. */
class ReconnectBackoff(
    private val baseMs: Long = 500,
    private val maxMs: Long = 30_000,
    private val random: Random = Random.Default,
) {
    private var attempt = 0

    @Synchronized
    fun nextDelayMs(): Long {
        val shift = min(attempt, 20)
        val cap = min(maxMs, baseMs shl shift)
        attempt += 1
        val floor = max(1, cap / 2)
        return if (floor >= cap) cap else random.nextLong(floor, cap + 1)
    }

    @Synchronized
    fun reset() {
        attempt = 0
    }
}
