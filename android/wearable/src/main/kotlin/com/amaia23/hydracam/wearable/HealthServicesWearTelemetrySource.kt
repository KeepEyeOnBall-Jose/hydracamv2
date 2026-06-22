package com.amaia23.hydracam.wearable

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.health.services.client.HealthServices
import androidx.health.services.client.MeasureCallback
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DataTypeAvailability
import androidx.health.services.client.data.DeltaDataType
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

class HealthServicesWearTelemetrySource(
    private val context: Context,
    private val sourceDeviceId: String = "galaxy-watch4",
) {
    private val appContext = context.applicationContext
    private val motionSource = AndroidMotionSensorSource(appContext)
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val sampleIndex = AtomicInteger(0)
    private val latestHeartRateBpm = AtomicInteger(0)
    @Volatile private var sampleCallback: ((WearTelemetrySample) -> Unit)? = null
    @Volatile private var statusCallback: ((String) -> Unit)? = null
    @Volatile private var started = false

    private val measureClient by lazy {
        HealthServices.getClient(appContext).measureClient
    }

    private val measureCallback = object : MeasureCallback {
        override fun onRegistered() {
            statusCallback?.invoke("Health Services heart-rate stream registered")
        }

        override fun onRegistrationFailed(throwable: Throwable) {
            statusCallback?.invoke(
                "Health Services registration failed: ${throwable.shortMessage()}",
            )
        }

        override fun onAvailabilityChanged(
            dataType: DeltaDataType<*, *>,
            availability: Availability,
        ) {
            val availabilityLabel = if (availability is DataTypeAvailability) {
                availability.name
            } else {
                availability.javaClass.simpleName
            }
            statusCallback?.invoke(
                "Health Services ${dataType.name} availability: $availabilityLabel",
            )
        }

        override fun onDataReceived(data: DataPointContainer) {
            val latest = data.getData(DataType.HEART_RATE_BPM)
                .lastOrNull()
                ?.value
                ?.toInt()
            if (latest != null) {
                latestHeartRateBpm.set(latest)
                sampleCallback?.invoke(latestSample(System.currentTimeMillis()))
            }
        }
    }

    fun start(
        onSample: (WearTelemetrySample) -> Unit,
        onStatus: (String) -> Unit,
    ): Boolean {
        sampleCallback = onSample
        statusCallback = onStatus

        return try {
            motionSource.start()
            measureClient.registerMeasureCallback(
                DataType.HEART_RATE_BPM,
                executor,
                measureCallback,
            )
            started = true
            statusCallback?.invoke("Health Services HR + motion telemetry active")
            true
        } catch (error: Throwable) {
            started = false
            motionSource.stop()
            statusCallback?.invoke(
                "Mock telemetry fallback: ${error.shortMessage()}",
            )
            false
        }
    }

    fun stop() {
        if (!started) {
            motionSource.stop()
            return
        }
        started = false
        try {
            measureClient.javaClass.methods
                .firstOrNull { method ->
                    method.name == "unregisterMeasureCallbackAsync" &&
                        method.parameterTypes.size == 2
                }
                ?.invoke(measureClient, DataType.HEART_RATE_BPM, measureCallback)
        } catch (_: Throwable) {
            // Stop is best-effort because the activity may already be tearing down.
        }
        motionSource.stop()
    }

    fun latestSample(nowMs: Long): WearTelemetrySample {
        val motion = motionSource.snapshot()
        val heartRate = latestHeartRateBpm.get().takeIf { it > 0 }
        return WearTelemetrySample.fromHeartRateAndMotion(
            sampleId = "watch-health-${sampleIndex.incrementAndGet()}",
            sourceDeviceId = sourceDeviceId,
            localTimestampMs = nowMs,
            heartRateBpm = heartRate,
            accelerometerX = motion.accelerometerX,
            accelerometerY = motion.accelerometerY,
            accelerometerZ = motion.accelerometerZ,
            gyroscopeX = motion.gyroscopeX,
            gyroscopeY = motion.gyroscopeY,
            gyroscopeZ = motion.gyroscopeZ,
            mockReading = false,
        )
    }

    fun capabilitySummary(): Map<String, Any> {
        return try {
            val client = HealthServices.getClient(appContext)
            mapOf(
                "preferredApi" to "wear_os_health_services",
                "measureClientAvailable" to true,
                "exerciseClientAvailable" to true,
                "heartRateDataType" to DataType.HEART_RATE_BPM.name,
                "measureClientClass" to client.measureClient.javaClass.name,
                "exerciseClientClass" to client.exerciseClient.javaClass.name,
            )
        } catch (error: Throwable) {
            mapOf(
                "preferredApi" to "wear_os_health_services",
                "measureClientAvailable" to false,
                "exerciseClientAvailable" to false,
                "error" to (error.message ?: error.javaClass.simpleName),
            )
        }
    }

    private fun Throwable.shortMessage(): String {
        return message ?: javaClass.simpleName
    }
}

data class WearMotionSnapshot(
    val accelerometerX: Double,
    val accelerometerY: Double,
    val accelerometerZ: Double,
    val gyroscopeX: Double,
    val gyroscopeY: Double,
    val gyroscopeZ: Double,
)

private class AndroidMotionSensorSource(
    context: Context,
) : SensorEventListener {
    private val sensorManager = context.getSystemService(SensorManager::class.java)
    private val accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val gyroscope = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

    @Volatile private var accelerometerX = 0.0
    @Volatile private var accelerometerY = 0.0
    @Volatile private var accelerometerZ = 9.81
    @Volatile private var gyroscopeX = 0.0
    @Volatile private var gyroscopeY = 0.0
    @Volatile private var gyroscopeZ = 0.0

    fun start() {
        accelerometer?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
        gyroscope?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
    }

    fun stop() {
        sensorManager?.unregisterListener(this)
    }

    fun snapshot(): WearMotionSnapshot {
        return WearMotionSnapshot(
            accelerometerX = accelerometerX,
            accelerometerY = accelerometerY,
            accelerometerZ = accelerometerZ,
            gyroscopeX = gyroscopeX,
            gyroscopeY = gyroscopeY,
            gyroscopeZ = gyroscopeZ,
        )
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.values.size < 3) {
            return
        }
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                accelerometerX = event.values[0].toDouble()
                accelerometerY = event.values[1].toDouble()
                accelerometerZ = event.values[2].toDouble()
            }
            Sensor.TYPE_GYROSCOPE -> {
                gyroscopeX = event.values[0].toDouble()
                gyroscopeY = event.values[1].toDouble()
                gyroscopeZ = event.values[2].toDouble()
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Sample payloads carry measured values only; accuracy is not part of v1 replay overlays.
    }
}
