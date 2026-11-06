package com.amaia23.hydracam.court

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
    fun unlimitedNeverSleeps() {
        val throttle = throttle(0)

        repeat(10) { throttle.acquire(1_000_000) }

        assertTrue(sleeps.isEmpty())
        assertEquals(0L, throttle.expectedNanos(1_000_000))
    }

    @Test
    fun backToBackChunksAreSpacedAtTheRate() {
        // 1000 kbps = 125 000 bytes per second.
        val throttle = throttle(1_000)

        repeat(3) { throttle.acquire(125_000) }

        assertEquals(listOf(1_000_000_000L, 2_000_000_000L), sleeps)
    }

    @Test
    fun idleTimeEarnsNoBurst() {
        val throttle = throttle(1_000)
        throttle.acquire(125_000)
        nowNs += 10_000_000_000L

        throttle.acquire(125_000)
        throttle.acquire(125_000)

        assertEquals(listOf(1_000_000_000L), sleeps)
    }

    @Test
    fun rateChangeAppliesToTheNextChunk() {
        val throttle = throttle(1_000)
        throttle.acquire(125_000)

        throttle.maxKbps = 2_000
        throttle.acquire(125_000)
        throttle.acquire(125_000)

        assertEquals(listOf(1_000_000_000L, 1_500_000_000L), sleeps)
        throttle.maxKbps = -5
        assertEquals(0, throttle.maxKbps)
    }

    @Test
    fun masterCapSlowsOnlyMasters() {
        // C1 1.11 masterMaxKbps: masters <= min(shared budget, cap); proxies keep the shared budget.
        val throttle = throttle(2_000)
        throttle.masterMaxKbps = 1_000

        throttle.acquire(125_000, master = true)
        throttle.acquire(125_000, master = true)

        assertEquals(listOf(1_000_000_000L), sleeps)
        assertEquals(1_000, throttle.masterKbps())
        assertEquals(1_000_000_000L, throttle.expectedNanos(125_000, master = true))
        assertEquals(500_000_000L, throttle.expectedNanos(125_000))
    }

    @Test
    fun masterCapHoldsWhenUploadsAreUnlimited() {
        val throttle = throttle(0)
        throttle.masterMaxKbps = 1_000

        throttle.acquire(125_000)
        throttle.acquire(125_000)
        assertTrue(sleeps.isEmpty())

        throttle.acquire(125_000, master = true)
        throttle.acquire(125_000, master = true)
        assertEquals(listOf(1_000_000_000L), sleeps)
    }

    @Test
    fun masterRateNeverExceedsTheSharedBudget() {
        val throttle = throttle(500)
        throttle.masterMaxKbps = 1_000
        assertEquals(500, throttle.masterKbps())

        throttle.masterMaxKbps = -3
        assertEquals(0, throttle.masterMaxKbps)
        // 0 holds the master lane: the uploader's gate keeps master bytes off the wire, so it never paces.
        assertEquals(500, throttle.masterKbps())
        throttle.masterMaxKbps = null
        assertEquals(500, throttle.masterKbps())
    }

    @Test
    fun shareAppliesThePolicyCapAndThePreviewShare() {
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
