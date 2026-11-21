package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PreviewBurstTest {
    @Test
    fun edgeRatesReturnSingleElementPatterns() {
        assertEquals(listOf(false), PreviewBurst.pattern(cameraFps = 30, previewFps = 0))
        assertEquals(listOf(true), PreviewBurst.pattern(cameraFps = 20, previewFps = 20))
        assertEquals(listOf(true), PreviewBurst.pattern(cameraFps = 15, previewFps = 20))
    }

    @Test
    fun reducesAndDistributesFramesEvenlyAcrossCommonRates() {
        assertEquals(listOf(true, false, true), PreviewBurst.pattern(cameraFps = 30, previewFps = 20))
        assertEquals(listOf(true, false, false), PreviewBurst.pattern(cameraFps = 60, previewFps = 20))

        for (camera in listOf(24, 25, 30, 50, 60, 120)) {
            for (preview in PreviewRateGovernor.MIN_FPS..PreviewRateGovernor.MAX_FPS) {
                val burst = PreviewBurst.pattern(camera, preview)
                val shown = burst.count { it }
                val expected = minOf(preview, camera)
                assertEquals("$camera->$preview", expected.toLong() * burst.size, shown.toLong() * camera)
                val gaps = burst.indices.filter { burst[it] }.let { idx -> idx.zipWithNext { a, b -> b - a } }
                if (gaps.isNotEmpty()) {
                    assertTrue("$camera->$preview gaps $gaps", gaps.max() - gaps.min() <= 1)
                }
            }
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun cameraFpsMustBePositive() {
        PreviewBurst.pattern(cameraFps = 0, previewFps = 20)
    }
}
