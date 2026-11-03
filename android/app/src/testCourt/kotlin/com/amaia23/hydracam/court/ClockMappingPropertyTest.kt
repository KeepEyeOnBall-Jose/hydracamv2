package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.random.Random

/** Property tests for the device → K2 server clock mapping (H10). Each failure names its seed. */
class ClockMappingPropertyTest {
    private val seeds = 0L until 200L
    private val burst = 8

    private fun ping(random: Random, theta: Long, t0: Long): ClockSample {
        val up = random.nextLong(0, 400)
        val work = random.nextLong(0, 20)
        val down = random.nextLong(0, 400)
        val t1 = t0 + up + theta
        val t2 = t1 + work
        return ClockSample(t0, t1, t2, t2 - theta + down)
    }

    @Test
    fun aSampleIsWithinHalfItsRoundTripOfTheTrueOffset() {
        for (seed in seeds) {
            val random = Random(seed)
            val theta = random.nextLong(-3_600_000, 3_600_000)
            val sample = ping(random, theta, random.nextLong(0, 1L shl 40))
            assertTrue("seed $seed", abs(sample.offsetMs - theta) <= sample.rttMs / 2 + 1)
        }
    }

    @Test
    fun aBurstKeepsTheMinimumRoundTripSampleAndMapsBothWays() {
        for (seed in seeds) {
            val random = Random(seed)
            val theta = random.nextLong(-3_600_000, 3_600_000)
            val estimator = ClockOffsetEstimator()
            val samples = (0 until burst).map { ping(random, theta, 1_000L * it) }
            samples.forEach { estimator.add(it) }
            val best = samples.minBy { it.rttMs }

            assertEquals("seed $seed", best.offsetMs, estimator.offsetMs())
            assertTrue("seed $seed", abs(estimator.offsetMs() - theta) <= best.rttMs / 2 + 1)
            val device = random.nextLong(0, 1L shl 40)
            assertEquals("seed $seed", device, estimator.toDeviceMs(estimator.toServerMs(device)))
        }
    }

    @Test
    fun aSampleTakenAcrossABackwardsClockStepIsIgnored() {
        val estimator = ClockOffsetEstimator()
        estimator.add(ClockSample(t0 = 10_000, t1 = 20_000, t2 = 20_001, t3 = 10_050))
        val before = estimator.offsetMs()
        // The device clock stepped back 5 s mid-ping: t3 < t0, so the round trip is negative.
        estimator.add(ClockSample(t0 = 30_000, t1 = 40_000, t2 = 40_001, t3 = 25_000))
        assertEquals(before, estimator.offsetMs())
    }

    @Test
    fun anchoredServerTimeFollowsThePtsEvenWhenTheMappingMoves() {
        for (seed in seeds) {
            val random = Random(seed)
            var skewMs = 0L
            val timebase = SessionTimebase { ptsUs -> 1_700_000_000_000L + ptsUs / 1_000 + skewMs }
            val firstPts = random.nextLong(0, 1L shl 36)
            val firstMs = timebase.serverMs(firstPts)
            timebase.anchor(firstPts)
            var pts = firstPts
            var previous = firstMs
            repeat(50) {
                pts += random.nextLong(1, 7_000_000)
                skewMs = random.nextLong(-2_000, 2_000)
                val ms = timebase.serverMs(pts)
                assertTrue("seed $seed", ms >= previous)
                assertTrue("seed $seed", abs(ms - (firstMs + (pts - firstPts) / 1_000)) <= 1)
                previous = ms
            }
        }
    }
}
