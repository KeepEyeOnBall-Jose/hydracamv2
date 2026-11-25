package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureSettingsTest {
    private val wide = LensInfo(
        cameraId = "0",
        viewWidth = 1.33,
        zoomRange = 1.0..8.0,
        aeFpsRanges = listOf(15..15, 24..24, 10..30, 15..30, 30..30),
        videoSizes = listOf(3840 to 2160, 1920 to 1080, 1280 to 720),
        videoStabilizationModes = listOf(0, 1),
        oisModes = listOf(0, 1),
        manualSensor = true,
        exposureRangeNs = 10_000L..100_000_000L,
        isoRange = 50..3200,
    )
    private val ultrawide = wide.copy(
        cameraId = "2",
        viewWidth = 2.6,
        zoomRange = 1.0..4.0,
        videoStabilizationModes = listOf(0),
        oisModes = null,
        fixedFocus = true,
    )
    private val tele = wide.copy(cameraId = "3", viewWidth = 0.66)
    private val fleet = listOf(wide, ultrawide, tele)
    private val profile = RecordProfile(masterKbps = 12_000)

    private fun plan(
        target: CaptureTarget = CaptureTarget.DEFAULT,
        lenses: List<LensInfo> = fleet,
        wanted: RecordProfile = profile,
    ) = CapturePlanner.plan(wanted, target, lenses, wideId = "0")

    @Test
    fun defaultCapturePlansWideUnstabilizedFixedShutter() {
        val result = plan() as CapturePlan

        assertEquals("0", result.cameraId)
        assertEquals(CaptureTarget.LENS_WIDE, result.lens)
        assertEquals(1.0, result.zoomRatio, 0.0)
        assertTrue(result.zoomControl)
        assertEquals(CapturePlanner.STABILIZATION_OFF, result.videoStabilizationMode)
        assertEquals(CapturePlanner.STABILIZATION_OFF, result.oisMode)
        assertEquals(30..30, result.fpsRange)
        assertEquals(1920 to 1080, result.masterSize)
        assertEquals(1280 to 720, result.proxySize)
        assertEquals(CapturePlanner.DEFAULT_SHUTTER_NS, result.shutterNs)
        assertEquals(1_000_000_000L / 30, result.frameDurationNs)
        assertFalse(result.fixedFocus)
    }

    @Test
    fun selectsUltrawideAndTeleAndRejectsUnsupportedTargets() {
        val ultra = plan(CaptureTarget(lens = CaptureTarget.LENS_ULTRAWIDE)) as CapturePlan
        assertEquals("2", ultra.cameraId)
        assertTrue(ultra.fixedFocus)
        assertNull(ultra.oisMode)

        val telePlan = plan(CaptureTarget(lens = CaptureTarget.LENS_TELE)) as CapturePlan
        assertEquals("3", telePlan.cameraId)

        assertEquals("capture.lens", (plan(lenses = listOf(ultrawide)) as CaptureUnsupported).field)
        assertEquals(
            "capture.codec",
            (plan(CaptureTarget(codec = CaptureTarget.CODEC_HEVC)) as CaptureUnsupported).field,
        )
        assertEquals(
            "capture.rotationDeg",
            (plan(CaptureTarget(rotationDeg = 90)) as CaptureUnsupported).field,
        )
        assertEquals(
            "capture.zoomRatio",
            (plan(CaptureTarget(zoomRatio = 0.5)) as CaptureUnsupported).field,
        )
        assertEquals(
            "profile.fps",
            (plan(wanted = profile.copy(fps = 60)) as CaptureUnsupported).field,
        )
        assertEquals(
            "profile.masterRes",
            (plan(lenses = listOf(wide.copy(videoSizes = listOf(1280 to 720)))) as CaptureUnsupported).field,
        )
        assertEquals(
            "profile.proxyRes",
            (plan(lenses = listOf(wide.copy(videoSizes = listOf(1920 to 1080)))) as CaptureUnsupported).field,
        )
    }

    @Test
    fun hevcPlansOnlyWhenAHardwareHevcEncoderCoversTheMasterMode() {
        val hevc = CaptureTarget(codec = CaptureTarget.CODEC_HEVC)
        val hd = 1920 to 1080
        val probe: (Pair<Int, Int>, Int) -> Int? = { size, fps -> if (size == hd && fps == 30) 20_000 else null }

        assertEquals(CaptureTarget.CODEC_AVC, (plan() as CapturePlan).codec)
        val planned = CapturePlanner.plan(profile, hevc, fleet, wideId = "0", hevcMaxKbps = probe) as CapturePlan
        assertEquals(CaptureTarget.CODEC_HEVC, planned.codec)
        assertEquals(hd, planned.masterSize)

        val uhd = profile.copy(masterRes = C1ContractConstants.Profile.MASTER_RES_2160P)
        val tooFast = profile.copy(masterKbps = 20_001)
        for (wanted in listOf(uhd, tooFast)) {
            val refused = CapturePlanner.plan(wanted, hevc, fleet, wideId = "0", hevcMaxKbps = probe)
            assertEquals("capture.codec", (refused as CaptureUnsupported).field)
        }
    }

    @Test
    fun zoomStabilizationShutterAndIsoCalculations() {
        assertEquals(1.0, (plan(CaptureTarget(zoomRatio = 1.005)) as CapturePlan).zoomRatio, 0.0)
        assertEquals(2.5, (plan(CaptureTarget(zoomRatio = 2.5)) as CapturePlan).zoomRatio, 0.0)

        val stabOn = plan(CaptureTarget(stabilization = true)) as CapturePlan
        assertEquals(CapturePlanner.STABILIZATION_ON, stabOn.videoStabilizationMode)
        assertEquals(CapturePlanner.STABILIZATION_ON, stabOn.oisMode)

        val offOnly = listOf(wide.copy(videoStabilizationModes = listOf(0), oisModes = null))
        assertEquals(
            "capture.stabilization",
            (plan(CaptureTarget(stabilization = true), offOnly) as CaptureUnsupported).field,
        )

        val defaultPlan = plan() as CapturePlan
        assertEquals(833, defaultPlan.isoFor(autoIso = 100, autoExposureNs = 16_666_667L))
        assertEquals(3200, defaultPlan.isoFor(autoIso = 800, autoExposureNs = 33_333_333L))
        assertNull((plan(lenses = listOf(wide.copy(manualSensor = false))) as CapturePlan).isoFor(100, 16_666_667L))

        assertEquals(1.4, LensInfo.viewWidth(5.6f, floatArrayOf(4.3f, 4.0f))!!, 1e-6)
        assertNull(LensInfo.viewWidth(null, floatArrayOf(4.0f)))
        assertNull(LensInfo.viewWidth(5.6f, floatArrayOf(0f)))
        assertEquals(listOf(30), CapturePlanner.recordableFps(wide.aeFpsRanges, listOf(30, 60)))
    }

    @Test
    fun readbackAndAppliedCapturePreserveObservations() {
        val readback = CaptureReadback(
            aeMode = CaptureReadback.MODE_OFF,
            afMode = CaptureReadback.MODE_OFF,
            awbLock = true,
            zoomRatio = 1.98,
            videoStabilizationMode = 0,
            oisMode = 0,
            frameDurationNs = 33_366_700L,
            exposureTimeNs = 2_000_000L,
            sensitivity = 640,
        )
        val plan = plan(CaptureTarget(zoomRatio = 2.0, rotationDeg = 180)) as CapturePlan
        val applied = appliedCapture(plan, readback, EncoderReadback(MIME_AVC, 1920, 1080, 12_000))!!

        assertEquals("0", applied.cameraId)
        assertEquals(180, applied.rotationDeg)
        assertEquals(30, applied.fps)
        assertEquals(1.98, applied.zoomRatio!!, 0.0)
        assertFalse(applied.stabilization)
        assertTrue(applied.aeLocked && applied.afLocked && applied.awbLocked)
        assertEquals(2_000_000L, applied.exposureTimeNs)
        assertEquals(640, applied.iso)

        assertNull(appliedCapture(plan, CaptureReadback(), EncoderReadback("video/x-vnd.on2.vp8", 1920, 1080, 1)))
        assertEquals(
            CaptureTarget.CODEC_HEVC,
            appliedCapture(plan, CaptureReadback(zoomRatio = 1.0), EncoderReadback(MIME_HEVC, 1920, 1080, 1))!!.codec,
        )
    }
}
