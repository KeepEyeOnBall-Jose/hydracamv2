package com.amaia23.hydracam.wearable

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.util.Locale

class WearMainActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private val mockTelemetrySource = MockWearTelemetrySource()
    private val samples = ArrayDeque<WearTelemetrySample>()
    private lateinit var healthTelemetrySource: HealthServicesWearTelemetrySource
    private var sampleText: TextView? = null
    private var statusText: TextView? = null
    private var running = false
    private var usingMockTelemetry = true

    private val pollRunnable = object : Runnable {
        override fun run() {
            if (!running) {
                return
            }
            val nowMs = System.currentTimeMillis()
            val sample = if (usingMockTelemetry) {
                mockTelemetrySource.nextSample(nowMs)
            } else {
                healthTelemetrySource.latestSample(nowMs)
            }
            addSample(sample)
            handler.postDelayed(this, SAMPLE_INTERVAL_MS)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        healthTelemetrySource = HealthServicesWearTelemetrySource(this)
        setContentView(buildUi())
        updateStatus("Ready for HydraCam session")
    }

    override fun onResume() {
        super.onResume()
        running = true
        startTelemetry()
        handler.post(pollRunnable)
    }

    override fun onPause() {
        running = false
        handler.removeCallbacks(pollRunnable)
        healthTelemetrySource.stop()
        super.onPause()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != SENSOR_PERMISSION_REQUEST_CODE || !running) {
            return
        }
        startTelemetry()
    }

    private fun buildUi(): ScrollView {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(18, 18, 18, 18)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        root.addView(TextView(this).apply {
            text = "HydraCam Wear"
            textSize = 18f
            gravity = Gravity.CENTER
        })

        statusText = TextView(this).apply {
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(0, 10, 0, 10)
        }
        root.addView(statusText)

        sampleText = TextView(this).apply {
            textSize = 12f
            gravity = Gravity.CENTER
            setPadding(0, 8, 0, 12)
        }
        root.addView(sampleText)

        root.addView(Button(this).apply {
            text = "Marker"
            setOnClickListener {
                val marker = WearMarkerEvent(
                    markerId = "wear-marker-${System.currentTimeMillis()}",
                    sourceDeviceId = "galaxy-watch4-sim",
                    localTimestampMs = System.currentTimeMillis(),
                )
                vibrate(VibrationEffect.EFFECT_CLICK)
                updateStatus("${marker.label} saved")
            }
        })

        root.addView(Button(this).apply {
            text = "Sync Cue"
            setOnClickListener {
                val calibration = WearSyncCalibration.fromClapOrFlashAnchor(
                    masterAnchorMs = System.currentTimeMillis(),
                    wearableAnchorMs = System.currentTimeMillis() - 24,
                )
                vibrate(VibrationEffect.EFFECT_DOUBLE_CLICK)
                updateStatus(
                    "Sync ${calibration.confidence}: " +
                        "${calibration.absoluteErrorMs} ms",
                )
            }
        })

        root.addView(Button(this).apply {
            text = "Capture Cue"
            setOnClickListener {
                val ack = WearFeedbackAck(
                    feedbackId = "wear-feedback-${System.currentTimeMillis()}",
                    sourceDeviceId = "galaxy-watch4-sim",
                    localTimestampMs = System.currentTimeMillis(),
                    channel = "watchHaptic",
                    trigger = "capture_state",
                    message = "Recording confirmed",
                )
                vibrate(VibrationEffect.EFFECT_TICK)
                updateStatus(ack.message)
            }
        })

        return ScrollView(this).apply {
            addView(root)
        }
    }

    private fun startTelemetry() {
        if (!hasSensorPermissions()) {
            usingMockTelemetry = true
            requestPermissions(REQUIRED_SENSOR_PERMISSIONS, SENSOR_PERMISSION_REQUEST_CODE)
            updateStatus("Mock telemetry until watch sensor permissions are granted")
            return
        }

        usingMockTelemetry = !healthTelemetrySource.start(
            onSample = { sample ->
                handler.post {
                    if (running && !usingMockTelemetry) {
                        addSample(sample)
                    }
                }
            },
            onStatus = { message ->
                handler.post {
                    if (running) {
                        updateStatus(message)
                    }
                }
            },
        )
    }

    private fun hasSensorPermissions(): Boolean {
        return REQUIRED_SENSOR_PERMISSIONS.all { permission ->
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun addSample(sample: WearTelemetrySample) {
        samples.addLast(sample)
        while (samples.size > MAX_VISIBLE_SAMPLES) {
            samples.removeFirst()
        }
        renderSample(sample)
    }

    private fun renderSample(sample: WearTelemetrySample) {
        sampleText?.text = String.format(
            Locale.US,
            "HR %d bpm\nMotion %.2f\n%s\nSamples %d",
            sample.heartRateBpm,
            sample.motionIntensity,
            if (sample.mockReading) "Mock fallback" else "Health Services + sensors",
            samples.size,
        )
    }

    private fun updateStatus(message: String) {
        statusText?.text = message
    }

    private fun vibrate(effectId: Int) {
        val effect = VibrationEffect.createPredefined(effectId)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            val manager = getSystemService(VibratorManager::class.java)
            manager?.defaultVibrator?.vibrate(effect)
        } else {
            @Suppress("DEPRECATION")
            val vibrator = getSystemService(VIBRATOR_SERVICE) as? Vibrator
            vibrator?.vibrate(effect)
        }
    }

    private companion object {
        const val SAMPLE_INTERVAL_MS = 1_000L
        const val MAX_VISIBLE_SAMPLES = 12
        const val SENSOR_PERMISSION_REQUEST_CODE = 4040
        // No android.Manifest constant exists for the health permission, so it
        // is referenced by its framework string. Health Services MeasureClient
        // on Wear OS 5+/API 35+ requires it to register a heart-rate stream.
        const val READ_HEART_RATE_PERMISSION = "android.permission.health.READ_HEART_RATE"
        val REQUIRED_SENSOR_PERMISSIONS = arrayOf(
            Manifest.permission.BODY_SENSORS,
            Manifest.permission.ACTIVITY_RECOGNITION,
            READ_HEART_RATE_PERMISSION,
        )
    }
}
