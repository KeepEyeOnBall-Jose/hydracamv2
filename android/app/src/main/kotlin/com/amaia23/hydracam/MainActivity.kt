package com.amaia23.hydracam

import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.MediaMetadataRetriever
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
	private val launchConfigChannelName = "hydracamv2/launch_config"
	private val cameraMetadataChannelName = "hydracamv2/camera_metadata"
	private val videoMetadataChannelName = "hydracamv2/video_metadata"

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
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
	}

	private fun buildLaunchConfig(): Map<String, Any?> {
		val extras = intent?.extras ?: return emptyMap()
		val payload = mutableMapOf<String, Any?>()

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

		return payload
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
}
