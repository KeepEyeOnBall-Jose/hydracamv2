package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PtsClockTest {
    private var realtimeUs = 50_000_000L
    private var monotonicUs = 900_000_000L

    private fun clock(useRealtime: Boolean) = PtsClock(
        useRealtime = useRealtime,
        realtimeUs = { realtimeUs },
        monotonicUs = { monotonicUs },
        wallMs = { 1_700_000_000_000L },
    )

    @Test
    fun firstFrameOnTheOtherClockSwitchesOnce() {
        val clock = clock(useRealtime = true)
        assertEquals(realtimeUs, clock.nowUs())

        assertTrue(clock.check(monotonicUs - 30_000))
        assertEquals(monotonicUs, clock.nowUs())
        // Only the first frame decides.
        assertFalse(clock.check(realtimeUs))
        assertEquals(monotonicUs, clock.nowUs())
    }

    @Test
    fun firstFrameOnTheExpectedClockKeepsIt() {
        val realtime = clock(useRealtime = true)
        assertFalse(realtime.check(realtimeUs - 30_000))
        assertEquals(realtimeUs, realtime.nowUs())

        val monotonic = clock(useRealtime = false)
        assertFalse(monotonic.check(monotonicUs - 30_000))
        assertEquals(monotonicUs, monotonic.nowUs())
    }

    @Test
    fun wallTimeOfAPtsIsNowMinusItsAge() {
        val clock = clock(useRealtime = true)

        assertEquals(1_700_000_000_000L - 250, clock.wallMsFor(realtimeUs - 250_000))
    }
}
