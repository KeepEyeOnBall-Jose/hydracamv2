package com.amaia23.hydracam

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import androidx.annotation.OptIn
import androidx.camera.camera2.interop.Camera2CameraControl
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.CaptureRequestOptions
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.core.content.ContextCompat
import io.flutter.plugins.camerax.HydracamCaptureHooks

/**
 * Locks shutter (exposure time), ISO, white balance and focus on the camera the
 * CameraX plugin bound, through Camera2 interop. ISO is metered once from the
 * running auto exposure (shutter priority) and then held for the whole clip.
 * Reports the values the sensor actually used from the latest capture result.
 */
@OptIn(ExperimentalCamera2Interop::class)
class ManualExposureController(private val context: Context) {
	private var lockedCameraId: String? = null
	private var optionsBeforeLock: CaptureRequestOptions? = null
	private var lockedRequest: Map<String, Any?>? = null

	fun applyLock(
		exposureTimeNs: Long,
		frameDurationNs: Long,
		onDone: (Map<String, Any?>) -> Unit,
	) {
		val camera = HydracamCaptureHooks.getBoundCamera()
		if (camera == null) {
			onDone(mapOf("status" to "no_camera"))
			return
		}
		val info = Camera2CameraInfo.from(camera.cameraInfo)
		val cameraId = info.cameraId
		if (!supportsManualSensor(info)) {
			onDone(mapOf("status" to "unsupported", "cameraId" to cameraId))
			return
		}
		// Re-applying after the recording rebinds the session keeps the metered ISO.
		val request = lockedRequest?.takeIf {
			lockedCameraId == cameraId && it["requestedExposureTimeNs"] == exposureTimeNs
		} ?: meterLockRequest(info, exposureTimeNs, frameDurationNs)
		val control = Camera2CameraControl.from(camera.cameraControl)
		if (lockedCameraId != cameraId) {
			optionsBeforeLock = control.getCaptureRequestOptions()
		}
		val options = CaptureRequestOptions.Builder()
			.setCaptureRequestOption(
				CaptureRequest.CONTROL_AE_MODE,
				CameraMetadata.CONTROL_AE_MODE_OFF,
			)
			.setCaptureRequestOption(
				CaptureRequest.SENSOR_EXPOSURE_TIME,
				request["exposureTimeNs"] as Long,
			)
			.setCaptureRequestOption(
				CaptureRequest.SENSOR_SENSITIVITY,
				request["iso"] as Int,
			)
			.setCaptureRequestOption(
				CaptureRequest.SENSOR_FRAME_DURATION,
				request["frameDurationNs"] as Long,
			)
			.setCaptureRequestOption(CaptureRequest.CONTROL_AWB_LOCK, true)
		val focusDistance = request["focusDistanceDiopters"] as Float?
		if (focusDistance != null) {
			options
				.setCaptureRequestOption(
					CaptureRequest.CONTROL_AF_MODE,
					CameraMetadata.CONTROL_AF_MODE_OFF,
				)
				.setCaptureRequestOption(CaptureRequest.LENS_FOCUS_DISTANCE, focusDistance)
		}
		val future = control.addCaptureRequestOptions(options.build())
		future.addListener(
			{
				try {
					future.get()
					lockedCameraId = cameraId
					lockedRequest = request
					onDone(request + mapOf("status" to "locked", "cameraId" to cameraId))
				} catch (error: Exception) {
					onDone(
						mapOf(
							"status" to "error",
							"cameraId" to cameraId,
							"error" to (error.cause?.message ?: error.message),
						),
					)
				}
			},
			ContextCompat.getMainExecutor(context),
		)
	}

	fun release(onDone: (Map<String, Any?>) -> Unit) {
		val camera = HydracamCaptureHooks.getBoundCamera()
		val cameraId = camera?.let { Camera2CameraInfo.from(it.cameraInfo).cameraId }
		val previous = optionsBeforeLock
		val wasLockedCameraId = lockedCameraId
		lockedCameraId = null
		lockedRequest = null
		optionsBeforeLock = null
		if (camera == null || wasLockedCameraId == null || cameraId != wasLockedCameraId) {
			onDone(mapOf("status" to "not_locked"))
			return
		}
		val future = Camera2CameraControl.from(camera.cameraControl)
			.setCaptureRequestOptions(previous ?: CaptureRequestOptions.Builder().build())
		future.addListener(
			{
				try {
					future.get()
					onDone(mapOf("status" to "released", "cameraId" to cameraId))
				} catch (error: Exception) {
					onDone(
						mapOf(
							"status" to "error",
							"cameraId" to cameraId,
							"error" to (error.cause?.message ?: error.message),
						),
					)
				}
			},
			ContextCompat.getMainExecutor(context),
		)
	}

