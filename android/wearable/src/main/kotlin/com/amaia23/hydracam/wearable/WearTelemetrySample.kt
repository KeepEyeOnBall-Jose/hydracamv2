package com.amaia23.hydracam.wearable

import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sqrt

data class WearTelemetrySample(
    val sampleId: String,
    val sourceDeviceId: String,
    val localTimestampMs: Long,
    val heartRateBpm: Int,
    val interBeatIntervalMs: Int,
    val accelerometerX: Double,
    val accelerometerY: Double,
    val accelerometerZ: Double,
    val gyroscopeX: Double,
    val gyroscopeY: Double,
    val gyroscopeZ: Double,
    val motionIntensity: Double,
    val mockReading: Boolean,
) {
    fun toHydraCamPayload(): Map<String, Any> {
        return mapOf(
            "recordType" to "wearableSample",
            "sampleId" to sampleId,
            "sourceDeviceId" to sourceDeviceId,
            "localTimestampMs" to localTimestampMs,
            "heartRateBpm" to heartRateBpm,
            "interBeatIntervalMs" to interBeatIntervalMs,
            "accelerometerX" to accelerometerX,
            "accelerometerY" to accelerometerY,
            "accelerometerZ" to accelerometerZ,
            "gyroscopeX" to gyroscopeX,
            "gyroscopeY" to gyroscopeY,
            "gyroscopeZ" to gyroscopeZ,
            "motionIntensity" to motionIntensity,
            "mockReading" to mockReading,
        )
    }

    companion object {
        fun fromHeartRateAndMotion(
            sampleId: String,
            sourceDeviceId: String,
            localTimestampMs: Long,
            heartRateBpm: Int?,
            accelerometerX: Double,
            accelerometerY: Double,
            accelerometerZ: Double,
            gyroscopeX: Double,
            gyroscopeY: Double,
            gyroscopeZ: Double,
            mockReading: Boolean,
        ): WearTelemetrySample {
            val normalizedHeartRate = heartRateBpm
                ?.coerceIn(MIN_HEART_RATE_BPM, MAX_HEART_RATE_BPM)
                ?: 0
            return WearTelemetrySample(
                sampleId = sampleId,
                sourceDeviceId = sourceDeviceId,
                localTimestampMs = localTimestampMs,
                heartRateBpm = normalizedHeartRate,
                interBeatIntervalMs = if (normalizedHeartRate > 0) {
                    60_000 / normalizedHeartRate
                } else {
                    0
                },
                accelerometerX = accelerometerX,
                accelerometerY = accelerometerY,
                accelerometerZ = accelerometerZ,
                gyroscopeX = gyroscopeX,
                gyroscopeY = gyroscopeY,
                gyroscopeZ = gyroscopeZ,
                motionIntensity = WearMotionMath.intensity(
                    accelerometerX = accelerometerX,
                    accelerometerY = accelerometerY,
                    accelerometerZ = accelerometerZ,
                    gyroscopeX = gyroscopeX,
                    gyroscopeY = gyroscopeY,
                    gyroscopeZ = gyroscopeZ,
                ),
                mockReading = mockReading,
            )
        }

        private const val MIN_HEART_RATE_BPM = 25
        private const val MAX_HEART_RATE_BPM = 240
    }
}

object WearMotionMath {
    fun intensity(
        accelerometerX: Double,
        accelerometerY: Double,
        accelerometerZ: Double,
        gyroscopeX: Double,
        gyroscopeY: Double,
        gyroscopeZ: Double,
    ): Double {
        val accelerationMagnitude = sqrt(
            accelerometerX * accelerometerX +
                accelerometerY * accelerometerY +
                accelerometerZ * accelerometerZ,
        )
        val rotationMagnitude = sqrt(
            gyroscopeX * gyroscopeX +
                gyroscopeY * gyroscopeY +
                gyroscopeZ * gyroscopeZ,
        )
        val accelerationLoad = abs(accelerationMagnitude - EARTH_GRAVITY_MPS2) / 2.5
        val rotationLoad = rotationMagnitude / 8.0
        return min(1.0, accelerationLoad + rotationLoad)
    }

