package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Test

class PreviewBurstTest {
    @Test
    fun offIsOneRequestWithoutThePreview() {
        assertEquals(listOf(false), PreviewBurst.pattern(cameraFps = 30, previewFps = 0))
    }

    @Test
    fun atOrAboveTheCameraRateEveryFrameFeedsThePreview() {
        assertEquals(listOf(true), PreviewBurst.pattern(cameraFps = 20, previewFps = 20))
        assertEquals(listOf(true), PreviewBurst.pattern(cameraFps = 15, previewFps = 20))
    }

    @Test
    fun thirtyToTwentyIsTwoOfEveryThree() {
        assertEquals(listOf(true, false, true), PreviewBurst.pattern(cameraFps = 30, previewFps = 20))
    }

    @Test
    fun sixtyToTwentyIsOneOfEveryThree() {
        assertEquals(listOf(true, false, false), PreviewBurst.pattern(cameraFps = 60, previewFps = 20))
    }

    @Test
    fun everyPairSendsExactlyTheAskedRateSpreadEvenly() {
        for (camera in listOf(24, 25, 30, 50, 60, 120)) {
            for (preview in PreviewRateGovernor.MIN_FPS..PreviewRateGovernor.MAX_FPS) {
                val burst = PreviewBurst.pattern(camera, preview)
                val shown = burst.count { it }
                val expected = minOf(preview, camera)
                assertEquals("$camera→$preview", expected.toLong() * burst.size, shown.toLong() * camera)
                // Bresenham: gaps between preview frames differ by at most one camera frame.
                val gaps = burst.indices.filter { burst[it] }.let { idx -> idx.zipWithNext { a, b -> b - a } }
                if (gaps.isNotEmpty()) {
                    assertEquals("$camera→$preview gaps $gaps", true, gaps.max() - gaps.min() <= 1)
                }
            }
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun cameraFpsMustBePositive() {
        PreviewBurst.pattern(cameraFps = 0, previewFps = 20)
    }
}
