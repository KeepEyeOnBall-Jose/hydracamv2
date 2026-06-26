package com.amaia23.hydracam.fixedcamera

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.Collections
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max

class FixedCameraCamera2HlsRecorder(
    private val context: Context,
    private val outputRoot: File,
    private val clockMillis: () -> Long = { System.currentTimeMillis() },
) {
    private data class ActiveRecording(
        val request: FixedCameraLocalHlsRecorder.Request,
        val session: CameraRecordingSession,
    )

    private val activeRecordings = mutableMapOf<String, ActiveRecording>()

    fun start(
        request: FixedCameraLocalHlsRecorder.Request,
    ): FixedCameraLocalHlsRecorder.Result {
        validate(request)
        require(!activeRecordings.containsKey(request.recordingId)) {
            "Recording ${request.recordingId} is already active."
        }

        val cameraId = request.cameraId ?: defaultCameraId()
        val directory = File(outputRoot, safeFileName(request.recordingId))
        val startedAtMillis = clockMillis()
        val startedAt = isoTimestamp(startedAtMillis)
        val session = CameraRecordingSession(
            context = context,
            cameraId = cameraId,
            request = request.copy(cameraId = cameraId),
            directory = directory,
            startedAtMillis = startedAtMillis,
            startedAt = startedAt,
        )
        try {
            session.start()
        } catch (error: Exception) {
            session.release()
            throw error
        }
        activeRecordings[request.recordingId] = ActiveRecording(
            request = request.copy(cameraId = cameraId),
            session = session,
        )

        return FixedCameraLocalHlsRecorder.Result(
            recordingId = request.recordingId,
            recordingDirectoryPath = directory.absolutePath,
            state = FixedCameraLocalHlsRecorder.State.RECORDING,
            targetDurationSeconds = request.targetDurationSeconds,
            startedAt = startedAt,
        )
    }

    fun stop(recordingId: String): FixedCameraLocalHlsRecorder.Result {
        val active = activeRecordings.remove(recordingId)
            ?: error("Recording $recordingId is not active.")
        return active.session.stop(finalizedAtMillis = clockMillis())
    }

    fun hasCameraHardware(): Boolean =
        cameraIds().isNotEmpty()

    fun cameraIds(): List<String> =
        try {
            cameraManager().cameraIdList.toList()
        } catch (error: Exception) {
            emptyList()
        }

    private inner class CameraRecordingSession(
        val context: Context,
        val cameraId: String,
        val request: FixedCameraLocalHlsRecorder.Request,
        val directory: File,
        val startedAtMillis: Long,
        val startedAt: String,
    ) {
        private val stopRequested = AtomicBoolean(false)
        private val aborted = AtomicBoolean(false)
        private val cameraStarted = CountDownLatch(1)
        private val videoSamples = Collections.synchronizedList(
            mutableListOf<FixedCameraEncodedHlsWriter.VideoSample>(),
        )
        private val audioSamples = Collections.synchronizedList(
            mutableListOf<FixedCameraEncodedHlsWriter.AudioSample>(),
        )

        private lateinit var cameraThread: HandlerThread
        private lateinit var cameraHandler: Handler
        private lateinit var videoEncoder: MediaCodec
        private var audioEncoder: MediaCodec? = null
        private var audioRecord: AudioRecord? = null
        private var encoderInputSurface: Surface? = null
        private var cameraDevice: CameraDevice? = null
        private var captureSession: CameraCaptureSession? = null
        private var videoDrainThread: Thread? = null
        private var audioThread: Thread? = null
        @Volatile private var startupError: Exception? = null
        @Volatile private var videoOutputFormat: MediaFormat? = null

        fun start() {
            requirePermission(Manifest.permission.CAMERA, "Camera")
            if (request.includeAudio) {
                requirePermission(Manifest.permission.RECORD_AUDIO, "Microphone")
            }

            directory.mkdirs()
            cameraThread = HandlerThread("HydraCamFixedCamera-$cameraId").apply { start() }
            cameraHandler = Handler(cameraThread.looper)
            videoEncoder = createVideoEncoder(request)
            encoderInputSurface = videoEncoder.createInputSurface()
            videoEncoder.start()
            videoDrainThread = Thread(::drainVideoEncoder, "HydraCamFixedCameraVideoDrain")
                .also { it.start() }

            if (request.includeAudio) {
                startAudioEncoding()
            }
            openCamera()

            if (!cameraStarted.await(CAMERA_START_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                throw IllegalStateException("Timed out starting Camera2 HLS recorder.")
            }
            startupError?.let { throw it }
        }

        fun stop(finalizedAtMillis: Long): FixedCameraLocalHlsRecorder.Result {
            stopRequested.set(true)
            closeCamera()
            signalVideoEndOfStream()
            videoDrainThread?.join(ENCODER_STOP_TIMEOUT_MILLIS)
            audioThread?.join(ENCODER_STOP_TIMEOUT_MILLIS)

            val finalizedAt = isoTimestamp(finalizedAtMillis)
            val format = videoOutputFormat
                ?: throw IllegalStateException("Video encoder did not report H.264 config.")
            val csd0 = format.byteArray("csd-0")
                ?: throw IllegalStateException("Video encoder did not report csd-0.")
            val avcConfig = FixedCameraH264AvcConfig.fromCsd(
                csd0 = csd0,
                csd1 = format.byteArray("csd-1"),
            )
            val encodedVideoSamples = synchronized(videoSamples) {
                videoSamples.toList()
            }
            val encodedAudioSamples = synchronized(audioSamples) {
                audioSamples.toList()
            }

            release()
            return FixedCameraEncodedHlsWriter.writeFinalizedBundle(
                request = request,
                outputDirectory = directory,
                startedAt = startedAt,
                finalizedAt = finalizedAt,
                elapsedMillis = finalizedAtMillis - startedAtMillis,
                avcConfig = avcConfig,
                videoSamples = encodedVideoSamples,
                audioSamples = encodedAudioSamples,
                recorderMode = RECORDER_MODE,
                syncConfidence = "device_clock",
            )
        }

        fun release() {
            // Signal the drain/audio loops to exit and join them BEFORE the
            // codecs are released. Otherwise a still-running drain thread can
            // call MediaCodec.dequeueOutputBuffer on a released encoder, which
            // throws IllegalStateException on that thread and crashes the whole
            // process (observed when the camera fails to open on first try).
            aborted.set(true)
            stopRequested.set(true)
            closeCamera()
            videoDrainThread?.join(ENCODER_STOP_TIMEOUT_MILLIS)
            audioThread?.join(ENCODER_STOP_TIMEOUT_MILLIS)
            runCatching { encoderInputSurface?.release() }
            runCatching { videoEncoder.stop() }
            runCatching { videoEncoder.release() }
            runCatching { audioRecord?.stop() }
            runCatching { audioRecord?.release() }
            runCatching { audioEncoder?.stop() }
            runCatching { audioEncoder?.release() }
            if (::cameraThread.isInitialized) {
                cameraThread.quitSafely()
            }
        }

        @SuppressLint("MissingPermission")
        private fun openCamera() {
            cameraManager().openCamera(
                cameraId,
                object : CameraDevice.StateCallback() {
                    override fun onOpened(camera: CameraDevice) {
                        cameraDevice = camera
                        configureCaptureSession(camera)
                    }

                    override fun onDisconnected(camera: CameraDevice) {
                        startupError = IllegalStateException("Camera $cameraId disconnected.")
                        camera.close()
                        cameraStarted.countDown()
                    }

                    override fun onError(camera: CameraDevice, error: Int) {
                        startupError = IllegalStateException(
                            "Camera $cameraId failed with error $error.",
                        )
                        camera.close()
                        cameraStarted.countDown()
                    }
                },
                cameraHandler,
            )
        }

        private fun configureCaptureSession(camera: CameraDevice) {
            val surface = encoderInputSurface
                ?: error("Video encoder input surface is missing.")
            camera.createCaptureSession(
                listOf(surface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        captureSession = session
                        try {
                            val requestBuilder = camera.createCaptureRequest(
                                CameraDevice.TEMPLATE_RECORD,
                            )
                            requestBuilder.addTarget(surface)
                            requestBuilder.set(
                                CaptureRequest.CONTROL_MODE,
                                CaptureRequest.CONTROL_MODE_AUTO,
                            )
                            requestBuilder.set(
                                CaptureRequest.CONTROL_AF_MODE,
                                CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO,
                            )
                            requestBuilder.set(
                                CaptureRequest.CONTROL_AE_MODE,
                                CaptureRequest.CONTROL_AE_MODE_ON,
                            )
                            session.setRepeatingRequest(
                                requestBuilder.build(),
                                null,
                                cameraHandler,
                            )
                        } catch (error: Exception) {
                            startupError = error
                        } finally {
                            cameraStarted.countDown()
                        }
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        startupError = IllegalStateException(
                            "Camera $cameraId capture session configuration failed.",
                        )
                        cameraStarted.countDown()
                    }
                },
                cameraHandler,
            )
        }

        private fun closeCamera() {
            runCatching { captureSession?.stopRepeating() }
            runCatching { captureSession?.abortCaptures() }
            runCatching { captureSession?.close() }
            captureSession = null
            runCatching { cameraDevice?.close() }
            cameraDevice = null
        }

        private fun signalVideoEndOfStream() {
            runCatching { videoEncoder.signalEndOfInputStream() }
        }

        private fun drainVideoEncoder() {
            val bufferInfo = MediaCodec.BufferInfo()
            var outputDone = false
            while (!outputDone) {
                if (aborted.get()) {
                    return
                }
                try {
                    when (val outputIndex =
                        videoEncoder.dequeueOutputBuffer(bufferInfo, CODEC_TIMEOUT_US)) {
                        MediaCodec.INFO_TRY_AGAIN_LATER -> {
                            if (stopRequested.get()) {
                                Thread.yield()
                            }
                        }
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            videoOutputFormat = videoEncoder.outputFormat
                        }
                        else -> {
                            if (outputIndex >= 0) {
                                val outputBuffer = videoEncoder.getOutputBuffer(outputIndex)
                                if (
                                    outputBuffer != null &&
                                    bufferInfo.size > 0 &&
                                    bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0
                                ) {
                                    val sample = outputBuffer.copyBytes(bufferInfo)
                                    videoSamples += FixedCameraEncodedHlsWriter.VideoSample(
                                        presentationTimeUs = max(0, bufferInfo.presentationTimeUs),
                                        data = FixedCameraH264SampleFormatter
                                            .toLengthPrefixedSample(sample),
                                        isSyncSample = bufferInfo.flags and
                                            MediaCodec.BUFFER_FLAG_KEY_FRAME != 0,
                                    )
                                }
                                outputDone = bufferInfo.flags and
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                                videoEncoder.releaseOutputBuffer(outputIndex, false)
                            }
                        }
                    }
                } catch (error: IllegalStateException) {
                    // The encoder was released or faulted (e.g. camera open
                    // failed and the session is being torn down). Exit quietly
                    // instead of crashing this background thread.
                    return
                }
            }
        }

        @SuppressLint("MissingPermission")
        private fun startAudioEncoding() {
            val minBufferSize = AudioRecord.getMinBufferSize(
                AUDIO_SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            val bufferSize = max(minBufferSize, AUDIO_INPUT_BUFFER_BYTES)
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                AUDIO_SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
            )
            require(audioRecord?.state == AudioRecord.STATE_INITIALIZED) {
                "AudioRecord failed to initialize."
            }

            audioEncoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
                .apply {
                    val format = MediaFormat.createAudioFormat(
                        MediaFormat.MIMETYPE_AUDIO_AAC,
                        AUDIO_SAMPLE_RATE,
                        AUDIO_CHANNEL_COUNT,
                    )
                    format.setInteger(MediaFormat.KEY_BIT_RATE, AUDIO_BIT_RATE)
                    format.setInteger(
                        MediaFormat.KEY_AAC_PROFILE,
                        MediaCodecInfo.CodecProfileLevel.AACObjectLC,
                    )
                    format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, bufferSize)
                    configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                    start()
                }
            audioThread = Thread(::runAudioEncoding, "HydraCamFixedCameraAudio").also {
                it.start()
            }
        }

        private fun runAudioEncoding() {
            val record = audioRecord ?: return
            val encoder = audioEncoder ?: return
            val bufferInfo = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var submittedSamples = 0L
            record.startRecording()

            while (!outputDone) {
                if (aborted.get()) {
                    return
                }
                try {
                if (!inputDone) {
                    val inputIndex = encoder.dequeueInputBuffer(CODEC_TIMEOUT_US)
                    if (inputIndex >= 0) {
                        val inputBuffer = encoder.getInputBuffer(inputIndex)
                        inputBuffer?.clear()
                        if (stopRequested.get()) {
                            encoder.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                submittedSamples.toAudioPresentationTimeUs(),
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputDone = true
                        } else if (inputBuffer != null) {
                            val bytesRead = record.read(
                                inputBuffer,
                                minOf(inputBuffer.remaining(), AUDIO_INPUT_BUFFER_BYTES),
                            )
                            if (bytesRead > 0) {
                                val presentationTimeUs =
                                    submittedSamples.toAudioPresentationTimeUs()
                                encoder.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    bytesRead,
                                    presentationTimeUs,
                                    0,
                                )
                                submittedSamples += bytesRead / AUDIO_BYTES_PER_SAMPLE
                            }
                        }
                    }
                }

                var draining = true
                while (draining) {
                    when (val outputIndex = encoder.dequeueOutputBuffer(bufferInfo, 0)) {
                        MediaCodec.INFO_TRY_AGAIN_LATER -> draining = false
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> Unit
                        else -> {
                            if (outputIndex >= 0) {
                                val outputBuffer = encoder.getOutputBuffer(outputIndex)
                                if (
                                    outputBuffer != null &&
                                    bufferInfo.size > 0 &&
                                    bufferInfo.flags and
                                    MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0
                                ) {
                                    audioSamples += FixedCameraEncodedHlsWriter.AudioSample(
                                        presentationTimeUs = max(
                                            0,
                                            bufferInfo.presentationTimeUs,
                                        ),
                                        data = outputBuffer.copyBytes(bufferInfo),
                                    )
                                }
                                outputDone = bufferInfo.flags and
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                                encoder.releaseOutputBuffer(outputIndex, false)
                            }
                        }
                    }
                }
                } catch (error: IllegalStateException) {
                    // Audio encoder torn down during teardown; exit quietly.
                    return
                }
            }
        }
    }

    private fun createVideoEncoder(
        request: FixedCameraLocalHlsRecorder.Request,
    ): MediaCodec =
        MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).apply {
            val format = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC,
                request.width,
                request.height,
            )
            format.setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
            )
            format.setInteger(MediaFormat.KEY_BIT_RATE, videoBitRate(request))
            format.setInteger(MediaFormat.KEY_FRAME_RATE, request.frameRate)
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        }

    private fun videoBitRate(request: FixedCameraLocalHlsRecorder.Request): Int {
        val pixels = request.width * request.height
        val frameRateScale = max(1, request.frameRate) / 30.0
        return (pixels * 3.0 * frameRateScale).toInt().coerceIn(
            MIN_VIDEO_BIT_RATE,
            MAX_VIDEO_BIT_RATE,
        )
    }

    private fun validate(request: FixedCameraLocalHlsRecorder.Request) {
        require(request.sessionGuid.isNotBlank()) { "sessionGuid is required." }
        require(request.deviceId.isNotBlank()) { "deviceId is required." }
        require(request.recordingId.isNotBlank()) { "recordingId is required." }
        require(request.targetDurationSeconds > 0) {
            "targetDurationSeconds must be positive."
        }
        require(request.width > 0) { "width must be positive." }
        require(request.height > 0) { "height must be positive." }
        require(request.frameRate > 0) { "frameRate must be positive." }
    }

    private fun requirePermission(permission: String, label: String) {
        require(context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            "$label permission is required for Camera2 HLS recording."
        }
    }

    private fun defaultCameraId(): String {
        val cameraManager = cameraManager()
        return cameraManager.cameraIdList.firstOrNull { cameraId ->
            cameraManager.getCameraCharacteristics(cameraId)
                .get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
        } ?: cameraManager.cameraIdList.firstOrNull()
            ?: error("No Android camera devices are available.")
    }

    private fun cameraManager(): CameraManager =
        context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

    private fun ByteBuffer.copyBytes(bufferInfo: MediaCodec.BufferInfo): ByteArray {
        val duplicate = duplicate()
        duplicate.position(bufferInfo.offset)
        duplicate.limit(bufferInfo.offset + bufferInfo.size)
        return ByteArray(bufferInfo.size).also { duplicate.get(it) }
    }

    private fun MediaFormat.byteArray(key: String): ByteArray? =
        getByteBuffer(key)?.let { buffer ->
            val duplicate = buffer.duplicate()
            duplicate.position(0)
            ByteArray(duplicate.remaining()).also { duplicate.get(it) }
        }

    private fun Long.toAudioPresentationTimeUs(): Long =
        this * MICROSECONDS_PER_SECOND / AUDIO_SAMPLE_RATE

    private fun safeFileName(value: String): String =
        value.replace(Regex("[^A-Za-z0-9._-]"), "_")

    private fun isoTimestamp(millis: Long): String =
        ISO_FORMAT.get()!!.format(Date(millis))

    private companion object {
        const val RECORDER_MODE = "camera2_hls"
        const val CAMERA_START_TIMEOUT_SECONDS = 8L
        const val ENCODER_STOP_TIMEOUT_MILLIS = 5_000L
        const val CODEC_TIMEOUT_US = 10_000L
        const val AUDIO_SAMPLE_RATE = 48_000
        const val AUDIO_CHANNEL_COUNT = 1
        const val AUDIO_BIT_RATE = 128_000
        const val AUDIO_INPUT_BUFFER_BYTES = 4_096
        const val AUDIO_BYTES_PER_SAMPLE = 2
        const val MICROSECONDS_PER_SECOND = 1_000_000L
        const val MIN_VIDEO_BIT_RATE = 2_000_000
        const val MAX_VIDEO_BIT_RATE = 16_000_000

        val ISO_FORMAT = object : ThreadLocal<SimpleDateFormat>() {
            override fun initialValue(): SimpleDateFormat =
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }
        }
    }
}
