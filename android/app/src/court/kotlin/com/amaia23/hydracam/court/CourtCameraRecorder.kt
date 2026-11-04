package com.amaia23.hydracam.court

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Range
import android.util.Size
import android.view.Surface
import androidx.core.content.ContextCompat
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** Recorder → runtime. `recording.*` C1 events are sent from these callbacks. */
interface CourtRecorderListener {
    fun onRecordingStarted(sessionId: String, firstFrameServerMs: Long, profile: RecordProfile)

    fun onSegment(segment: SegmentRecord)

    /** A crash left a tier's last part with no whole frame (C1 `recording.gap`). */
    fun onSegmentLost(gap: SegmentGap)

    fun onRecordingStopped(sessionId: String, lastSeqProxy: Long, lastSeqMaster: Long, reason: String)

    fun onRecorderFailed(sessionId: String, error: String)
}

/**
 * H5/H6/H15/H17: one Camera2 session feeding a master and a proxy (low) H.264 encoder, each cut into
 * 6 s MPEG-TS segments. AE/AF/AWB lock after warm-up; OIS/EIS off; torch through `FLASH_MODE_TORCH`
 * in the repeating request. Audio only when `record.start.audio`. The camera is closed when idle,
 * unless the live preview holds it ([CourtPreviewSeam]).
 *
 * The preview encoder's surface joins the capture session at open (or the session is retried
 * without it); preview on/off only swaps the repeating burst, so the master never sees a rebuild.
 *
 * Port calls return at once; work runs on one control thread.
 */
