package com.amaia23.hydracam.spike.preview

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureFailure
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.TotalCaptureResult
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.util.Range
import android.util.Size
import android.view.Surface
import androidx.annotation.RequiresApi
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/**
 * One Camera2 session feeding several encoder surfaces. A target with a lower fps than the
 * camera is fed from a subset of the requests of a repeating burst (20 of 30 fps = 2 of every
 * 3 requests), so it never sees frames it would have to drop.
 */
class SharedCameraSession(
    private val context: Context,
    private val cameraFps: Int,
    private val targets: List<Target>,
) {
    class Target(val name: String, val surface: Surface, val fps: Int) {
        val bufferLost = AtomicLong()
    }

    val captureStarted = AtomicLong()
    val captureCompleted = AtomicLong()
    val captureFailed = AtomicLong()
    val info = linkedMapOf<String, Any?>()

    /** Wall-clock ns minus sensor-timebase ns, measured at the first capture. */
    @Volatile var sensorToWallNs: Long? = null
        private set
    /** Recent sensor timestamps (us), to check that encoder PTS equal sensor timestamps. */
    val recentSensorUs = LongArray(256)
    @Volatile var recentSensorCount = 0L

    private val thread = HandlerThread("h8-camera").apply { start() }
    private val handler = Handler(thread.looper)
    private val executor = Executor { handler.post(it) }
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null

    @SuppressLint("MissingPermission")
    fun open() {
        val manager = context.getSystemService(CameraManager::class.java)
        val cameraId = backCameraId(manager)
        val chars = manager.getCameraCharacteristics(cameraId)
        info["cameraId"] = cameraId
        info["hardwareLevel"] = hardwareLevelName(chars.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL))
        info["timestampSource"] = when (chars.get(CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE)) {
            CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME -> "REALTIME"
            else -> "UNKNOWN"
        }
        info["aeFpsRanges"] = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)?.joinToString()

        val opened = CountDownLatch(1)
        var openError: String? = null
        manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
            override fun onOpened(camera: CameraDevice) {
                device = camera
                opened.countDown()
            }

            override fun onDisconnected(camera: CameraDevice) {
                Log.w(TAG, "camera disconnected")
                openError = "disconnected"
                camera.close()
                opened.countDown()
            }

            override fun onError(camera: CameraDevice, error: Int) {
                Log.e(TAG, "camera error $error")
                openError = "error $error"
                camera.close()
                opened.countDown()
            }
        }, handler)
        check(opened.await(10, TimeUnit.SECONDS)) { "camera open timed out" }
        val camera = checkNotNull(device) { "camera open failed: $openError" }

        val outputs = targets.map { OutputConfiguration(it.surface) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            info["sessionSupported"] = runCatching {
                camera.isSessionConfigurationSupported(sessionConfiguration(outputs, NO_OP_STATE))
            }.getOrElse { "unknown: ${it.message}" }
        }

        val configured = CountDownLatch(1)
        val state = object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(s: CameraCaptureSession) {
                session = s
                configured.countDown()
            }

            override fun onConfigureFailed(s: CameraCaptureSession) {
                Log.e(TAG, "session configure failed for ${targets.map { it.name }}")
                configured.countDown()
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            camera.createCaptureSession(sessionConfiguration(outputs, state))
        } else {
            @Suppress("DEPRECATION")
            camera.createCaptureSessionByOutputConfigurations(outputs, state, handler)
        }
        check(configured.await(10, TimeUnit.SECONDS)) { "session configure timed out" }
        val s = checkNotNull(session) { "session configure failed for ${targets.map { it.name }}" }

        val burst = burstRequests(camera)
        info["burst"] = burst.size
        if (burst.size == 1) s.setRepeatingRequest(burst[0], captureCallback, handler)
        else s.setRepeatingBurst(burst, captureCallback, handler)
        Log.i(TAG, "camera streaming: $info")
    }

    fun targetBufferLost(name: String): Long? = targets.firstOrNull { it.name == name }?.bufferLost?.get()

    fun close() {
        runCatching { session?.stopRepeating() }
        runCatching { session?.abortCaptures() }
        runCatching { session?.close() }
        runCatching { device?.close() }
        thread.quitSafely()
    }

    @RequiresApi(Build.VERSION_CODES.P)
    private fun sessionConfiguration(
        outputs: List<OutputConfiguration>,
        state: CameraCaptureSession.StateCallback,
    ) = SessionConfiguration(SessionConfiguration.SESSION_REGULAR, outputs, executor, state)

    private fun burstRequests(camera: CameraDevice): List<CaptureRequest> {
        val length = targets.fold(1) { acc, t -> lcm(acc, cameraFps / gcd(cameraFps, t.fps)) }
        return (0 until length).map { i ->
            camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, Range(cameraFps, cameraFps))
                targets.filter { includes(it.fps, i) }.forEach { addTarget(it.surface) }
            }.build()
        }
    }

    /** Spreads [fps] of every [cameraFps] requests evenly (Bresenham). */
    private fun includes(fps: Int, index: Int): Boolean {
        if (fps >= cameraFps) return true
        return ((index + 1) * fps) / cameraFps > (index * fps) / cameraFps
    }

    private val captureCallback = object : CameraCaptureSession.CaptureCallback() {
        override fun onCaptureStarted(s: CameraCaptureSession, r: CaptureRequest, timestamp: Long, frame: Long) {
            captureStarted.incrementAndGet()
            if (sensorToWallNs == null) sensorToWallNs = calibrate(timestamp)
            val n = recentSensorCount
            recentSensorUs[(n % recentSensorUs.size).toInt()] = timestamp / 1_000
            recentSensorCount = n + 1
        }

        override fun onCaptureCompleted(s: CameraCaptureSession, r: CaptureRequest, result: TotalCaptureResult) {
            captureCompleted.incrementAndGet()
        }

        override fun onCaptureFailed(s: CameraCaptureSession, r: CaptureRequest, failure: CaptureFailure) {
            captureFailed.incrementAndGet()
        }

        override fun onCaptureBufferLost(s: CameraCaptureSession, r: CaptureRequest, target: Surface, frame: Long) {
            targets.firstOrNull { it.surface == target }?.bufferLost?.incrementAndGet()
        }
    }

    /**
     * Maps the sensor timebase to wall clock. REALTIME is elapsedRealtimeNanos; UNKNOWN is
     * usually uptime (System.nanoTime) on Samsung, so then pick whichever clock is closest.
     */
    private fun calibrate(sensorNs: Long): Long {
        val wallNs = System.currentTimeMillis() * 1_000_000
        val realtime = SystemClock.elapsedRealtimeNanos()
        val uptime = System.nanoTime()
        val useRealtime = info["timestampSource"] == "REALTIME" ||
            Math.abs(realtime - sensorNs) <= Math.abs(uptime - sensorNs)
        info["sensorClock"] = if (useRealtime) "elapsedRealtime" else "nanoTime"
        info["sensorDeliveryDelayMs"] = ((if (useRealtime) realtime else uptime) - sensorNs) / 1_000_000.0
        return wallNs - (if (useRealtime) realtime else uptime)
    }

    companion object {
        private const val TAG = "H8Spike"
        private val NO_OP_STATE = object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(s: CameraCaptureSession) {}
            override fun onConfigureFailed(s: CameraCaptureSession) {}
        }

        fun backCameraId(manager: CameraManager): String = manager.cameraIdList.first {
            manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) ==
                CameraCharacteristics.LENS_FACING_BACK
        }

        /** Output sizes the back camera supports for a consumer class (MediaCodec, SurfaceTexture). */
        fun outputSizes(context: Context, consumer: Class<*>): List<Size> {
            val manager = context.getSystemService(CameraManager::class.java)
            val map = manager.getCameraCharacteristics(backCameraId(manager))
                .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: return emptyList()
            return map.getOutputSizes(consumer)?.toList().orEmpty()
        }

        private fun gcd(a: Int, b: Int): Int = if (b == 0) a else gcd(b, a % b)
        private fun lcm(a: Int, b: Int): Int = a / gcd(a, b) * b

        private fun hardwareLevelName(level: Int?) = when (level) {
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY -> "LEGACY"
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_LIMITED -> "LIMITED"
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_FULL -> "FULL"
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_3 -> "LEVEL_3"
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_EXTERNAL -> "EXTERNAL"
            else -> "unknown($level)"
        }
    }
}
