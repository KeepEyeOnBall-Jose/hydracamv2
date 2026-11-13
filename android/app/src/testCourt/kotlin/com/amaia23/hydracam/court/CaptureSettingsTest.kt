package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * C1 1.16 on K1: plan the camera a `record.prepare` asks for, refuse what this phone cannot do
 * (`unsupported`, field first), and report what the camera and encoder actually applied.
 */
class CaptureSettingsTest {
    /** A court S10e / S20 FE, as Camera2 shows it to a third-party app: id 0 wide, id 2 ultrawide. */
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
    private val front = wide.copy(cameraId = "1", viewWidth = 1.2)
    private val tele = wide.copy(cameraId = "3", viewWidth = 0.66)
    private val fleet = listOf(wide, ultrawide)
    private val profile = RecordProfile(masterKbps = 12_000)

    private fun plan(
        target: CaptureTarget = CaptureTarget.DEFAULT,
        lenses: List<LensInfo> = fleet,
        wanted: RecordProfile = profile,
    ) = CapturePlanner.plan(wanted, target, lenses, wideId = "0")

    private fun planned(target: CaptureTarget = CaptureTarget.DEFAULT, lenses: List<LensInfo> = fleet) =
        plan(target, lenses) as CapturePlan

    private fun refused(
        target: CaptureTarget = CaptureTarget.DEFAULT,
        lenses: List<LensInfo> = fleet,
        wanted: RecordProfile = profile,
    ) = plan(target, lenses, wanted) as CaptureUnsupported

    @Test
    fun theDefaultCaptureIsTheWideLensUnstabilizedAtAFixedShutter() {
        val plan = planned()

        assertEquals("0", plan.cameraId)
        assertEquals(CaptureTarget.LENS_WIDE, plan.lens)
        assertEquals(1.0, plan.zoomRatio, 0.0)
        assertTrue(plan.zoomControl)
        assertEquals(CapturePlanner.STABILIZATION_OFF, plan.videoStabilizationMode)
        assertEquals(CapturePlanner.STABILIZATION_OFF, plan.oisMode)
        assertEquals(30..30, plan.fpsRange)
        assertEquals(1920 to 1080, plan.masterSize)
        assertEquals(1280 to 720, plan.proxySize)
        assertEquals(CapturePlanner.DEFAULT_SHUTTER_NS, plan.shutterNs)
        assertEquals(1_000_000_000L / 30, plan.frameDurationNs)
        assertFalse(plan.fixedFocus)
    }

    @Test
    fun theDefaultShutterIsAFiveHundredthOfASecond() {
        assertEquals(2_000_000L, CapturePlanner.DEFAULT_SHUTTER_NS)
    }

    @Test
    fun theUltrawideIsTheWidestOtherBackLens() {
        val plan = planned(CaptureTarget(lens = CaptureTarget.LENS_ULTRAWIDE))

        assertEquals("2", plan.cameraId)
        assertEquals(CaptureTarget.LENS_ULTRAWIDE, plan.lens)
        assertTrue(plan.fixedFocus)
        assertNull(plan.oisMode)
        assertEquals(CapturePlanner.STABILIZATION_OFF, plan.videoStabilizationMode)
    }

    @Test
    fun aLensBarelyWiderThanTheWideIsNotAnUltrawide() {
        val result = refused(CaptureTarget(lens = CaptureTarget.LENS_ULTRAWIDE), listOf(wide, front))

        assertEquals("capture.lens", result.field)
        assertTrue(result.reason, result.reason.startsWith("capture.lens: "))
    }

    @Test
    fun aPhoneWithoutUltrawideRefusesIt() {
        val result = refused(CaptureTarget(lens = CaptureTarget.LENS_ULTRAWIDE), listOf(wide))

        assertEquals("capture.lens", result.field)
    }

