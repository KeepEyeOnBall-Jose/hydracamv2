package com.amaia23.hydracam.wearable

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WearTelemetrySampleTest {
    @Test
    fun mockSourceBuildsHydraCamCompatibleTelemetryPayloads() {
        val source = MockWearTelemetrySource("galaxy-watch4-sim")

        val first = source.nextSample(1_000L)
        val second = source.nextSample(2_000L)
        val payload = first.toHydraCamPayload()

        assertEquals("wearableSample", payload["recordType"])
        assertEquals("galaxy-watch4-sim", payload["sourceDeviceId"])
        assertEquals(1_000L, payload["localTimestampMs"])
        assertEquals(true, payload["mockReading"])
        assertTrue(first.heartRateBpm in 120..190)
        assertTrue(first.motionIntensity > 0.0)
        assertTrue(second.heartRateBpm >= first.heartRateBpm)
    }

    @Test
    fun healthServicesSampleBuilderHandlesMissingAndBoundedHeartRate() {
        val missingHeartRate = WearTelemetrySample.fromHeartRateAndMotion(
            sampleId = "sample-1",
            sourceDeviceId = "galaxy-watch4",
            localTimestampMs = 5_000L,
            heartRateBpm = null,
            accelerometerX = 0.0,
            accelerometerY = 0.0,
            accelerometerZ = 9.81,
            gyroscopeX = 0.0,
            gyroscopeY = 0.0,
            gyroscopeZ = 0.0,
            mockReading = false,
        )
        val clampedHeartRate = WearTelemetrySample.fromHeartRateAndMotion(
            sampleId = "sample-2",
            sourceDeviceId = "galaxy-watch4",
            localTimestampMs = 5_001L,
            heartRateBpm = 260,
            accelerometerX = 0.0,
            accelerometerY = 0.0,
            accelerometerZ = 9.81,
            gyroscopeX = 0.0,
            gyroscopeY = 0.0,
            gyroscopeZ = 0.0,
            mockReading = false,
        )

        assertEquals(0, missingHeartRate.heartRateBpm)
        assertEquals(0, missingHeartRate.interBeatIntervalMs)
        assertFalse(missingHeartRate.mockReading)
        assertEquals(240, clampedHeartRate.heartRateBpm)
        assertEquals(250, clampedHeartRate.interBeatIntervalMs)
    }

    @Test
    fun motionIntensityIncreasesWithAccelerationAndRotation() {
        val resting = WearMotionMath.intensity(
            accelerometerX = 0.0,
            accelerometerY = 0.0,
            accelerometerZ = 9.81,
            gyroscopeX = 0.0,
            gyroscopeY = 0.0,
            gyroscopeZ = 0.0,
        )
        val active = WearMotionMath.intensity(
            accelerometerX = 3.0,
            accelerometerY = 4.0,
            accelerometerZ = 11.0,
            gyroscopeX = 2.0,
            gyroscopeY = 2.0,
            gyroscopeZ = 2.0,
        )

        assertEquals(0.0, resting, 0.0001)
        assertTrue(active > resting)
        assertTrue(active <= 1.0)
    }

    @Test
    fun markerAndFeedbackPayloadsCarryReplayRecordTypes() {
        val marker = WearMarkerEvent(
            markerId = "marker-1",
            sourceDeviceId = "galaxy-watch4-sim",
            localTimestampMs = 10_000L,
        )
        val feedback = WearFeedbackAck(
            feedbackId = "feedback-1",
            sourceDeviceId = "galaxy-watch4-sim",
            localTimestampMs = 10_010L,
            channel = "watchHaptic",
            trigger = "marker_saved",
            message = "Marker saved",
        )

        assertEquals("wearableMarker", marker.toHydraCamPayload()["recordType"])
        assertEquals("player_marker", marker.toHydraCamPayload()["markerType"])
        assertEquals("feedbackEvent", feedback.toHydraCamPayload()["recordType"])
        assertEquals("watchHaptic", feedback.toHydraCamPayload()["channel"])
    }

    @Test
    fun clapFlashCalibrationClassifiesFrameLevelAlignment() {
        val green = WearSyncCalibration.fromClapOrFlashAnchor(
            masterAnchorMs = 1_000L,
            wearableAnchorMs = 970L,
        )
        val red = WearSyncCalibration.fromClapOrFlashAnchor(
            masterAnchorMs = 1_000L,
            wearableAnchorMs = 870L,
        )

        assertTrue(green.withinFrameTarget)
        assertEquals(30L, green.absoluteErrorMs)
        assertEquals("green", green.confidence)
        assertFalse(red.withinFrameTarget)
        assertEquals("red", red.confidence)
    }
}
