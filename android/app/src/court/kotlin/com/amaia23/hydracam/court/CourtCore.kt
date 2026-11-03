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

/** HTTP status codes the C0/C1/C2 clients branch on. */
object HttpStatus {
    const val OK = 200
    const val CREATED = 201
    const val UNAUTHORIZED = 401
    const val FORBIDDEN = 403
    const val NOT_FOUND = 404
    const val REQUEST_TIMEOUT = 408
    const val CONFLICT = 409
    const val TOO_MANY_REQUESTS = 429
    private val CLIENT_ERROR = 400..499

    /** A 4xx that retrying the same request will not fix (408 and 429 are transient). */
    fun isPermanentClientError(code: Int): Boolean =
        code in CLIENT_ERROR && code != REQUEST_TIMEOUT && code != TOO_MANY_REQUESTS
}

/** One `clock.ping` → `clock.pong` round trip: t0/t3 device ms, t1/t2 server ms. */
data class ClockSample(val t0: Long, val t1: Long, val t2: Long, val t3: Long) {
    val rttMs: Long get() = (t3 - t0) - (t2 - t1)

    /** server − device. */
    val offsetMs: Long get() = ((t1 - t0) + (t2 - t3)) / 2
}

data class ClockEstimate(val offsetMs: Long, val rttMs: Long)

/**
 * H10: offset to K2 from bursts of [burstSize] pings, keeping the lowest-RTT sample.
 * Until the first burst completes, the best sample so far is used; likewise after [markStale].
 */
class ClockOffsetEstimator(private val burstSize: Int = 8) {
    private val burst = mutableListOf<ClockSample>()
    private var published: ClockEstimate? = null
    private var stale = false

    @Synchronized
    fun beginBurst() {
        burst.clear()
    }

    /** K2's clock moved: drop the open burst; the next sample replaces the (still used) estimate. */
    @Synchronized
    fun markStale() {
        burst.clear()
        stale = true
    }

    @Synchronized
    fun isStale(): Boolean = stale

    /** Returns true when this sample completed a burst. */
    @Synchronized
    fun add(sample: ClockSample): Boolean {
        if (sample.rttMs < 0) {
            return false
        }
        burst += sample
        val best = burst.minBy { it.rttMs }
        val estimate = ClockEstimate(best.offsetMs, best.rttMs)
        val complete = burst.size >= burstSize
        if (complete || published == null || stale) {
            published = estimate
            stale = false
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
        val shift = min(attempt, MAX_SHIFT)
        val cap = min(maxMs, baseMs shl shift)
        attempt += 1
        val floor = max(1, cap / 2)
        return if (floor >= cap) cap else random.nextLong(floor, cap + 1)
    }

    @Synchronized
    fun reset() {
        attempt = 0
    }

    private companion object {
        const val MAX_SHIFT = 20
    }
}

/**
 * Cached root status: [rooted] never blocks. A negative answer is re-checked every [retryMs]
 * (the Magisk prompt may be approved later); [onChange] fires when the answer flips.
 */
class RootStatus(
    private val logger: CourtLogger,
    private val probe: () -> Boolean,
    private val retryMs: Long = 60_000,
    private val clock: CourtClock = CourtClock.SYSTEM,
) {
    @Volatile
    var rooted: Boolean = false
        private set

    @Volatile
    var checkedAtMs: Long = 0
        private set

    /** Blocking; call off the main thread. */
    fun check(onChange: (Boolean) -> Unit = {}): Boolean {
        val now = clock.nowMs()
        if (checkedAtMs > 0 && (rooted || now - checkedAtMs < retryMs)) {
            return rooted
        }
        val result = probe()
        checkedAtMs = now
        logger.info(TAG, "Root available: $result.")
        if (result != rooted) {
            rooted = result
            onChange(result)
        }
        return result
    }

    private companion object {
        const val TAG = "CourtRoot"
    }
}
