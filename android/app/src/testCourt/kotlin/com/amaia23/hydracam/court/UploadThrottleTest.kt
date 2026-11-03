package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
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