class CourtCameraRecorder(
    private val context: Context,
    private val storage: CourtStorage,
    private val seqStore: SegmentSeqStore,
    private val clockEstimator: ClockOffsetEstimator,
    private val slot: () -> String,
    private val listener: CourtRecorderListener,
    private val logger: CourtLogger = NoopCourtLogger,
) : CourtRecorderPort,
    TorchControl,
    CourtPreviewSeam {
    private val control = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "CourtRecorder")
    }

    @Volatile
    private var pipeline: CameraPipeline? = null

    @Volatile
    private var recording: Recording? = null

    @Volatile
    private var previewSurface: Surface? = null

    @Volatile
    private var previewFps = 0

    /** Control thread only: the live preview holds the camera / K2 armed it for a session. */
    private var held = false
    private var armed = false

    /** For the status screen: `closed`, `warming`, `locked`. */
    val cameraState: String
        get() = pipeline?.let { if (it.locked) "locked" else "warming" } ?: "closed"

    /** For the status screen: the preview output made it into the open capture session. */
    val previewInSession: Boolean
        get() = pipeline?.previewInSession == true

    override fun prepare(sessionId: String, profile: RecordProfile) {
        control.execute {
            if (recording != null) {
                return@execute
            }
            armed = true
            try {
                ensurePipeline(profile, sessionId)
            } catch (error: Exception) {
                // Not armed: holdCameraForPreview(false) and disarm() must be free to close the camera.
                armed = false
                fail(sessionId, "camera_open: ${error.message}", error)
            }
        }
    }

    override fun start(command: RecordStart, profile: RecordProfile) {
        control.execute { startNow(command, profile) }
    }

    override fun refresh(command: RecordStart) {
        logger.info(TAG, "record.start refresh for ${command.sessionId}.")
    }

    override fun stop(sessionId: String, stopAtServerMs: Long, reason: String) {
        control.execute {
            val active = recording
            if (active == null || active.sessionId != sessionId) {
                // Nothing running (crash recovery or failed start): close what a kill left, report the seqs.
                armed = false
                closeUnlessHeld()
                recoverParts(sessionId)
                listener.onRecordingStopped(
                    sessionId,
                    seqStore.lastSeq(sessionId, C1.TIER_PROXY),
                    seqStore.lastSeq(sessionId, C1.TIER_MASTER),
                    reason,
                )
                return@execute
            }
            val nowServerMs = clockEstimator.toServerMs(System.currentTimeMillis())
            val stopAt = if (stopAtServerMs > 0) stopAtServerMs else nowServerMs
            active.stopAtServerMs = stopAt
            val waitMs = (stopAt - nowServerMs).coerceIn(0, MAX_STOP_WAIT_MS) + STOP_GRACE_MS
            control.schedule({ finishRecording(active, reason) }, waitMs, TimeUnit.MILLISECONDS)
        }
    }

    override fun disarm(sessionId: String) {
        control.execute {
            armed = false
            if (recording == null) {
                closeUnlessHeld()
            }
        }
    }

    override fun torchAvailable(): Boolean = pipeline?.hasFlash == true

    override fun setTorch(on: Boolean) {
        pipeline?.setTorch(on)
    }

    override fun previewOutputSizes(): List<Size> = try {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        manager.getCameraCharacteristics(backCameraId(manager))
            .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?.getOutputSizes(MediaCodec::class.java)
            ?.toList()
            .orEmpty()
    } catch (error: Exception) {
        logger.warn(TAG, "Could not read the preview output sizes.", error)
        emptyList()
    }

    override fun setPreviewSurface(surface: Surface?) {
        previewSurface = surface
    }

    override fun setPreviewFps(fps: Int) {
        previewFps = max(0, fps)
        pipeline?.resubmit("Preview burst")
    }

    override fun holdCameraForPreview(hold: Boolean) {
        control.execute {
            held = hold
            if (!hold) {
                if (recording == null && !armed) {
                    closePipeline()
                }
                return@execute
            }
            if (pipeline != null) {
                return@execute
            }
            try {
                ensurePipeline(RecordProfile.DEFAULT)
            } catch (error: Exception) {
                logger.warn(TAG, "Live preview could not open the camera.", error)
            }
        }
    }

    override fun cameraOpen(): Boolean = pipeline != null

    override fun captureWallMs(sensorNs: Long): Long =
        pipeline?.ptsClock?.wallMsFor(sensorNs / NS_PER_US) ?: System.currentTimeMillis()

    fun shutdown() {
        control.execute {
            recording?.let { finishRecording(it, CourtStateMachine.REASON_ERROR) }
            closePipeline()
        }
        control.shutdown()
    }

    private fun startNow(command: RecordStart, profile: RecordProfile) {
        val sessionId = command.sessionId
        if (recording?.sessionId == sessionId) {
            return
        }
        try {
            val pipe = ensurePipeline(profile)
            val timebase = SessionTimebase { ptsUs -> clockEstimator.toServerMs(pipe.ptsClock.wallMsFor(ptsUs)) }
            val sidecar = JsonlAppender(storage.sidecar(sessionId))
            val withAudio = command.audio && hasPermission(Manifest.permission.RECORD_AUDIO)
            if (command.audio && !withAudio) {
                logger.warn(TAG, "record.start asked for audio but RECORD_AUDIO is not granted; video only.")
            }
            val frameUs = 1_000_000L / max(1, profile.fps)
            val segmenters = C1.TIERS.associateWith { tier ->
                TsSegmenter(
                    sessionId = sessionId,
                    slot = slot(),
                    tier = tier,
                    directory = storage.tierDir(sessionId, tier),
                    sidecar = sidecar,
                    seqStore = seqStore,
                    timebase = timebase,
                    segmentDurationUs = profile.segmentS * 1_000_000L,
                    frameDurationUs = frameUs,
                    hasAudio = withAudio,
                    clockEstimate = { clockEstimator.current() },
                    onSegment = { listener.onSegment(it) },
                    onGap = { listener.onSegmentLost(it) },
                    requestSyncFrame = { pipe.encoder(tier).requestSyncFrame() },
                    logger = logger,
                ).also { segmenter -> pipe.config(tier)?.let { segmenter.onVideoConfig(it) } }
            }
            val active = Recording(sessionId, profile, command.startAtServerMs, timebase, segmenters)
            recording = active
            if (withAudio) {
                active.audio = AudioPipeline(pipe.ptsClock) { ptsUs, aac ->
                    segmenters.values.forEach { segmenter -> segmenter.onAudioFrame(ptsUs, aac) }
                }.also { it.start() }
            }
            // Ask both encoders for an IDR at the start time so seq 0 begins promptly.
            val delayMs = max(0, clockEstimator.toDeviceMs(command.startAtServerMs) - System.currentTimeMillis())
            control.schedule(
                { if (recording === active) C1.TIERS.forEach { pipe.encoder(it).requestSyncFrame() } },
                delayMs,
                TimeUnit.MILLISECONDS,
            )
            logger.info(
                TAG,
                "Recording $sessionId armed for server ${command.startAtServerMs} (in $delayMs ms), audio=$withAudio.",
            )
        } catch (error: Exception) {
            fail(sessionId, "record_start: ${error.message}", error)
        }
    }

    private fun finishRecording(active: Recording, reason: String) {
        if (recording !== active) {
            return
        }
        recording = null
        armed = false
        active.audio?.stop()
        val lastSeqs = C1.TIERS.associateWith { tier ->
            val segmenter = active.segmenters.getValue(tier)
            try {
                segmenter.finish()
            } catch (error: IOException) {
                logger.warn(TAG, "Could not close the last $tier segment.", error)
                segmenter.abort()
                seqStore.lastSeq(active.sessionId, tier)
            }
        }
        closeUnlessHeld()
        logger.info(TAG, "Recording ${active.sessionId} stopped ($reason), lastSeq=$lastSeqs.")
        listener.onRecordingStopped(
            active.sessionId,
            lastSeqs.getValue(C1.TIER_PROXY),
            lastSeqs.getValue(C1.TIER_MASTER),
            reason,
        )
    }

    private fun fail(sessionId: String, message: String, error: Throwable?) {
        logger.warn(TAG, message, error)
        listener.onRecorderFailed(sessionId, message)
    }

    /**
     * The open pipeline for [profile], opened if needed. [sessionId] is set by `record.prepare` only:
     * a pipeline the live preview or an earlier session warmed up warms up again (see [pipelineAction]).
     */
    private fun ensurePipeline(profile: RecordProfile, sessionId: String? = null): CameraPipeline {
        val current = pipeline
        return when (pipelineAction(current?.profile, current?.warmedFor, profile, sessionId)) {
            PipelineAction.REUSE -> checkNotNull(current)
            PipelineAction.REWARM -> checkNotNull(current).also { it.rewarm(checkNotNull(sessionId)) }
            PipelineAction.REOPEN -> {
                closePipeline()
                openPipeline(profile, sessionId)
            }
            PipelineAction.OPEN -> openPipeline(profile, sessionId)
        }
    }

    private fun openPipeline(profile: RecordProfile, sessionId: String?): CameraPipeline {
        if (!hasPermission(Manifest.permission.CAMERA)) {
            throw SecurityException("CAMERA permission not granted.")
        }
        val pipe = CameraPipeline(profile)
        try {
            pipe.open()
        } catch (error: Exception) {
            pipe.close()
            throw error
        }
        pipe.warmedFor = sessionId
        pipeline = pipe
        if (pipe.previewInSession) {
            // A setPreviewFps() during open() found no pipeline to resubmit; catch it up.
            pipe.resubmit("Preview burst")
        }
        return pipe
    }

    /** The live preview keeps the camera open past a recording (R2: it never records). */
    private fun closeUnlessHeld() {
        if (!held) {
            closePipeline()
        }
    }

    private fun closePipeline() {
        val pipe = pipeline ?: return
        pipeline = null
        pipe.close()
    }

    private fun recoverParts(sessionId: String) {
        val sidecar = JsonlAppender(storage.sidecar(sessionId))
        C1.TIERS.forEach { tier ->
            try {
                val directory = storage.tierDir(sessionId, tier)
                TsPartRecovery(sessionId, slot(), tier, directory, sidecar, seqStore, logger = logger).recover(
                    onSegment = { listener.onSegment(it) },
                    onGap = { listener.onSegmentLost(it) },
                )
            } catch (error: IOException) {
                logger.warn(TAG, "Could not recover $sessionId/$tier parts.", error)
            }
        }
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    /** Encoded output of one tier: routed to the session's segmenter inside the record window. */
    private fun onEncodedFrame(tier: String, ptsUs: Long, annexB: ByteArray, isKeyframe: Boolean) {
        val active = recording ?: return
        if (!active.inWindow(ptsUs) || !writeFrame(active, tier, ptsUs, annexB, isKeyframe)) {
            return
        }
        if (!active.announced && active.timebase.baseUs >= 0) {
            active.announced = true
            val firstFrameServerMs = active.timebase.serverMs(active.timebase.baseUs)
            listener.onRecordingStarted(active.sessionId, firstFrameServerMs, active.profile)
        }
    }

    /** False after a write error, which fails the session (once). */
    private fun writeFrame(
        active: Recording,
        tier: String,
        ptsUs: Long,
        annexB: ByteArray,
        isKeyframe: Boolean,
    ): Boolean = try {
        active.segmenters.getValue(tier).onVideoFrame(ptsUs, annexB, isKeyframe)
        true
    } catch (error: IOException) {
        if (!active.failed) {
            active.failed = true
            fail(active.sessionId, "segment_io: ${error.message}", error)
        }
        false
    }

    private fun onEncoderConfig(tier: String, config: ByteArray) {
        recording?.segmenters?.get(tier)?.onVideoConfig(config)
    }

    private class Recording(
        val sessionId: String,
        val profile: RecordProfile,
        val startAtServerMs: Long,
        val timebase: SessionTimebase,
        val segmenters: Map<String, TsSegmenter>,
    ) {
        @Volatile
        var stopAtServerMs: Long = Long.MAX_VALUE

        /** Inside `[startAtServerMs, stopAtServerMs)` on the server clock. */
        fun inWindow(ptsUs: Long): Boolean =
            timebase.serverMs(ptsUs).let { it >= startAtServerMs && it < stopAtServerMs }

        @Volatile
        var announced = false

        @Volatile
        var failed = false

        var audio: AudioPipeline? = null
    }

    private inner class CameraPipeline(val profile: RecordProfile) {
        private val thread = HandlerThread("CourtCamera").apply { start() }
        private val handler = Handler(thread.looper)
        private val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        private val cameraId: String = backCameraId(manager)
        private val characteristics = manager.getCameraCharacteristics(cameraId)
        private val encoders = mutableMapOf<String, VideoEncoder>()

        /** Read once: a surface set later joins at the next open. */
        private val preview: Surface? = previewSurface
        private val configs = mutableMapOf<String, ByteArray>()
        private var device: CameraDevice? = null
        private var session: CameraCaptureSession? = null
        private var builder: CaptureRequest.Builder? = null
        private var openedAtMs = 0L
        private var lastFocusDistance: Float? = null
        private var afTriggered = false
        private var torchOn = false

        /** Control thread only: the session whose `record.prepare` warmed 3A up (null: the preview). */
        var warmedFor: String? = null

        val ptsClock = PtsClock(
            characteristics.get(CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE) ==
                CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME,
            realtimeUs = { SystemClock.elapsedRealtimeNanos() / 1_000 },
        )
        val hasFlash: Boolean = characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true

        @Volatile
        var locked = false
            private set

        @Volatile
        var previewInSession = false
            private set

        fun encoder(tier: String): VideoEncoder = encoders.getValue(tier)

        @Synchronized
        fun config(tier: String): ByteArray? = configs[tier]

        @Synchronized
        private fun storeConfig(tier: String, config: ByteArray) {
            configs[tier] = config
        }

        @SuppressLint("MissingPermission")
        fun open() {
            val sizes = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?.getOutputSizes(MediaCodec::class.java)
                ?.toList()
                .orEmpty()
            val masterSize = pickSize(sizes, RecordProfile.sizeFor(profile.masterRes))
            val proxySize = pickSize(sizes, RecordProfile.sizeFor(profile.proxyRes))
            encoders[C1.TIER_MASTER] = VideoEncoder(C1.TIER_MASTER, masterSize, profile.fps, profile.masterKbps)
            encoders[C1.TIER_PROXY] = VideoEncoder(C1.TIER_PROXY, proxySize, profile.fps, profile.proxyKbps)
            encoders.values.forEach { it.start() }

            val opened = CountDownLatch(1)
            var openError: Exception? = null
            manager.openCamera(
                cameraId,
                object : CameraDevice.StateCallback() {
                    override fun onOpened(camera: CameraDevice) {
                        device = camera
                        configureSession(camera) { error ->
                            openError = error
                            opened.countDown()
                        }
                    }

                    override fun onDisconnected(camera: CameraDevice) {
                        openError = IllegalStateException("Camera $cameraId disconnected.")
                        camera.close()
                        opened.countDown()
                    }

                    override fun onError(camera: CameraDevice, error: Int) {
                        openError = IllegalStateException("Camera $cameraId error $error.")
                        camera.close()
                        opened.countDown()
                    }
                },
                handler,
            )
            check(opened.await(OPEN_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                "Camera $cameraId did not open in $OPEN_TIMEOUT_MS ms."
            }
            openError?.let { throw it }
            logger.info(
                TAG,
                "Camera $cameraId open: master $masterSize, proxy $proxySize @ ${profile.fps} fps, " +
                    "preview output ${if (previewInSession) "on" else "off"}.",
            )
        }

        private fun configureSession(camera: CameraDevice, withPreview: Boolean = true, done: (Exception?) -> Unit) {
            val recordSurfaces = encoders.values.map { it.surface }
            val extra = preview?.takeIf { withPreview }
            camera.createCaptureSession(
                recordSurfaces + listOfNotNull(extra),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(configured: CameraCaptureSession) {
                        try {
                            session = configured
                            previewInSession = extra != null
                            // The builder targets the encoders only; submit() adds the preview per burst slot.
                            val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
                            recordSurfaces.forEach { request.addTarget(it) }
                            applyBaseControls(request)
                            builder = request
                            openedAtMs = SystemClock.elapsedRealtime()
                            submit()
                            done(null)
                        } catch (error: Exception) {
                            done(error)
                        }
                    }

                    override fun onConfigureFailed(configured: CameraCaptureSession) {
                        if (extra != null) {
                            // The recording comes first: drop the preview output rather than fail.
                            logger.warn(TAG, "Capture session refused the preview output; recording without it.")
                            configureSession(camera, withPreview = false, done = done)
                        } else {
                            done(IllegalStateException("Capture session configuration failed."))
                        }
                    }
                },
                handler,
            )
        }

        private fun applyBaseControls(request: CaptureRequest.Builder) {
            request.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
            request.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
            request.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
            request.set(CaptureRequest.CONTROL_AWB_MODE, CaptureRequest.CONTROL_AWB_MODE_AUTO)
            request.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_OFF)
            // EIS and OIS off: both shift the image, which breaks the fixed court calibration.
            request.set(
                CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE,
                CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_OFF,
            )
            val oisModes = characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION)
            if (oisModes?.contains(CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE_OFF) == true) {
                request.set(
                    CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE,
                    CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE_OFF,
                )
            }
            fixedFpsRange()?.let { request.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, it) }
        }

        private fun fixedFpsRange(): Range<Int>? {
            val ranges = characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                ?: return null
            return ranges.firstOrNull { it.lower == profile.fps && it.upper == profile.fps }
                ?: ranges.filter { it.upper == profile.fps }.maxByOrNull { it.lower }
        }

        /**
         * Must run on [handler]. One repeating request, or a burst whose slots feed the preview
         * output at [previewFps] (see [PreviewBurst]); every slot feeds both encoders.
         */
        private fun submit() {
            val request = builder ?: return
            val current = session ?: return
            request.set(
                CaptureRequest.FLASH_MODE,
                if (torchOn) CaptureRequest.FLASH_MODE_TORCH else CaptureRequest.FLASH_MODE_OFF,
            )
            val target = preview?.takeIf { previewInSession }
            val pattern = if (target == null) listOf(false) else PreviewBurst.pattern(profile.fps, previewFps)
            val requests = pattern.map { show -> build(request, target?.takeIf { show }) }
            val callback = if (locked) null else warmupCallback
            if (requests.size == 1) {
                current.setRepeatingRequest(requests.first(), callback, handler)
            } else {
                current.setRepeatingBurst(requests, callback, handler)
            }
        }

        private fun build(request: CaptureRequest.Builder, extra: Surface?): CaptureRequest {
            if (extra == null) {
                return request.build()
            }
            request.addTarget(extra)
            try {
                return request.build()
            } finally {
                request.removeTarget(extra)
            }
        }

        /** Re-issues the repeating burst with the current torch and preview fps. */
        fun resubmit(what: String) {
            handler.post {
                try {
                    submit()
                } catch (error: Exception) {
                    logger.warn(TAG, "$what update failed.", error)
                }
            }
        }

        private val warmupCallback = object : CameraCaptureSession.CaptureCallback() {
            override fun onCaptureCompleted(
                captureSession: CameraCaptureSession,
                request: CaptureRequest,
                result: TotalCaptureResult,
            ) {
                if (locked) {
                    return
                }
                result.get(CaptureResult.LENS_FOCUS_DISTANCE)?.let { lastFocusDistance = it }
                val ae = result.get(CaptureResult.CONTROL_AE_STATE)
                val awb = result.get(CaptureResult.CONTROL_AWB_STATE)
                val aeReady = ae == null ||
                    ae == CaptureResult.CONTROL_AE_STATE_CONVERGED ||
                    ae == CaptureResult.CONTROL_AE_STATE_FLASH_REQUIRED
                val awbReady = awb == null || awb == CaptureResult.CONTROL_AWB_STATE_CONVERGED
                val converged = aeReady && awbReady
                val elapsed = SystemClock.elapsedRealtime() - openedAtMs
                if ((elapsed >= WARMUP_MIN_MS && converged) || elapsed >= WARMUP_MAX_MS) {
                    lock(elapsed, converged)
                }
            }
        }

        /** Runs on [handler] (capture callback). */
        private fun lock(elapsedMs: Long, converged: Boolean) {
            val request = builder ?: return
            locked = true
            request.set(CaptureRequest.CONTROL_AE_LOCK, true)
            request.set(CaptureRequest.CONTROL_AWB_LOCK, true)
            val minFocus = characteristics.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f
            val manualSensor = characteristics.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)
                ?.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR) == true
            val focus = lastFocusDistance
            var focusMode = "fixed"
            if (minFocus > 0f && manualSensor && focus != null) {
                request.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_OFF)
                request.set(CaptureRequest.LENS_FOCUS_DISTANCE, focus)
                focusMode = "manual $focus dpt"
            } else if (minFocus > 0f) {
                // No manual focus: an AF trigger in continuous-video mode locks focus where it is.
                request.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_START)
                session?.capture(request.build(), null, handler)
                request.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_IDLE)
                afTriggered = true
                focusMode = "af_trigger"
            }
            submit()
            logger.info(TAG, "3A locked after $elapsedMs ms (converged=$converged, focus=$focusMode).")
        }

        /**
         * Control thread: a `record.prepare` for [sessionId] reuses this pipeline, so 3A warms up and
         * locks again for it instead of keeping what the preview (or the last session) locked.
         */
        fun rewarm(sessionId: String) {
            warmedFor = sessionId
            handler.post {
                try {
                    unlock(sessionId)
                } catch (error: Exception) {
                    logger.warn(TAG, "3A warm-up for $sessionId failed; keeping the old lock.", error)
                }
            }
        }

        /** Runs on [handler]: back to open-time 3A; [warmupCallback] then locks again. */
        private fun unlock(sessionId: String) {
            val request = builder ?: return
            request.set(CaptureRequest.CONTROL_AE_LOCK, false)
            request.set(CaptureRequest.CONTROL_AWB_LOCK, false)
            request.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
            if (afTriggered) {
                request.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_CANCEL)
                session?.capture(request.build(), null, handler)
                request.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_IDLE)
                afTriggered = false
            }
            lastFocusDistance = null
            openedAtMs = SystemClock.elapsedRealtime()
            locked = false
            submit()
            logger.info(TAG, "3A unlocked to warm up again for $sessionId.")
        }

        fun setTorch(on: Boolean) {
            handler.post { torchOn = on }
            resubmit("Torch")
        }

        fun close() {
            try {
                session?.stopRepeating()
            } catch (error: Exception) {
                logger.warn(TAG, "stopRepeating failed.", error)
            }
            session?.close()
            device?.close()
            session = null
            device = null
            encoders.values.forEach { it.release() }
            encoders.clear()
            thread.quitSafely()
            logger.info(TAG, "Camera closed.")
        }

        private fun pickSize(sizes: List<Size>, wanted: Pair<Int, Int>): Size {
            val (width, height) = wanted
            sizes.firstOrNull { it.width == width && it.height == height }?.let { return it }
            return sizes
                .filter { it.width * ASPECT_H == it.height * ASPECT_W && it.width <= width }
                .maxByOrNull { it.width }
                ?: sizes.minByOrNull { abs(it.width - width) }
                ?: Size(width, height)
        }

        inner class VideoEncoder(private val tier: String, size: Size, fps: Int, kbps: Int) {
            private val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            val surface: Surface
            private val info = MediaCodec.BufferInfo()

            @Volatile
            private var running = true
            private val drainThread = Thread({ drain() }, "CourtEncoder-$tier")

            init {
                configure(videoFormat(size, fps, kbps, withProfile = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q))
                surface = codec.createInputSurface()
            }

            private fun configure(format: MediaFormat) {
                try {
                    codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                } catch (error: MediaCodec.CodecException) {
                    if (!format.containsKey(MediaFormat.KEY_PROFILE)) {
                        throw error
                    }
                    codec.reset()
                    format.removeKeyCompat(MediaFormat.KEY_PROFILE)
                    codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                }
            }

            fun start() {
                codec.start()
                drainThread.start()
            }

            fun requestSyncFrame() {
                try {
                    codec.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) })
                } catch (error: IllegalStateException) {
                    logger.warn(TAG, "Sync-frame request on $tier failed.", error)
                }
            }

            private var first = true

            private fun drain() {
                var endOfStream = false
                while (running && !endOfStream) {
                    // null: the codec was released under us, so the session is stopping.
                    val index = dequeueOrNull() ?: break
                    if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        configFromFormat(codec.outputFormat)?.let { publishConfig(it) }
                    } else if (index >= 0) {
                        endOfStream = handleOutput(index)
                    }
                }
            }

            private fun dequeueOrNull(): Int? = try {
                codec.dequeueOutputBuffer(info, DRAIN_TIMEOUT_US)
            } catch (ignored: IllegalStateException) {
                null
            }

            /** Publishes one output buffer; true at end of stream. */
            private fun handleOutput(index: Int): Boolean {
                val buffer = codec.getOutputBuffer(index)
                if (buffer != null && info.size > 0) {
                    val bytes = ByteArray(info.size)
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    buffer.get(bytes)
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                        publishConfig(bytes)
                    } else {
                        publishFrame(bytes)
                    }
                }
                codec.releaseOutputBuffer(index, false)
                return info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
            }

            private fun publishFrame(bytes: ByteArray) {
                if (first) {
                    first = false
                    if (ptsClock.check(info.presentationTimeUs)) {
                        logger.info(TAG, "Sensor timestamps follow the other clock; switched pts timebase.")
                    }
                }
                onEncodedFrame(
                    tier,
                    info.presentationTimeUs,
                    bytes,
                    info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0,
                )
            }

            private fun publishConfig(config: ByteArray) {
                storeConfig(tier, config)
                onEncoderConfig(tier, config)
            }

            fun release() {
                running = false
                drainThread.join(RELEASE_JOIN_MS)
                runCatching { codec.stop() }
                codec.release()
                surface.release()
            }
        }
    }

    /** 48 kHz mono AAC-LC from the mic, pts on the same clock as the video encoders. */
    private inner class AudioPipeline(
        private val ptsClock: PtsClock,
        private val sink: (ptsUs: Long, aacRaw: ByteArray) -> Unit,
    ) {
        @Volatile
        private var running = true
        private val thread = Thread({ loop() }, "CourtAudio")

        fun start() {
            thread.start()
        }

        fun stop() {
            running = false
            thread.join(RELEASE_JOIN_MS)
        }

        private var baseUs = -1L
        private var samples = 0L

        @SuppressLint("MissingPermission")
        private fun openRecord(): AudioRecord? {
            val minBuffer = AudioRecord.getMinBufferSize(
                AUDIO_SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            val bufferBytes = max(minBuffer * 2, AUDIO_CHUNK_BYTES * AUDIO_BUFFER_CHUNKS)
            val record = AudioRecord(
                MediaRecorder.AudioSource.CAMCORDER,
                AUDIO_SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferBytes,
            )
            if (record.state != AudioRecord.STATE_INITIALIZED) {
                logger.warn(TAG, "AudioRecord did not initialize; continuing video only.")
                record.release()
                return null
            }
            return record
        }

        private fun loop() {
            val record = openRecord() ?: return
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, AUDIO_SAMPLE_RATE, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, AUDIO_BIT_RATE)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, AUDIO_CHUNK_BYTES)
            }
            val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
            record.startRecording()
            val info = MediaCodec.BufferInfo()
            try {
                while (running) {
                    feedInput(encoder, record)
                    drainOutput(encoder, info)
                }
            } catch (error: IllegalStateException) {
                logger.warn(TAG, "Audio pipeline stopped.", error)
            } finally {
                runCatching { record.stop() }
                record.release()
                runCatching { encoder.stop() }
                encoder.release()
            }
        }

        /** Moves one chunk of PCM into the encoder, stamped from the first read on the shared pts clock. */
        private fun feedInput(encoder: MediaCodec, record: AudioRecord) {
            val inputIndex = encoder.dequeueInputBuffer(DRAIN_TIMEOUT_US)
            if (inputIndex < 0) {
                return
            }
            val input = encoder.getInputBuffer(inputIndex)
            val read = if (input == null) 0 else record.read(input, min(input.remaining(), AUDIO_CHUNK_BYTES))
            if (read > 0) {
                val readSamples = read / 2L
                if (baseUs < 0) {
                    baseUs = ptsClock.nowUs() - readSamples * 1_000_000L / AUDIO_SAMPLE_RATE
                }
                encoder.queueInputBuffer(inputIndex, 0, read, baseUs + samples * 1_000_000L / AUDIO_SAMPLE_RATE, 0)
                samples += readSamples
            } else {
                encoder.queueInputBuffer(inputIndex, 0, 0, 0, 0)
            }
        }

        private fun drainOutput(encoder: MediaCodec, info: MediaCodec.BufferInfo) {
            var outputIndex = encoder.dequeueOutputBuffer(info, 0)
            while (outputIndex >= 0) {
                val output = encoder.getOutputBuffer(outputIndex)
                if (output != null && info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                    emit(output, info)
                }
                encoder.releaseOutputBuffer(outputIndex, false)
                outputIndex = encoder.dequeueOutputBuffer(info, 0)
            }
        }

        private fun emit(output: ByteBuffer, info: MediaCodec.BufferInfo) {
            val bytes = ByteArray(info.size)
            output.position(info.offset)
            output.limit(info.offset + info.size)
            output.get(bytes)
            try {
                sink(info.presentationTimeUs, bytes)
            } catch (error: IOException) {
                logger.warn(TAG, "Audio write failed.", error)
            }
        }
    }

    companion object {
        private const val TAG = "CourtRecorder"
        private const val OPEN_TIMEOUT_MS = 5_000L
        private const val WARMUP_MIN_MS = 1_500L
        private const val WARMUP_MAX_MS = 4_000L
        private const val MAX_STOP_WAIT_MS = 10_000L
        private const val STOP_GRACE_MS = 300L
        private const val DRAIN_TIMEOUT_US = 10_000L
        private const val RELEASE_JOIN_MS = 1_000L
        private const val NS_PER_US = 1_000L
        private const val I_FRAME_INTERVAL_S = 2
        private const val AUDIO_SAMPLE_RATE = 48_000
        private const val AUDIO_BIT_RATE = 96_000
        private const val AUDIO_CHUNK_BYTES = 4_096
        private const val AUDIO_BUFFER_CHUNKS = 4
        private const val ASPECT_W = 16
        private const val ASPECT_H = 9

        fun backCameraId(manager: CameraManager): String = manager.cameraIdList.firstOrNull { id ->
            manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) ==
                CameraCharacteristics.LENS_FACING_BACK
        } ?: manager.cameraIdList.firstOrNull() ?: error("No camera.")

        private fun videoFormat(size: Size, fps: Int, kbps: Int, withProfile: Boolean): MediaFormat =
            MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, size.width, size.height).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, kbps * 1_000)
                setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL_S)
                // The TS muxer writes PTS only (PTS = DTS): no B-frames.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
                }
                if (withProfile) {
                    setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
                }
            }

        /** SPS + PPS (Annex-B) from `csd-0`/`csd-1`. */
        private fun configFromFormat(format: MediaFormat): ByteArray? {
            val parts = listOf("csd-0", "csd-1").mapNotNull { key ->
                format.getByteBuffer(key)?.let { buffer ->
                    val copy = buffer.duplicate()
                    ByteArray(copy.remaining()).also { copy.get(it) }
                }
            }
            if (parts.isEmpty()) {
                return null
            }
            return parts.reduce { acc, bytes -> acc + bytes }
        }

        private fun MediaFormat.removeKeyCompat(key: String) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                removeKey(key)
            } else {
                setInteger(key, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
            }
        }
    }
}
