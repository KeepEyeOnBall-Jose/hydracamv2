package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Retained SM-G935F camera 0 PRIVATE metadata, collected read-only on 2026-11-14:
 * device-s7-camera-capabilities.txt, sizes 301–327, durations 405–457, controls 166–181/617–626.
 * OMX.Exynos.AVC.Encoder declares 3840x2160, 2,073,600 blocks/s and 120,000,000 bits/s.
 * These are capability facts for planning tests, not a successful physical capture.
 */
class S7CapturePlanningTest {
    private val uhd = 3840 to 2160
    private val hd = 1920 to 1080
    private val proxy = 1280 to 720
    private val source = 4032 to 2268
    private val privateSizes = listOf(
        4032 to 3024, source, 3024 to 3024, 3984 to 2988, 3264 to 2448,
        3264 to 1836, 2976 to 2976, 2880 to 2160, 2560 to 1440, 2160 to 2160,
        2048 to 1152, hd, 1440 to 1080, 1088 to 1088, proxy, 1056 to 704,
        1024 to 768, 960 to 720, 800 to 450, 720 to 720, 720 to 480,
        640 to 480, 352 to 288, 320 to 240, 256 to 144, 176 to 144,
    )
    private val lens = LensInfo(
        cameraId = "0",
        viewWidth = 5.64499998 / 4.19999981,
        zoomRange = null,
        aeFpsRanges = listOf(15..15, 24..24, 10..30, 15..30, 30..30),
        videoSizes = privateSizes,
        videoStabilizationModes = listOf(0),
        oisModes = listOf(0, 1),
        manualSensor = true,
        exposureRangeNs = 22_000L..100_000_000L,
        isoRange = 64..1600,
    )
    private val durations = privateSizes.associateWith { 33_331_760L }
    private val encoderKbps = mapOf(uhd to 120_000, hd to 120_000, proxy to 120_000)

    @Test
    fun privateSourceCanQualifyASeparateUhdEncoderAtThirtyFps() {
        val modes = CaptureCapabilities.profiles(
            listOf(lens),
            { _, size -> durations[size] },
            { size, fps -> encoderKbps[size].takeIf { fps == 30 } },
        )
        assertEquals(listOf("2160p", "1080p", "720p"), modes.map { it.masterRes })
        assertTrue(modes.all { it.fps == 30 && it.lens == "wide" && it.codec == "avc" })
        assertEquals(100_000, modes.first().maxMasterKbps)
    }

    @Test
    fun scaledMasterUsesOneCameraTextureAtBothRotationsWithAndWithoutPreview() {
        for (rotation in listOf(0, 180)) {
            val plan = CapturePlanner.plan(
                RecordProfile(masterRes = "2160p", fps = 30),
                CaptureTarget(rotationDeg = rotation),
                listOf(lens),
                minFrameDurationNs = { _, size -> durations[size] },
            ) as CapturePlan
            assertEquals(uhd, plan.masterSize)
            assertEquals(source, plan.masterCameraSize)
            assertTrue(plan.needsMasterFanout)
            assertEquals(source, plan.fanoutSourceSize(hasPreview = false))
            assertEquals(source, plan.fanoutSourceSize(hasPreview = true))
        }
    }

    @Test
    fun exactSizeIsPreferredBeforeLargerPrivateSources() {
        val plan = CapturePlanner.plan(
            RecordProfile(masterRes = "1080p"),
            CaptureTarget.DEFAULT,
            listOf(lens),
            minFrameDurationNs = { _, size -> durations[size] },
        ) as CapturePlan
        assertEquals(hd, plan.masterSize)
        assertEquals(hd, plan.masterCameraSize)
        assertFalse(plan.needsMasterFanout)
    }

    @Test
    fun missingExactSizeChoosesSmallestTimedSameAspectSource() {
        // Filter retained PRIVATE entries to exercise selection; this is not a second phone observation.
        val withoutExact = lens.copy(videoSizes = privateSizes - hd)
        fun selected(knownDurations: Map<Pair<Int, Int>, Long>) = CapturePlanner.plan(
            RecordProfile(masterRes = "1080p"),
            CaptureTarget.DEFAULT,
            listOf(withoutExact),
            minFrameDurationNs = { _, size -> knownDurations[size] },
        ) as CapturePlan
        assertEquals(2048 to 1152, selected(durations).masterCameraSize)
        assertEquals(2560 to 1440, selected(durations - (2048 to 1152)).masterCameraSize)
    }

    @Test
    fun sourceNeedsEnoughPixelsMatchingAspectAndKnownFastTiming() {
        fun refused(candidate: LensInfo = lens, timing: Long?) = CapturePlanner.plan(
            RecordProfile(masterRes = "2160p"),
            CaptureTarget.DEFAULT,
            listOf(candidate),
            minFrameDurationNs = { _, _ -> timing },
        ) is CaptureUnsupported
        assertTrue(refused(lens.copy(videoSizes = privateSizes - source), 33_331_760L))
        // Deliberate negative timing controls, not additional observed S7 modes.
        assertTrue(refused(timing = null))
        assertTrue(refused(timing = 0))
        assertTrue(refused(timing = 50_000_000L))
    }
}