    @Test
    fun theTeleIsTheNarrowestOtherBackLens() {
        val plan = planned(CaptureTarget(lens = CaptureTarget.LENS_TELE), listOf(wide, ultrawide, tele))

        assertEquals("3", plan.cameraId)
        assertEquals("capture.lens", refused(CaptureTarget(lens = CaptureTarget.LENS_TELE)).field)
    }

    @Test
    fun noLensRoleWithoutTheWideOrItsFieldOfView() {
        assertEquals("capture.lens", refused(lenses = listOf(ultrawide)).field)
        val blind = listOf(wide.copy(viewWidth = null), ultrawide)
        assertEquals("capture.lens", refused(CaptureTarget(lens = CaptureTarget.LENS_ULTRAWIDE), blind).field)
        assertEquals("0", planned(lenses = blind).cameraId)
    }

    @Test
    fun hevcIsUnsupported() {
        assertEquals("capture.codec", refused(CaptureTarget(codec = CaptureTarget.CODEC_HEVC)).field)
    }

    @Test
    fun aRotatedPictureIsUnsupported() {
        listOf(90, 180, 270).forEach { degrees ->
            assertEquals("capture.rotationDeg", refused(CaptureTarget(rotationDeg = degrees)).field)
        }
    }

    @Test
    fun aZoomInsideTheLensRangeIsApplied() {
        val plan = planned(CaptureTarget(zoomRatio = 2.5))

        assertEquals(2.5, plan.zoomRatio, 0.0)
    }

    @Test
    fun aZoomWithinOnePercentOfOneIsNoZoom() {
        assertEquals(1.0, planned(CaptureTarget(zoomRatio = 1.005)).zoomRatio, 0.0)
        assertEquals(1.0, planned(CaptureTarget(zoomRatio = 1.0), listOf(wide.copy(zoomRange = null))).zoomRatio, 0.0)
        assertFalse(planned(lenses = listOf(wide.copy(zoomRange = null))).zoomControl)
    }

    @Test
    fun aZoomOutsideTheLensRangeOrBelowOneIsUnsupported() {
        assertEquals("capture.zoomRatio", refused(CaptureTarget(zoomRatio = 9.0)).field)
        // Below 1x would quietly switch to another lens on a logical camera; ask for the lens instead.
        assertEquals("capture.zoomRatio", refused(CaptureTarget(zoomRatio = 0.5)).field)
        val noZoom = listOf(wide.copy(zoomRange = null))
        assertEquals("capture.zoomRatio", refused(CaptureTarget(zoomRatio = 2.0), noZoom).field)
    }

    @Test
    fun stabilizationOffNeedsALensThatCanTurnItOff() {
        val alwaysOn = wide.copy(videoStabilizationModes = listOf(1))
        val oisAlwaysOn = wide.copy(oisModes = listOf(1))

        assertEquals("capture.stabilization", refused(lenses = listOf(alwaysOn)).field)
        assertEquals("capture.stabilization", refused(lenses = listOf(oisAlwaysOn)).field)
        val bare = planned(lenses = listOf(wide.copy(videoStabilizationModes = null, oisModes = null)))
        assertNull(bare.videoStabilizationMode)
        assertNull(bare.oisMode)
    }

    @Test
    fun stabilizationOnUsesWhatTheLensOffers() {
        val on = CaptureTarget(stabilization = true)

        val both = planned(on)
        assertEquals(CapturePlanner.STABILIZATION_ON, both.videoStabilizationMode)
        assertEquals(CapturePlanner.STABILIZATION_ON, both.oisMode)
        val oisOnly = planned(on, listOf(wide.copy(videoStabilizationModes = listOf(0))))
        assertEquals(CapturePlanner.STABILIZATION_OFF, oisOnly.videoStabilizationMode)
        assertEquals(CapturePlanner.STABILIZATION_ON, oisOnly.oisMode)
        val offOnly = listOf(wide.copy(videoStabilizationModes = listOf(0), oisModes = null))
        assertEquals("capture.stabilization", refused(on, offOnly).field)
    }

