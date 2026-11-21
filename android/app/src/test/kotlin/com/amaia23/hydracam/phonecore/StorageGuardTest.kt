package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StorageGuardTest {
    private var free = 0L
    private val guard = StorageGuard({ free })
    private val profile = RecordProfile(masterKbps = 8_000, proxyKbps = 2_000, segmentS = 6)

    @Test
    fun bytesForIsDurationTimesBothTierRates() {
        assertEquals(2L * 1024 * 1024 * 1024, StorageGuard.RESERVE_BYTES)
        assertEquals(1_250_000L, guard.bytesFor(1, profile))
        assertEquals(4_500_000_000L, guard.bytesFor(3_600, profile))
        assertEquals(0L, guard.bytesFor(0, profile))
    }

    @Test
    fun refusesWhenDurationDoesNotFitAboveReserve() {
        free = StorageGuard.RESERVE_BYTES + 4_500_000_000L
        assertFalse(guard.refuses(3_600, profile))

        free -= 1
        assertTrue(guard.refuses(3_600, profile))

        free = StorageGuard.RESERVE_BYTES - 1
        assertTrue(guard.refuses(1, profile))
    }

    @Test
    fun blockedWhileLessThanTenMinutesFit() {
        free = StorageGuard.RESERVE_BYTES + 750_000_000L
        assertFalse(guard.blocked(profile))

        free -= 1
        assertTrue(guard.blocked(profile))
        assertEquals(600L, StorageGuard.BLOCKED_BELOW_S)
    }

    @Test
    fun exhaustedWhenNextSegmentWouldEatIntoReserve() {
        free = StorageGuard.RESERVE_BYTES + 7_500_000L
        assertFalse(guard.exhausted(profile))

        free -= 1
        assertTrue(guard.exhausted(profile))
    }

    @Test
    fun customReserveIsHonoured() {
        val small = StorageGuard({ free }, reserveBytes = 0)
        free = 1_250_000L
        assertFalse(small.refuses(1, profile))
        assertTrue(small.refuses(2, profile))
    }
}
