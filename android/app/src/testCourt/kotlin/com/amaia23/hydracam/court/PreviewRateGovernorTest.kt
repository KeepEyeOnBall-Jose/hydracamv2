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
    fun admittedWireBytesNeverExceedTheCapPlusOneSecondOfBurst() {
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
            for ((start, _) in admitted) {
                for (spanMs in longArrayOf(500, 1_000, 3_000)) {
                    val bytes = admitted.filter { it.first in start until start + spanMs }.sumOf { it.second }
                    val allowed = cap.toLong() * (spanMs + PreviewRateGovernor.BURST_MS) / 8
                    assertTrue("cap=$cap span=$spanMs bytes=$bytes allowed=$allowed", bytes <= allowed)
                }
            }
        }
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