    @Test
    fun sixtyFpsIsUnsupportedWhereNoAutoExposureRangeReachesIt() {
        val result = refused(wanted = profile.copy(fps = 60))

        assertEquals("profile.fps", result.field)
        assertTrue(result.reason, result.reason.startsWith("profile.fps: "))
        assertTrue(result.reason, result.reason.contains("60"))
    }

    @Test
    fun aFixedFpsRangeIsPreferredOverAVariableOne() {
        val variable = wide.copy(aeFpsRanges = listOf(15..60, 30..30, 60..60))

        assertEquals(60..60, (plan(lenses = listOf(variable), wanted = profile.copy(fps = 60)) as CapturePlan).fpsRange)
        assertEquals(30..30, (plan(lenses = listOf(variable)) as CapturePlan).fpsRange)
        val onlyVariable = wide.copy(aeFpsRanges = listOf(15..60, 7..30, 15..30))
        assertEquals(15..30, (plan(lenses = listOf(onlyVariable)) as CapturePlan).fpsRange)
    }

    @Test
    fun aMasterOrProxySizeTheLensCannotEncodeIsUnsupported() {
        val small = wide.copy(videoSizes = listOf(1280 to 720))
        val noProxy = wide.copy(videoSizes = listOf(1920 to 1080))

        assertEquals("profile.masterRes", refused(lenses = listOf(small)).field)
        assertEquals("profile.proxyRes", refused(lenses = listOf(noProxy)).field)
    }

    @Test
    fun theShutterIsClampedToTheSensorAndTheFrame() {
        val slowSensor = wide.copy(exposureRangeNs = 5_000_000L..100_000_000L)
        val fastFrame = wide.copy(aeFpsRanges = listOf(1000..1000), exposureRangeNs = 10_000L..100_000_000L)

        assertEquals(5_000_000L, planned(lenses = listOf(slowSensor)).shutterNs)
        val fast = plan(lenses = listOf(fastFrame), wanted = profile.copy(fps = 1000)) as CapturePlan
        assertEquals(1_000_000L, fast.shutterNs)
    }

    @Test
    fun noShutterWithoutManualSensorControl() {
        assertNull(planned(lenses = listOf(wide.copy(manualSensor = false))).shutterNs)
        assertNull(planned(lenses = listOf(wide.copy(exposureRangeNs = null))).shutterNs)
        assertNull(planned(lenses = listOf(wide.copy(isoRange = null))).shutterNs)
    }

    @Test
    fun theShutterKeepsTheAutoExposureBrightnessThroughIso() {
        val plan = planned()

        // Auto chose 1/60 s at ISO 100; 1/500 s needs 500/60 times the gain.
        assertEquals(833, plan.isoFor(autoIso = 100, autoExposureNs = 16_666_667L))
        assertEquals(3200, plan.isoFor(autoIso = 800, autoExposureNs = 33_333_333L))
        assertEquals(50, plan.isoFor(autoIso = 50, autoExposureNs = 1_000_000L))
        assertNull(planned(lenses = listOf(wide.copy(manualSensor = false))).isoFor(100, 16_666_667L))
    }

    @Test
    fun theViewWidthIsTheSensorWidthOverTheShortestFocalLength() {
        assertEquals(1.4, LensInfo.viewWidth(5.6f, floatArrayOf(4.3f, 4.0f))!!, 1e-6)
        assertNull(LensInfo.viewWidth(null, floatArrayOf(4.0f)))
        assertNull(LensInfo.viewWidth(5.6f, null))
        assertNull(LensInfo.viewWidth(5.6f, floatArrayOf()))
        assertNull(LensInfo.viewWidth(5.6f, floatArrayOf(0f)))
    }

    @Test
    fun capsListOnlyTheFpsSomeAutoExposureRangeEndsAt() {
        assertEquals(listOf(30), CapturePlanner.recordableFps(wide.aeFpsRanges, listOf(30, 60)))
        assertEquals(listOf(30, 60), CapturePlanner.recordableFps(listOf(30..30, 15..60), listOf(30, 60)))
    }

