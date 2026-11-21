package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.InterruptedIOException

class UploadThrottleTest {
    private var nowNs = 0L
    private val sleeps = mutableListOf<Long>()

    private fun throttle(maxKbps: Int) = UploadThrottle(maxKbps, nanoClock = { nowNs }, sleeper = { sleeps += it })

    @Test
    fun unlimitedAndNonPositiveBytesNeverSleep() {
        val throttle = throttle(0)

        repeat(5) { throttle.acquire(1_000_000) }
        throttle(1_000).acquire(0)
        throttle(1_000).acquire(-10)

        assertTrue(sleeps.isEmpty())
        assertEquals(0L, throttle.expectedNanos(1_000_000))
    }

    @Test
    fun backToBackChunksAreSpacedAndIdleTimeEarnsNoBurst() {
        val throttle = throttle(1_000)
        repeat(3) { throttle.acquire(125_000) }
        assertEquals(listOf(1_000_000_000L, 2_000_000_000L), sleeps)

        sleeps.clear()
        val burstCheck = throttle(1_000)
        burstCheck.acquire(125_000)
        nowNs += 10_000_000_000L
        burstCheck.acquire(125_000)
        burstCheck.acquire(125_000)
        assertEquals(listOf(1_000_000_000L), sleeps)
    }

    @Test
    fun rateChangeAndMasterCapControlLanes() {
        val throttle = throttle(2_000)
        throttle.masterMaxKbps = 1_000

        throttle.acquire(125_000, master = true)
        throttle.acquire(125_000, master = true)
        assertEquals(listOf(1_000_000_000L), sleeps)
        assertEquals(1_000, throttle.masterKbps())
        assertEquals(1_000_000_000L, throttle.expectedNanos(125_000, master = true))
        assertEquals(500_000_000L, throttle.expectedNanos(125_000))

        throttle.maxKbps = -5
        assertEquals(0, throttle.maxKbps)
        throttle.masterMaxKbps = -3
        assertEquals(0, throttle.masterMaxKbps)
        throttle.masterMaxKbps = null
        assertEquals(0, throttle.masterKbps())
    }

    @Test
    fun shareAppliesPolicyCapAndPreviewFloor() {
        assertEquals(32, UploadThrottle.budgetKbps(policyKbps = 32, measuredPreviewKbps = 100))
        assertEquals(UploadThrottle.MIN_SHARED_KBPS, UploadThrottle.budgetKbps(1_000, 2_000))
        assertEquals(0, UploadThrottle.budgetKbps(0, 500))

        val throttle = throttle(0)
        val policy = UploadPolicy.DEFAULT.copy(
            masterMode = UploadPolicy.MODE_STREAM,
            maxKbps = 10_000,
            masterMaxKbps = 8_000,
        )

        throttle.share(policy, measuredPreviewKbps = 3_000)
        assertEquals(7_000, throttle.maxKbps)
        assertEquals(7_000, throttle.masterKbps())

        throttle.share(policy, measuredPreviewKbps = 0)
        assertEquals(10_000, throttle.maxKbps)
        assertEquals(8_000, throttle.masterKbps())

        throttle.share(policy.copy(masterMaxKbps = null), measuredPreviewKbps = 1_000)
        assertNull(throttle.masterMaxKbps)
        assertEquals(9_000, throttle.masterKbps())
    }

    @Test
    fun interruptedSleepThrowsInterruptedIo() {
        val throttle = UploadThrottle(maxKbps = 8)
        throttle.acquire(1_000)
        Thread.currentThread().interrupt()
        try {
            throttle.acquire(1_000)
            fail("Expected InterruptedIOException")
        } catch (expected: InterruptedIOException) {
            assertTrue(Thread.interrupted())
        }
    }
}
