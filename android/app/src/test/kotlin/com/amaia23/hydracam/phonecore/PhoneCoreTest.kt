package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class PhoneCoreTest {
    private fun sample(t0: Long, rtt: Long, offset: Long = 1_000): ClockSample {
        val t1 = t0 + rtt / 2 + offset
        val t2 = t1 + 1
        val t3 = t2 - offset + rtt / 2
        return ClockSample(t0, t1, t2, t3)
    }

    @Test
    fun noopLoggerAndSystemClockWorkOnJvm() {
        NoopPhoneLogger.info("Tag", "message")
        NoopPhoneLogger.warn("Tag", "warn", IllegalStateException("test"))
        assertTrue(PhoneClock.SYSTEM.nowMs() > 0L)
        val fixed = PhoneClock { 42L }
        assertEquals(42L, fixed.nowMs())
    }

    @Test
    fun sampleMath() {
        val s = ClockSample(t0 = 100, t1 = 1_110, t2 = 1_112, t3 = 122)
        assertEquals(20L, s.rttMs)
        assertEquals(1_000L, s.offsetMs)
    }

    @Test
    fun burstKeepsLowestRttSample() {
        val estimator = ClockOffsetEstimator(burstSize = 8)
        estimator.beginBurst()
        val rtts = listOf(80L, 40L, 60L, 12L, 90L, 30L, 50L, 70L)
        rtts.forEachIndexed { index, rtt ->
            val offset = if (rtt == 12L) 1_000L else 1_000L + rtt
            val complete = estimator.add(sample(index * 300L, rtt, offset))
            assertEquals(index == rtts.lastIndex, complete)
        }

        val estimate = estimator.current()!!
        assertEquals(12L, estimate.rttMs)
        assertEquals(1_000L, estimate.offsetMs)
        assertEquals(6_000L, estimator.toServerMs(5_000))
        assertEquals(5_000L, estimator.toDeviceMs(6_000))
    }

    @Test
    fun firstSamplePublishesBeforeBurstCompletes() {
        val estimator = ClockOffsetEstimator(burstSize = 8)
        assertNull(estimator.current())
        assertEquals(0L, estimator.offsetMs())

        assertFalse(estimator.add(sample(0, rtt = 50, offset = 1_050)))
        assertEquals(1_050L, estimator.offsetMs())

        estimator.add(sample(300, rtt = 10, offset = 1_000))
        assertEquals(1_050L, estimator.offsetMs())
    }

    @Test
    fun negativeRttIsRejected() {
        val estimator = ClockOffsetEstimator(burstSize = 1)
        assertFalse(estimator.add(ClockSample(t0 = 100, t1 = 0, t2 = 500, t3 = 101)))
        assertNull(estimator.current())
    }

    @Test
    fun staleEstimateIsKeptUntilTheNextSampleReplacesIt() {
        val estimator = ClockOffsetEstimator(burstSize = 2)
        estimator.add(sample(0, rtt = 10, offset = 1_000))
        estimator.add(sample(10, rtt = 20, offset = 1_000))
        estimator.add(sample(20, rtt = 5, offset = 1_000))
        assertFalse(estimator.isStale())

        estimator.markStale()
        assertTrue(estimator.isStale())
        assertEquals(1_000L, estimator.offsetMs())
        assertFalse(estimator.add(sample(30, rtt = 40, offset = 91_000)))
        assertFalse(estimator.isStale())
        assertEquals(91_000L, estimator.offsetMs())

        assertTrue(estimator.add(sample(40, rtt = 30, offset = 91_000)))
        assertEquals(30L, estimator.current()!!.rttMs)
    }

    @Test
    fun backoffIsJitteredCappedAndResets() {
        val backoff = ReconnectBackoff(random = Random(7))
        var cap = 500L
        repeat(30) {
            val delay = backoff.nextDelayMs()
            assertTrue("delay $delay for cap $cap", delay in (cap / 2)..cap)
            cap = minOf(30_000L, cap * 2)
        }
        assertTrue(backoff.nextDelayMs() >= 15_000)

        backoff.reset()
        assertTrue(backoff.nextDelayMs() <= 500)

        val unit = ReconnectBackoff(baseMs = 1, maxMs = 1)
        assertEquals(listOf(1L, 1L, 1L), List(3) { unit.nextDelayMs() })
    }

    @Test
    fun permanentClientErrorsExclude408And429() {
        val codes = listOf(
            HttpStatus.OK,
            HttpStatus.CREATED,
            399,
            400,
            HttpStatus.UNAUTHORIZED,
            HttpStatus.FORBIDDEN,
            HttpStatus.NOT_FOUND,
            HttpStatus.REQUEST_TIMEOUT,
            HttpStatus.CONFLICT,
            HttpStatus.TOO_MANY_REQUESTS,
            499,
            500,
        )
        assertEquals(listOf(400, 401, 403, 404, 409, 499), codes.filter(HttpStatus::isPermanentClientError))
    }
}
