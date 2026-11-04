package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/**
 * C1 1.7: `kbps` caps the measured on-wire rate. H8 measured encoders that overshoot low targets
 * (≈ 900 kbps floor at 640x360/20 for a 700 target), so the bitrate alone cannot hold the cap.
 */
class PreviewRateGovernorTest {
    @Test
    fun startsBelowTheCapWithTheWireOverheadTakenOff() {
        val governor = PreviewRateGovernor(capKbps = 1_000)

        assertEquals(20, governor.fps)
        assertTrue("${governor.encoderKbps}", governor.encoderKbps in 800..900)
    }

    @Test
    fun admittedWireBytesNeverExceedTheCapPlusOneBurst() {
        val random = Random(11)
        repeat(200) {
            val cap = random.nextInt(50, 1_001)
            val governor = PreviewRateGovernor(capKbps = cap)
            val admitted = mutableListOf<Pair<Long, Int>>()
            var now = 0L
            repeat(400) {
                now += random.nextLong(10, 120)
                val payload = random.nextInt(200, 40_000)
                if (governor.admit(payload, now)) {
                    admitted += now to governor.wireBytes(payload)
                }
            }
            // The burst is one second at the cap, or one oversized frame the bucket went into debt for.
            val burst = maxOf(cap.toLong() * PreviewRateGovernor.BURST_MS / 8, admitted.maxOf { it.second }.toLong())
            for ((start, _) in admitted) {
                for (spanMs in longArrayOf(500, 1_000, 3_000, 10_000)) {
                    val bytes = admitted.filter { it.first in start until start + spanMs }.sumOf { it.second }
                    val allowed = cap.toLong() * spanMs / 8 + burst
                    assertTrue("cap=$cap span=$spanMs bytes=$bytes allowed=$allowed", bytes <= allowed)
                }
            }
        }
    }

    @Test
    fun aKeyFrameBiggerThanTheBucketGoesOnceItIsFullAndItsDebtIsRepaid() {
        // At 200 kbps the bucket is 25 KB; a 40 KB key frame (43.2 KB on the wire) must still go.
        val governor = PreviewRateGovernor(capKbps = 200)
        assertTrue(governor.admit(40_000, 0))

        // 18.2 KB of debt at 25 KB/s: the next 1 KB frame waits ~770 ms.
        assertFalse(governor.admit(1_000, 500))
        assertTrue(governor.admit(1_000, 800))

        // Not full again yet, so a second oversized frame waits for the bucket to refill.
        assertFalse(governor.admit(40_000, 1_500))
        assertTrue(governor.admit(40_000, 3_000))
    }

    @Test
    fun aFrameBiggerThanTheWindowGoesIntoAnEmptyWindowAndHoldsTheLongRunRate() {
        // At 50 kbps the 2 s window is 12.5 KB; a 20 KB key frame is bigger than bucket and window.
        val governor = PreviewRateGovernor(capKbps = 50)
        val admitted = mutableListOf<Long>()
        var now = 0L
        repeat(600) {
            now += 100
            if (governor.admit(20_000, now)) admitted += now
        }

        assertTrue("admitted ${admitted.size}", admitted.size >= 10)
        // From the first frame on (the bucket starts full), the debt holds the rate at the cap.
        val wireBits = (admitted.size - 1) * governor.wireBytes(20_000) * 8L
        val kbps = wireBits / (admitted.last() - admitted.first())
        assertTrue("long-run $kbps kbps", kbps <= 50)
    }

    @Test
    fun measuresTheAdmittedRateOnTheWire() {
        val governor = PreviewRateGovernor(capKbps = 1_000)
        var now = 0L
        repeat(100) {
            now += 50
            assertTrue(governor.admit(2_500, now))
        }

        // 2,500 B every 50 ms is 400 kbps of payload; the wire adds 8 %.
        assertEquals(432, governor.measuredKbps(now))
        assertEquals(0, governor.measuredKbps(now + 10_000))
    }

    @Test
    fun anEncoderStuckAboveTheCapIsHeldBelowItByDroppingFps() {
        val governor = PreviewRateGovernor(capKbps = 700)
        val encoder = OvershootingEncoder(floorKbpsAt20Fps = 900)
        var now = 0L
        var rejected = 0
        repeat(60_000 / 10) {
            now += 10
            val payload = encoder.next(now, governor.encoderKbps, governor.fps)
            if (payload > 0 && !governor.admit(payload, now)) rejected++
            if (now % 500 == 0L) governor.adjust(now)
        }

        assertTrue("fps ${governor.fps}", governor.fps < 20)
        assertTrue("measured ${governor.measuredKbps(now)}", governor.measuredKbps(now) <= 700)
        assertTrue("encoder ${governor.encoderKbps}", governor.encoderKbps >= PreviewRateGovernor.floorKbps(700))
    }

    @Test
    fun aWellBehavedEncoderKeepsFullFpsAndNoDrops() {
        val governor = PreviewRateGovernor(capKbps = 1_000)
        val encoder = OvershootingEncoder(floorKbpsAt20Fps = 0)
        var now = 0L
        var rejected = 0
        repeat(30_000 / 10) {
            now += 10
            val payload = encoder.next(now, governor.encoderKbps, governor.fps)
            if (payload > 0 && !governor.admit(payload, now)) rejected++
            if (now % 500 == 0L) governor.adjust(now)
        }

        assertEquals(20, governor.fps)
        assertEquals(0, rejected)
        assertTrue(governor.measuredKbps(now) in 800..1_000)
    }

    @Test
    fun headroomRestoresFpsBeforeBitrate() {
        val governor = PreviewRateGovernor(capKbps = 1_000)
        var now = 0L
        // Saturate: 1,000 kbps of payload is above the cap once the wire overhead is added.
        repeat(400) {
            now += 50
            governor.admit(6_250, now)
            if (now % 500 == 0L) governor.adjust(now)
        }
        val loweredKbps = governor.encoderKbps
        assertTrue(loweredKbps < 850)

        governor.capKbps = 1_000
        repeat(400) {
            now += 50
            governor.admit(1_000, now)
            if (now % 500 == 0L) governor.adjust(now)
        }
        assertEquals(20, governor.fps)
        assertTrue("${governor.encoderKbps} > $loweredKbps", governor.encoderKbps > loweredKbps)
    }

    @Test
    fun aNewCapRescalesTheLevelsAndResetForgetsThePast() {
        val governor = PreviewRateGovernor(capKbps = 1_000)
        governor.admit(10_000, 0)

        governor.capKbps = 400
        assertTrue("${governor.encoderKbps}", governor.encoderKbps <= 400)
        governor.reset(1_000)
        assertEquals(0, governor.measuredKbps(1_000))
        assertFalse(governor.adjust(1_100))
    }

    /** Emits frames at [fps]; its rate is the larger of the target and a per-frame floor (H8 S10e). */
    private class OvershootingEncoder(private val floorKbpsAt20Fps: Int) {
        private var nextFrameAt = 0L

        fun next(now: Long, targetKbps: Int, fps: Int): Int {
            if (now < nextFrameAt) return 0
            nextFrameAt = now + 1_000 / fps
            val floorBitsPerFrame = floorKbpsAt20Fps * 1_000 / 20
            val targetBitsPerFrame = targetKbps * 1_000 / fps
            return maxOf(floorBitsPerFrame, targetBitsPerFrame) / 8
        }
    }
}
