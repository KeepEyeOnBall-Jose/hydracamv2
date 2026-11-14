package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** C1 raw observations must not inherit configured values from legacy `applied` fields. */
class CaptureReadbackTest {
    private val plan = CapturePlan(
        cameraId = "0",
        lens = CaptureTarget.LENS_WIDE,
        zoomRatio = 1.0,
        zoomControl = false,
        videoStabilizationMode = 0,
        oisMode = 0,
        fpsRange = 30..30,
        masterSize = 3840 to 2160,
        proxySize = 1280 to 720,
        shutterNs = 2_000_000,
        frameDurationNs = 33_333_333,
        fixedFocus = false,
    )
    private val encoder = EncoderReadback(MIME_AVC, 3840, 2160, 45_000)

    @Test
    fun missingZoomRetainsOtherObservedValuesAndMarksZoomUnknown() {
        val observed = CaptureReadback(exposureTimeNs = 2_000_000, sensitivity = 907)

        val applied = appliedCapture(plan.copy(zoomControl = true), observed, encoder)

        assertNotNull("A missing zoom observation must not discard other evidence", applied)
        val json = applied!!.toJson()
        assertTrue(json.has("zoomRatio"))
        assertTrue(json.isNull("zoomRatio"))
        assertEquals(2_000_000L, json.getLong("exposureTimeNs"))
        assertEquals(907, json.getInt("iso"))
        assertEquals(30, json.getInt("fps"))
        assertFalse(json.getBoolean("aeLocked"))
        assertFalse(json.getBoolean("afLocked"))
        assertFalse(json.getBoolean("awbLocked"))
        val raw = json.getJSONObject("captureResult")
        assertTrue(raw.isNull("zoomRatio"))
        assertEquals(12, raw.length())
        assertEquals(2_000_000L, raw.getLong("exposureTimeNs"))
        assertEquals(907, raw.getInt("sensitivity"))
    }

    @Test
    fun appliedPreservesRawObservationsAndExplicitlyMarksUnavailableFields() {
        val observed = CaptureReadback(exposureTimeNs = 2_000_000, sensitivity = 907)

        val json = appliedCapture(plan, observed, encoder)!!.toJson()
        val raw = json.getJSONObject("captureResult")

        assertEquals(
            setOf(
                "aeMode", "aeLock", "afMode", "afState", "awbMode", "awbLock", "zoomRatio",
                "videoStabilizationMode", "oisMode", "frameDurationNs", "exposureTimeNs", "sensitivity",
            ),
            raw.keys().asSequence().toSet(),
        )
        listOf(
            "aeMode", "aeLock", "afMode", "afState", "awbMode", "awbLock", "zoomRatio",
            "videoStabilizationMode", "oisMode", "frameDurationNs",
        ).forEach { assertTrue("$it was not reported by the camera", raw.isNull(it)) }
        assertEquals(2_000_000L, raw.getLong("exposureTimeNs"))
        assertEquals(907, raw.getInt("sensitivity"))
        assertEquals(2_000_000L, json.getLong("exposureTimeNs"))
        assertEquals(907, json.getInt("iso"))
        assertEquals(30, json.getInt("fps"))
        assertEquals(1.0, json.getDouble("zoomRatio"), 0.0)
        assertFalse(json.getBoolean("stabilization"))
    }

    @Test
    fun appliedOmitsRawEvidenceUntilACaptureResultArrives() {
        val waiting = appliedCapture(plan, null, encoder)!!.toJson()
        val received = appliedCapture(plan, CaptureReadback(), encoder)!!.toJson()

        assertFalse(waiting.has("captureResult"))
        assertFalse(waiting.has("exposureTimeNs"))
        assertFalse(waiting.has("iso"))
        assertEquals(30, waiting.getInt("fps"))
        assertEquals(1.0, waiting.getDouble("zoomRatio"), 0.0)
        assertFalse(waiting.getBoolean("stabilization"))
        val raw = received.getJSONObject("captureResult")
        assertEquals(12, raw.length())
        raw.keys().forEach { assertTrue(raw.isNull(it)) }
    }
}