    private const val EARTH_GRAVITY_MPS2 = 9.81
}

data class WearMarkerEvent(
    val markerId: String,
    val sourceDeviceId: String,
    val localTimestampMs: Long,
    val markerType: String = "player_marker",
    val label: String = "Player highlight marker",
) {
    fun toHydraCamPayload(): Map<String, Any> {
        return mapOf(
            "recordType" to "wearableMarker",
            "markerId" to markerId,
            "sourceDeviceId" to sourceDeviceId,
            "localTimestampMs" to localTimestampMs,
            "markerType" to markerType,
            "label" to label,
        )
    }
}

data class WearFeedbackAck(
    val feedbackId: String,
    val sourceDeviceId: String,
    val localTimestampMs: Long,
    val channel: String,
    val trigger: String,
    val message: String,
) {
    fun toHydraCamPayload(): Map<String, Any> {
        return mapOf(
            "recordType" to "feedbackEvent",
            "feedbackId" to feedbackId,
            "sourceDeviceId" to sourceDeviceId,
            "localTimestampMs" to localTimestampMs,
            "channel" to channel,
            "trigger" to trigger,
            "message" to message,
        )
    }
}

class MockWearTelemetrySource(
    private val sourceDeviceId: String = "galaxy-watch4-sim",
) {
    private var sampleIndex = 0

    fun nextSample(nowMs: Long): WearTelemetrySample {
        sampleIndex += 1
        val heartRate = 142 + (sampleIndex % 9)
        return WearTelemetrySample.fromHeartRateAndMotion(
            sampleId = "watch-sim-$sampleIndex",
            sourceDeviceId = sourceDeviceId,
            localTimestampMs = nowMs,
            heartRateBpm = heartRate,
            accelerometerX = 0.34,
            accelerometerY = 0.46,
            accelerometerZ = 9.61,
            gyroscopeX = 0.12,
            gyroscopeY = 0.08,
            gyroscopeZ = 0.18,
            mockReading = true,
        )
    }
}

data class WearSyncCalibrationResult(
    val masterAnchorMs: Long,
    val wearableAnchorMs: Long,
    val offsetMs: Long,
    val absoluteErrorMs: Long,
    val confidence: String,
) {
    val withinFrameTarget: Boolean
        get() = absoluteErrorMs <= FRAME_ALIGNMENT_TARGET_MS

    fun toHydraCamPayload(): Map<String, Any> {
        return mapOf(
            "recordType" to "wearableSyncCalibration",
            "masterAnchorMs" to masterAnchorMs,
            "wearableAnchorMs" to wearableAnchorMs,
            "offsetMs" to offsetMs,
            "absoluteErrorMs" to absoluteErrorMs,
            "confidence" to confidence,
            "withinFrameTarget" to withinFrameTarget,
            "targetMs" to FRAME_ALIGNMENT_TARGET_MS,
        )
    }

    companion object {
        const val FRAME_ALIGNMENT_TARGET_MS = 50L
    }
}

object WearSyncCalibration {
    fun fromClapOrFlashAnchor(
        masterAnchorMs: Long,
        wearableAnchorMs: Long,
    ): WearSyncCalibrationResult {
        val offsetMs = masterAnchorMs - wearableAnchorMs
        val absoluteErrorMs = abs(offsetMs)
        val confidence = when {
            absoluteErrorMs <= WearSyncCalibrationResult.FRAME_ALIGNMENT_TARGET_MS -> "green"
            absoluteErrorMs <= WearSyncCalibrationResult.FRAME_ALIGNMENT_TARGET_MS * 2 -> "yellow"
            else -> "red"
        }
        return WearSyncCalibrationResult(
            masterAnchorMs = masterAnchorMs,
            wearableAnchorMs = wearableAnchorMs,
            offsetMs = offsetMs,
            absoluteErrorMs = absoluteErrorMs,
            confidence = confidence,
        )
    }
}