    @Test
    fun theReadbackSaysWhatIsLocked() {
        val locked = CaptureReadback(aeLock = true, afState = CaptureReadback.AF_FOCUSED_LOCKED, awbLock = true)
        val manual = CaptureReadback(
            aeMode = CaptureReadback.MODE_OFF,
            afMode = CaptureReadback.MODE_OFF,
            awbMode = CaptureReadback.MODE_OFF,
        )
        val searching = CaptureReadback(aeLock = false, afState = 1, awbLock = false)

        assertTrue(locked.aeLocked && locked.afLocked(fixedFocus = false) && locked.awbLocked)
        assertTrue(manual.aeLocked && manual.afLocked(fixedFocus = false) && manual.awbLocked)
        assertTrue(CaptureReadback(afState = CaptureReadback.AF_NOT_FOCUSED_LOCKED).afLocked(fixedFocus = false))
        assertFalse(searching.aeLocked || searching.afLocked(fixedFocus = false) || searching.awbLocked)
        assertTrue(searching.afLocked(fixedFocus = true))
        assertFalse(CaptureReadback().aeLocked)
    }

    @Test
    fun appliedReportsWhatTheCameraAndEncoderDid() {
        val plan = planned(CaptureTarget(zoomRatio = 2.0))
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

        val applied = appliedCapture(plan, readback, EncoderReadback(MIME_AVC, 1920, 1088, 12_000))

        assertEquals(
            AppliedCapture(
                cameraId = "0",
                lens = CaptureTarget.LENS_WIDE,
                width = 1920,
                height = 1088,
                fps = 30,
                codec = CaptureTarget.CODEC_AVC,
                masterKbps = 12_000,
                rotationDeg = 0,
                zoomRatio = 1.98,
                stabilization = false,
                aeLocked = true,
                afLocked = true,
                awbLocked = true,
                exposureTimeNs = 2_000_000L,
                iso = 640,
            ),
            applied,
        )
    }

    @Test
    fun appliedFallsBackToThePlanWhereTheResultIsSilent() {
        val plan = planned(lenses = listOf(wide.copy(zoomRange = null)))

        val applied = appliedCapture(plan, CaptureReadback(), EncoderReadback(MIME_AVC, 1920, 1080, 12_000))!!

        assertEquals(30, applied.fps)
        assertEquals(1.0, applied.zoomRatio, 0.0)
        assertFalse(applied.stabilization)
        assertNull(applied.exposureTimeNs)
        assertNull(applied.iso)
    }

    @Test
    fun appliedSaysStabilizationIsOnWhenEitherKindIs() {
        val plan = planned()
        val encoder = EncoderReadback(MIME_AVC, 1920, 1080, 12_000)

        assertTrue(appliedCapture(plan, CaptureReadback(zoomRatio = 1.0, oisMode = 1), encoder)!!.stabilization)
        val stabilized = CaptureReadback(zoomRatio = 1.0, videoStabilizationMode = 1)
        assertTrue(appliedCapture(plan, stabilized, encoder)!!.stabilization)
    }

    @Test
    fun appliedIsUnknownWithoutAZoomReadbackOrAContractCodec() {
        val plan = planned()

        assertNull(appliedCapture(plan, CaptureReadback(), EncoderReadback(MIME_AVC, 1920, 1080, 12_000)))
        val vp8 = EncoderReadback("video/x-vnd.on2.vp8", 1920, 1080, 1)
        assertNull(appliedCapture(plan, CaptureReadback(zoomRatio = 1.0), vp8))
        assertEquals(
            CaptureTarget.CODEC_HEVC,
            appliedCapture(plan, CaptureReadback(zoomRatio = 1.0), EncoderReadback(MIME_HEVC, 1920, 1080, 1))!!.codec,
        )
    }
}