	/** Values the sensor used for the latest completed frame. */
	fun readCaptureSettings(): Map<String, Any?> {
		val camera = HydracamCaptureHooks.getBoundCamera()
			?: return mapOf("status" to "no_camera")
		val info = Camera2CameraInfo.from(camera.cameraInfo)
		val result = HydracamCaptureHooks.getLatestCaptureResult()
			?: return mapOf("status" to "no_capture_result", "cameraId" to info.cameraId)
		val frameDurationNs = result.get(CaptureResult.SENSOR_FRAME_DURATION)
		return mapOf(
			"status" to "ok",
			"source" to "camera2_capture_result",
			"cameraId" to info.cameraId,
			"hardwareLevel" to hardwareLevelName(
				info.getCameraCharacteristic(
					CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL,
				),
			),
			"exposureTimeNs" to result.get(CaptureResult.SENSOR_EXPOSURE_TIME),
			"iso" to result.get(CaptureResult.SENSOR_SENSITIVITY),
			"frameDurationNs" to frameDurationNs,
			"fps" to frameDurationNs?.takeIf { it > 0 }?.let { 1_000_000_000.0 / it },
			"rollingShutterSkewNs" to result.get(CaptureResult.SENSOR_ROLLING_SHUTTER_SKEW),
			"aeMode" to result.get(CaptureResult.CONTROL_AE_MODE),
			"awbLocked" to result.get(CaptureResult.CONTROL_AWB_LOCK),
			"afMode" to result.get(CaptureResult.CONTROL_AF_MODE),
			"focusDistanceDiopters" to result.get(CaptureResult.LENS_FOCUS_DISTANCE),
			"sensorTimestampNs" to result.get(CaptureResult.SENSOR_TIMESTAMP),
			"manualLockActive" to (lockedCameraId == info.cameraId),
		)
	}

	/**
	 * Shutter priority: keep the requested exposure time and pick the ISO that
	 * gives the same brightness auto exposure is currently producing.
	 */
	private fun meterLockRequest(
		info: Camera2CameraInfo,
		exposureTimeNs: Long,
		frameDurationNs: Long,
	): Map<String, Any?> {
		val exposureRange = info.getCameraCharacteristic(
			CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE,
		)
		val isoRange = info.getCameraCharacteristic(
			CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE,
		)
		val maxFrameDurationNs = info.getCameraCharacteristic(
			CameraCharacteristics.SENSOR_INFO_MAX_FRAME_DURATION,
		)
		val frameDuration = maxFrameDurationNs?.let { minOf(frameDurationNs, it) } ?: frameDurationNs
		var exposure = minOf(exposureTimeNs, frameDuration)
		if (exposureRange != null) {
			exposure = exposure.coerceIn(exposureRange.lower, exposureRange.upper)
		}

		val metered = HydracamCaptureHooks.getLatestCaptureResult()
		val autoExposureNs = metered?.get(CaptureResult.SENSOR_EXPOSURE_TIME)
		val autoIso = metered?.get(CaptureResult.SENSOR_SENSITIVITY)
		val isoMin = isoRange?.lower ?: 100
		val isoMax = isoRange?.upper ?: 800
		val wantedIso = if (autoExposureNs != null && autoIso != null && autoExposureNs > 0) {
			(autoIso.toDouble() * autoExposureNs.toDouble() / exposure.toDouble()).toInt()
		} else {
			isoMax
		}
		val iso = wantedIso.coerceIn(isoMin, isoMax)
		val minFocusDistance = info.getCameraCharacteristic(
			CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE,
		)
		val focusDistance = if (minFocusDistance != null && minFocusDistance > 0f) {
			metered?.get(CaptureResult.LENS_FOCUS_DISTANCE)
		} else {
			null
		}

		return mapOf(
			"requestedExposureTimeNs" to exposureTimeNs,
			"exposureTimeNs" to exposure,
			"iso" to iso,
			"frameDurationNs" to frameDuration,
			"focusDistanceDiopters" to focusDistance,
			"fixedFocusLens" to (minFocusDistance == null || minFocusDistance == 0f),
			"meteredAutoExposureTimeNs" to autoExposureNs,
			"meteredAutoIso" to autoIso,
			"wantedIso" to wantedIso,
			"isoMin" to isoMin,
			"isoMax" to isoMax,
			"exposureClamped" to (exposure != exposureTimeNs),
			"underexposed" to (wantedIso > isoMax),
			"meteringSource" to if (autoIso != null) "auto_exposure" else "none_max_iso",
		)
	}

	private fun supportsManualSensor(info: Camera2CameraInfo): Boolean {
		val capabilities = info.getCameraCharacteristic(
			CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES,
		) ?: return false
		return capabilities.contains(
			CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR,
		)
	}

	private fun hardwareLevelName(level: Int?): String? = when (level) {
		CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY -> "legacy"
		CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_LIMITED -> "limited"
		CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_FULL -> "full"
		CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_3 -> "level_3"
		CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_EXTERNAL -> "external"
		null -> null
		else -> level.toString()
	}
}
