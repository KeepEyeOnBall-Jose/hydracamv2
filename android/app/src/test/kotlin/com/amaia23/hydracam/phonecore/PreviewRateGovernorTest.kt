package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class PreviewRateGovernorTest {
    @Test
    fun startsBelowCapWithWireOverheadTakenOff() {
        val governor = PreviewRateGovernor(capKbps = 1_000)

        assertEquals(PreviewRateGovernor.MAX_FPS, governor.fps)
        assertTrue("${governor.encoderKbps}", governor.encoderKbps in 800..900)
        assertEquals(1_080, governor.wireBytes(1_000))
    }

    @Test
    fun admittedWireBytesNeverExceedCapPlusOneBurst() {
        val random = Random(11)
        repeat(100) {
            val cap = random.nextInt(50, 1_001)
            val governor = PreviewRateGovernor(capKbps = cap)
            val admitted = mutableListOf<Pair<Long, Int>>()
            var now = 0L
            repeat(300) {
                now += random.nextLong(10, 120)
                val payload = random.nextInt(200, 40_000)
                if (governor.admit(payload, now)) {
                    admitted += now to governor.wireBytes(payload)
                }
            }
            val burst = maxOf(cap.toLong() * PreviewRateGovernor.BURST_MS / 8, admitted.maxOf { it.second }.toLong())
            for ((start, _) in admitted) {
                for (spanMs in longArrayOf(500, 1_000, 3_000)) {
                    val bytes = admitted.filter { it.first in start until start + spanMs }.sumOf { it.second }
                    val allowed = cap.toLong() * spanMs / 8 + burst
                    assertTrue("cap=$cap span=$spanMs bytes=$bytes allowed=$allowed", bytes <= allowed)
                }
            }
        }
    }

    @Test
    fun oversizedKeyframeEntersDebtAndRepaysBeforeNextOversizedFrame() {
        val governor = PreviewRateGovernor(capKbps = 200)
        assertTrue(governor.admit(40_000, 0))
        assertFalse(governor.admit(1_000, 500))
        assertTrue(governor.admit(1_000, 800))
        assertFalse(governor.admit(40_000, 1_500))
        assertTrue(governor.admit(40_000, 3_000))
    }

    @Test
    fun measuresRateAndAdjustsBitrateAndFpsWithHeadroomRestoration() {
        val governor = PreviewRateGovernor(capKbps = 700)
        var now = 0L
        repeat(6_000) {
            now += 10
            if (now % 50 == 0L) {
                // Simulate encoder stuck at 900 kbps floor at 20 fps.
                val payload = maxOf(900 * 1_000 / 20, governor.encoderKbps * 1_000 / governor.fps) / 8
                governor.admit(payload, now)
            }
            if (now % 500 == 0L) {
                governor.adjust(now)
            }
        }
        assertTrue("fps=${governor.fps}", governor.fps < PreviewRateGovernor.MAX_FPS)
        assertTrue("measured=${governor.measuredKbps(now)}", governor.measuredKbps(now) <= 700)
        assertTrue(governor.encoderKbps >= PreviewRateGovernor.floorKbps(700))

        governor.capKbps = 1_500
        repeat(400) {
            now += 50
            governor.admit(1_000, now)
            if (now % 500 == 0L) {
                governor.adjust(now)
            }
        }
        assertEquals(PreviewRateGovernor.MAX_FPS, governor.fps)
        assertTrue(governor.encoderKbps > 700)
    }

    @Test
    fun resetClearsWindowAndRejectsNonPositiveCap() {
        val governor = PreviewRateGovernor(capKbps = 1_000)
        governor.admit(10_000, 0)
        governor.capKbps = 400
        assertTrue(governor.encoderKbps <= 400)

        governor.reset(1_000)
        assertEquals(0, governor.measuredKbps(1_000))
        assertFalse(governor.adjust(1_100))

        val error = runCatching { PreviewRateGovernor(capKbps = 0) }.exceptionOrNull()
        assertTrue(error is IllegalArgumentException)
        val setterError = runCatching { governor.capKbps = -1 }.exceptionOrNull()
        assertTrue(setterError is IllegalArgumentException)
    }
}
