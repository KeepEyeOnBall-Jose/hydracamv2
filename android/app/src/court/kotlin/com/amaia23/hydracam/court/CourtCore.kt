package com.amaia23.hydracam.court

import com.amaia23.hydracam.phonecore.NoopPhoneLogger
import com.amaia23.hydracam.phonecore.PhoneClock
import com.amaia23.hydracam.phonecore.PhoneLogger

typealias CourtLogger = PhoneLogger
typealias NoopCourtLogger = NoopPhoneLogger
typealias CourtClock = PhoneClock
typealias HttpStatus = com.amaia23.hydracam.phonecore.HttpStatus
typealias ClockSample = com.amaia23.hydracam.phonecore.ClockSample
typealias ClockEstimate = com.amaia23.hydracam.phonecore.ClockEstimate
typealias ClockOffsetEstimator = com.amaia23.hydracam.phonecore.ClockOffsetEstimator
typealias ReconnectBackoff = com.amaia23.hydracam.phonecore.ReconnectBackoff

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
