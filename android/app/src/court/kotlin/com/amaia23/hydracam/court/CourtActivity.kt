package com.amaia23.hydracam.court

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Court launcher: requests runtime permissions, starts [CourtCameraService] while visible
 * (needed for a camera FGS on Android 14+) and serves the status screen over `hydracam/court`.
 */
class CourtActivity : FlutterActivity() {
    private val background = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val missing = requiredPermissions().filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), PERMISSION_REQUEST)
        }
        CourtCameraService.start(this)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) {
            // Re-promote so the FGS picks up the camera/microphone types.
            CourtCameraService.start(this)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val runtime = CourtRuntime.get(this)
            when (call.method) {
                "status" -> result.success(runtime.status())
                "enroll" -> {
                    val values = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                    val typed = values.entries.associate { (key, value) -> key.toString() to value }
                    background.execute {
                        val error = try {
                            runtime.enroll(typed, checkCurrentSecret = true)
                        } catch (failure: RuntimeException) {
                            failure.javaClass.simpleName
                        }
                        main.post { result.success(error) }
                    }
                }
                "clearEnrollment" -> {
                    val currentSecret = (call.arguments as? Map<*, *>)?.get("currentSecret")
                    background.execute {
                        val error = runtime.clearEnrollment(currentSecret, checkCurrentSecret = true)
                        main.post { result.success(error) }
                    }
                }
                "startService" -> {
                    CourtCameraService.start(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        background.shutdown()
        super.onDestroy()
    }

    private fun requiredPermissions(): List<String> {
        val permissions = mutableListOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions += Manifest.permission.POST_NOTIFICATIONS
        }
        return permissions
    }

    private companion object {
        const val CHANNEL = "hydracam/court"
        const val PERMISSION_REQUEST = 4101
    }
}
