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
import androidx.camera.core.Camera
import androidx.camera.core.CameraControl
import androidx.core.content.ContextCompat
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.plugins.camerax.HydracamCaptureHooks

/**
 * Locks shutter (exposure time), ISO, white balance and focus on the camera the
 * CameraX plugin bound, through Camera2 interop. ISO is metered once from the
 * running auto exposure (shutter priority) and then held for the whole clip.
 * Reports the values the sensor actually used from the latest capture result.
 */
@OptIn(ExperimentalCamera2Interop::class)
class ManualExposureController(
	private val context: Context,
	private val infoFor: (Camera) -> Camera2CameraInfo = { Camera2CameraInfo.from(it.cameraInfo) },
	private val controlFor: (Camera) -> Camera2CameraControl = { Camera2CameraControl.from(it.cameraControl) },
	private val cameraIdFor: (Camera2CameraInfo) -> String = { it.cameraId },
) {
	private class ExposureLease(
		val ownerId: String,
		val cameraId: String,
		val camera: Camera,
		val sourceControl: CameraControl,
		val control: Camera2CameraControl,
		val previousOptions: CaptureRequestOptions,
		var request: Map<String, Any?>,
	) {
		var applying = false
		var applied = false
		var cleanupOnly = false
		var applyFuture: ListenableFuture<Void?>? = null
		var restoreFuture: ListenableFuture<Void?>? = null
		val releaseCallbacks = mutableListOf<(Map<String, Any?>) -> Unit>()
	}

	private var lease: ExposureLease? = null

	fun applyLock(
		ownerId: String,
		cameraName: String,
		exposureTimeNs: Long,
		frameDurationNs: Long,
		onDone: (Map<String, Any?>) -> Unit,
	) {
		val current = lease
		if (current != null && current.ownerId != ownerId) {
			onDone(mapOf("status" to "busy", "cleanupRequired" to false))
			return
		}
		if (current != null && (current.cameraId != cameraName || current.applying || current.cleanupOnly)) {
			onDone(ownedError(current, "The original exposure lease must settle before another apply"))
			return
		}
		val camera = HydracamCaptureHooks.getBoundCamera()
		if (camera == null) {
			onDone(mapOf("status" to "no_camera", "cleanupRequired" to (current != null)))
			return
		}
		try {
			val info = infoFor(camera)
			val cameraId = cameraIdFor(info)
			val control = controlFor(camera)
			if (cameraId != cameraName) {
				onDone(mapOf("status" to "error", "error" to "Camera does not match cameraName",
					"cleanupRequired" to (current != null)))
				return
			}
			if (current != null && (current.camera !== camera ||
				current.sourceControl !== camera.cameraControl || current.control !== control)) {
				onDone(ownedError(current, "The original camera control must be restored before replacement"))
				return
			}
			if (!supportsManualSensor(info)) {
				onDone(mapOf("status" to "unsupported", "cameraId" to cameraId,
					"cleanupRequired" to (current != null)))
				return
			}
			// A same-owner recording relock keeps both the metered request and the
			// original control snapshot. A replacement camera cannot inherit them.
			val request = current?.request?.takeIf {
				it["requestedExposureTimeNs"] == exposureTimeNs
			} ?: meterLockRequest(info, exposureTimeNs, frameDurationNs)
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
			val active = current ?: ExposureLease(ownerId, cameraId, camera,
				camera.cameraControl, control, control.getCaptureRequestOptions(), request)
			active.request = request
			active.applying = true
			active.applied = false
			lease = active // Reserve ownership before native options can mutate.
			val future = control.addCaptureRequestOptions(options.build())
			active.applyFuture = future
			future.addListener({
				val result = try {
					future.get()
					active.applied = true
					request + mapOf("status" to "locked", "cameraId" to cameraId, "cleanupRequired" to true)
				} catch (error: Exception) {
					active.cleanupOnly = true
					ownedError(active, error.cause?.message ?: error.message)
				}
				completeApply(active, result, onDone)
			}, ContextCompat.getMainExecutor(context))
		} catch (error: Exception) {
			val active = lease
			if (active != null && active.ownerId == ownerId) {
				active.cleanupOnly = true
				completeApply(active, ownedError(active, error.cause?.message ?: error.message), onDone)
			} else {
				onDone(mapOf("status" to "error", "error" to (error.cause?.message ?: error.message),
					"cleanupRequired" to false))
			}
		}
	}

	fun release(ownerId: String, cameraName: String, onDone: (Map<String, Any?>) -> Unit) {
		val active = lease
		if (active == null) {
			onDone(mapOf("status" to "released", "cleanupRequired" to false))
			return
		}
		if (active.ownerId != ownerId) {
			onDone(mapOf("status" to "busy", "cleanupRequired" to false))
			return
		}
		if (active.cameraId != cameraName) {
			onDone(ownedError(active, "cameraName does not own the original control"))
			return
		}
		active.cleanupOnly = true
		active.releaseCallbacks.add(onDone)
		if (!active.applying && active.restoreFuture == null) restore(active)
	}

	private fun completeApply(active: ExposureLease, result: Map<String, Any?>, onDone: (Map<String, Any?>) -> Unit) {
		active.applying = false
		active.applyFuture = null
		onDone(result)
		if (active.releaseCallbacks.isNotEmpty() && active.restoreFuture == null) restore(active)
	}

	private fun restore(active: ExposureLease) {
		try {
			// Restore the saved control, even after the plugin binds another camera.
			val future = active.control.setCaptureRequestOptions(active.previousOptions)
			active.restoreFuture = future
			future.addListener({
				val result = try {
					future.get()
					if (lease === active) lease = null
					mapOf("status" to "released", "cameraId" to active.cameraId, "cleanupRequired" to false)
				} catch (error: Exception) {
					ownedError(active, error.cause?.message ?: error.message)
				}
				completeRelease(active, result)
			}, ContextCompat.getMainExecutor(context))
		} catch (error: Exception) {
			completeRelease(active, ownedError(active, error.cause?.message ?: error.message))
		}
	}

	private fun completeRelease(active: ExposureLease, result: Map<String, Any?>) {
		active.restoreFuture = null
		val callbacks = active.releaseCallbacks.toList()
		active.releaseCallbacks.clear()
		callbacks.forEach { it(result) }
	}

	private fun ownedError(active: ExposureLease, message: String?): Map<String, Any?> = mapOf(
		"status" to "error", "cameraId" to active.cameraId,
		"error" to message, "cleanupRequired" to true,
	)

	/** Values the sensor used for the latest completed frame. */
	fun readCaptureSettings(): Map<String, Any?> {
		val camera = HydracamCaptureHooks.getBoundCamera()
			?: return mapOf("status" to "no_camera")
		val info = infoFor(camera)
		val cameraId = cameraIdFor(info)
		val result = HydracamCaptureHooks.getLatestCaptureResult()
			?: return mapOf("status" to "no_capture_result", "cameraId" to cameraId)
		val frameDurationNs = result.get(CaptureResult.SENSOR_FRAME_DURATION)
		return mapOf(
			"status" to "ok",
			"source" to "camera2_capture_result",
			"cameraId" to cameraId,
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
			"manualLockActive" to (lease?.let {
				it.camera === camera && it.sourceControl === camera.cameraControl && it.applied && !it.cleanupOnly
			} == true),
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
