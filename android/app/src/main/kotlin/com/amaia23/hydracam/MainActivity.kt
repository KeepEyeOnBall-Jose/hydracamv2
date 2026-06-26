package com.amaia23.hydracam

import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.MediaMetadataRetriever
import android.os.Build
import com.amaia23.hydracam.fixedcamera.FixedCameraCamera2HlsRecorder
import com.amaia23.hydracam.fixedcamera.FixedCameraLocalHlsRecorder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class MainActivity: FlutterActivity() {
	private val launchConfigChannelName = "hydracamv2/launch_config"
	private val cameraMetadataChannelName = "hydracamv2/camera_metadata"
	private val videoMetadataChannelName = "hydracamv2/video_metadata"
	private val fixedCameraHlsChannelName = "hydracamv2/fixed_camera_hls"
	private val wearableReplayChannelName = "hydracamv2/wearable_replay"
	private val fixedCameraLocalHlsRecorder: FixedCameraLocalHlsRecorder by lazy {
		FixedCameraLocalHlsRecorder(getFixedCameraHlsOutputDirectory())
	}
	private val fixedCameraCamera2HlsRecorder: FixedCameraCamera2HlsRecorder by lazy {
		FixedCameraCamera2HlsRecorder(this, getFixedCameraHlsOutputDirectory())
	}
	private val fixedCameraRecordingModes = mutableMapOf<String, String>()
	private val wearablePovCaptures = mutableMapOf<String, Map<String, Any?>>()
	// Null on default builds (stub factory) -> mock POV path. Non-null only on
	// gated `-PwithMetaDat=true` builds, and even then drives capture only when
	// isAvailable() reports a live Meta DAT stream.
	private val realPovBridge: WearablePovBridge? by lazy {
		RealMetaPovBridgeFactory.createOrNull(this)
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, launchConfigChannelName)
			.setMethodCallHandler { call, result ->
				if (call.method == "getLaunchConfig") {
					result.success(buildLaunchConfig())
				} else {
					result.notImplemented()
				}
			}
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, cameraMetadataChannelName)
			.setMethodCallHandler { call, result ->
				if (call.method == "getCameraMetadata") {
					val cameraId = call.argument<String>("cameraId")
					if (cameraId == null) {
						result.error("missing_camera_id", "cameraId is required", null)
					} else {
						result.success(buildCameraMetadata(cameraId))
					}
				} else {
					result.notImplemented()
				}
			}
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, videoMetadataChannelName)
			.setMethodCallHandler { call, result ->
				if (call.method == "inspectVideo") {
					val path = call.argument<String>("path")
					if (path == null) {
						result.error("missing_path", "path is required", null)
					} else {
						result.success(buildVideoMetadata(path))
					}
				} else {
					result.notImplemented()
				}
			}
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fixedCameraHlsChannelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"getCapabilities" -> result.success(buildFixedCameraHlsCapabilities())
					"startRecording" -> startFixedCameraHlsRecording(call, result)
					"stopRecording" -> stopFixedCameraHlsRecording(call, result)
					else -> result.notImplemented()
				}
			}
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wearableReplayChannelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"getCapabilities" -> result.success(buildWearableReplayCapabilities())
					"pollWatchTelemetry" -> result.success(buildMockWatchTelemetry(call))
					"startMetaPovCapture" -> startMockMetaPovCapture(call, result)
					"stopMetaPovCapture" -> stopMockMetaPovCapture(call, result)
					"sendFeedback" -> result.success(true)
					else -> result.notImplemented()
				}
			}
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
	}

	private fun buildLaunchConfig(): Map<String, Any?> {
		val launchIntent = intent ?: return emptyMap()
		val extras = launchIntent.extras
		val payload = mutableMapOf<String, Any?>()

		if (extras != null) {
			extras.getString("role")?.let { payload["role"] = it }
			extras.getString("preferredMasterIp")?.let {
				payload["preferredMasterIp"] = it
			}
			extras.getString("automationTargetId")?.let {
				payload["automationTargetId"] = it
			}
			if (extras.containsKey("forceSlaveMode")) {
				payload["forceSlaveMode"] = extras.getBoolean("forceSlaveMode")
			}
		}

		if (payload.isEmpty() && isManualLauncherIntent(launchIntent)) {
			payload["manualLaunch"] = true
		}

		return payload
	}

	private fun isManualLauncherIntent(intent: Intent): Boolean {
		return intent.action == Intent.ACTION_MAIN &&
			intent.hasCategory(Intent.CATEGORY_LAUNCHER)
	}

	private fun buildCameraMetadata(cameraId: String): Map<String, Any?> {
		val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
		val characteristics = try {
			cameraManager.getCameraCharacteristics(cameraId)
		} catch (e: Exception) {
			return mapOf(
				"cameraId" to cameraId,
				"focalLengths" to emptyList<Double>(),
				"maxDigitalZoom" to null
			)
		}
		val focalLengths = characteristics
			.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
			?.map { it.toDouble() }
			?: emptyList()
		val maxDigitalZoom = characteristics
			.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM)
			?.toDouble()

		return mapOf(
			"cameraId" to cameraId,
			"focalLengths" to focalLengths,
			"maxDigitalZoom" to maxDigitalZoom
		)
	}

	private fun buildVideoMetadata(path: String): Map<String, Any?> {
		val retriever = MediaMetadataRetriever()
		return try {
			retriever.setDataSource(path)
			mapOf(
				"width" to retriever
					.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
					?.toIntOrNull(),
				"height" to retriever
					.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
					?.toIntOrNull(),
				"durationMs" to retriever
					.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
					?.toIntOrNull(),
				"framesPerSecond" to retriever
					.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)
					?.toDoubleOrNull()
			)
		} catch (e: Exception) {
			emptyMap()
		} finally {
			retriever.release()
		}
	}

	private fun buildFixedCameraHlsCapabilities(): Map<String, Any?> {
		val outputDirectory = getFixedCameraHlsOutputDirectory()
		val cameraIds = fixedCameraCamera2HlsRecorder.cameraIds()
		val cameraRecorderAvailable = cameraIds.isNotEmpty()
		val cameraModes = if (cameraRecorderAvailable) {
			fixedCameraCamera2HlsRecorder.cameraModes()
		} else {
			emptyList()
		}
		return mapOf(
			"platform" to "android",
			"channelAvailable" to true,
			"nativeRecorderImplemented" to true,
			"cameraRecorderImplemented" to cameraRecorderAvailable,
			"recorderMode" to "synthetic_local",
			"supportedRecorderModes" to listOf("synthetic_local", "camera2_hls"),
			"cameraIds" to cameraIds,
			"cameraModes" to cameraModes,
			"requiresCameraHardware" to false,
			"supportsHlsUpload" to true,
			"androidSdk" to Build.VERSION.SDK_INT,
			"supportedMimeTypes" to listOf(
				"application/vnd.apple.mpegurl",
				"video/mp4",
				"video/iso.segment"
			),
			"outputDirectoryPath" to outputDirectory.absolutePath,
			"reason" to "Synthetic local HLS is the default; pass cameraId to use Camera2 HLS recording."
		)
	}

	private fun buildWearableReplayCapabilities(): Map<String, Any?> {
		val realStreamAvailable = realPovBridge?.isAvailable() == true
		return mapOf(
			"platform" to "android",
			"channelAvailable" to true,
			"metaDatAvailable" to realStreamAvailable,
			"metaDatBridgeCompiled" to BuildConfig.META_DAT_BRIDGE,
			"metaMockAvailable" to true,
			"watchCompanionAvailable" to false,
			"watchMockAvailable" to true,
			"supportsWatchHaptics" to true,
			"supportsGlassesAudio" to true,
			"supportsRollingPovFallback" to true,
			"requiresPhysicalMetaHardware" to true,
			"requiresPhysicalWatchHardware" to true,
			"reason" to "Mock Meta DAT and Galaxy Watch telemetry are available for emulator proof; physical Ray-Ban Meta and Galaxy Watch4 remain hardware gates."
		)
	}

	private fun buildMockWatchTelemetry(call: MethodCall): Map<String, Any?> {
		val sourceDeviceId = call.argument<String>("sourceDeviceId")
			?.takeIf { it.isNotBlank() }
			?: "galaxy-watch4-sim"
		val nowMs = System.currentTimeMillis()
		val heartRate = 145 + ((nowMs / 1000) % 8).toInt()
		return mapOf(
			"sourceDeviceId" to sourceDeviceId,
			"localTimestamp" to isoTimestamp(nowMs),
			"heartRateBpm" to heartRate,
			"interBeatIntervalMs" to 60000 / heartRate,
			"accelerometerX" to 0.31,
			"accelerometerY" to 0.42,
			"accelerometerZ" to 9.62,
			"gyroscopeX" to 0.11,
			"gyroscopeY" to 0.07,
			"gyroscopeZ" to 0.13,
			"motionIntensity" to 0.76,
			"mockReading" to true
		)
	}

	private fun startMockMetaPovCapture(
		call: MethodCall,
		result: MethodChannel.Result
	) {
		try {
			val recordingId = requiredString(call, "recordingId")
			val bridge = realPovBridge
			if (bridge != null && bridge.isAvailable()) {
				val payload = bridge.startCapture(
					mapOf(
						"recordingId" to recordingId,
						"captureMode" to call.argument<String>("captureMode"),
						"includeAudio" to call.argument<Boolean>("includeAudio"),
					)
				)
				wearablePovCaptures[recordingId] = payload
				result.success(payload)
				return
			}
			val nowMs = System.currentTimeMillis()
			val mediaFile = File(getWearableReplayOutputDirectory(), "$recordingId-mock-pov.mp4")
			mediaFile.parentFile?.mkdirs()
			mediaFile.writeText("mock Ray-Ban Meta POV capture for $recordingId\n")
			val payload = mapOf(
				"recordingId" to recordingId,
				"mediaPath" to mediaFile.absolutePath,
				"startedAt" to isoTimestamp(nowMs),
				"endedAt" to isoTimestamp(nowMs),
				"captureMode" to (call.argument<String>("captureMode") ?: "continuous"),
				"hasAudio" to (call.argument<Boolean>("includeAudio") ?: true),
				"mockCapture" to true
			)
			wearablePovCaptures[recordingId] = payload
			result.success(payload)
		} catch (error: IllegalArgumentException) {
			result.error("invalid_meta_pov_request", error.message, null)
		} catch (error: Exception) {
			result.error("meta_pov_mock_error", error.message, null)
		}
	}

	private fun stopMockMetaPovCapture(
		call: MethodCall,
		result: MethodChannel.Result
	) {
		try {
			val recordingId = requiredString(call, "recordingId")
			val bridge = realPovBridge
			if (bridge != null && bridge.isAvailable()) {
				val payload = bridge.stopCapture(recordingId)
				wearablePovCaptures.remove(recordingId)
				result.success(payload)
				return
			}
			val started = wearablePovCaptures[recordingId]
				?: throw IllegalArgumentException("Unknown recordingId: $recordingId")
			val payload = started.toMutableMap()
			payload["endedAt"] = isoTimestamp(System.currentTimeMillis())
			wearablePovCaptures.remove(recordingId)
			result.success(payload)
		} catch (error: IllegalArgumentException) {
			result.error("invalid_meta_pov_request", error.message, null)
		} catch (error: Exception) {
			result.error("meta_pov_mock_error", error.message, null)
		}
	}

	private fun startFixedCameraHlsRecording(
		call: MethodCall,
		result: MethodChannel.Result
	) {
		try {
			val recordingRequest = buildFixedCameraHlsRecordingRequest(call)
			val recorderMode = if (recordingRequest.cameraId.isNullOrBlank()) {
				"synthetic_local"
			} else {
				"camera2_hls"
			}
			val recordingResult = if (recorderMode == "camera2_hls") {
				fixedCameraCamera2HlsRecorder.start(recordingRequest)
			} else {
				fixedCameraLocalHlsRecorder.start(recordingRequest)
			}
			fixedCameraRecordingModes[recordingRequest.recordingId] = recorderMode
			result.success(
				recordingResult.toMap()
			)
		} catch (error: IllegalArgumentException) {
			result.error("invalid_fixed_camera_hls_request", error.message, null)
		} catch (error: IllegalStateException) {
			result.error("fixed_camera_hls_state_error", error.message, null)
		} catch (error: Exception) {
			result.error("fixed_camera_hls_error", error.message, null)
		}
	}

	private fun stopFixedCameraHlsRecording(
		call: MethodCall,
		result: MethodChannel.Result
	) {
		try {
			val recordingId = requiredString(call, "recordingId")
			val recorderMode = fixedCameraRecordingModes[recordingId]
				?: "synthetic_local"
			val recordingResult = if (recorderMode == "camera2_hls") {
				fixedCameraCamera2HlsRecorder.stop(recordingId)
			} else {
				fixedCameraLocalHlsRecorder.stop(recordingId)
			}
			fixedCameraRecordingModes.remove(recordingId)
			result.success(
				recordingResult.toMap()
			)
		} catch (error: IllegalArgumentException) {
			result.error("invalid_fixed_camera_hls_request", error.message, null)
		} catch (error: IllegalStateException) {
			result.error("fixed_camera_hls_state_error", error.message, null)
		} catch (error: Exception) {
			result.error("fixed_camera_hls_error", error.message, null)
		}
	}

	private fun buildFixedCameraHlsRecordingRequest(
		call: MethodCall
	): FixedCameraLocalHlsRecorder.Request {
		return FixedCameraLocalHlsRecorder.Request(
			sessionGuid = requiredString(call, "sessionGuid"),
			deviceId = requiredString(call, "deviceId"),
			recordingId = requiredString(call, "recordingId"),
			cameraId = call.argument<String>("cameraId")?.takeIf { it.isNotBlank() },
			targetDurationSeconds = call.argument<Int>("targetDurationSeconds") ?: 2,
			width = call.argument<Int>("width") ?: 1920,
			height = call.argument<Int>("height") ?: 1080,
			frameRate = call.argument<Int>("frameRate") ?: 30,
			includeAudio = call.argument<Boolean>("includeAudio") ?: true
		)
	}

	private fun requiredString(call: MethodCall, name: String): String {
		val value = call.argument<String>(name)
		require(!value.isNullOrBlank()) {
			"$name is required"
		}
		return value
	}

	private fun getFixedCameraHlsOutputDirectory(): File {
		val directory = getExternalFilesDir("fixed_camera_hls")
			?: File(filesDir, "fixed_camera_hls")
		if (!directory.exists()) {
			directory.mkdirs()
		}
		return directory
	}

	private fun getWearableReplayOutputDirectory(): File {
		val directory = getExternalFilesDir("wearable_replay")
			?: File(filesDir, "wearable_replay")
		if (!directory.exists()) {
			directory.mkdirs()
		}
		return directory
	}

	private fun isoTimestamp(epochMillis: Long): String {
		val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
		format.timeZone = TimeZone.getTimeZone("UTC")
		return format.format(java.util.Date(epochMillis))
	}
}
