package com.amaia23.hydracam.fixedcamera

import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.max

class FixedCameraLocalHlsRecorder(
    private val outputRoot: File,
    private val clockMillis: () -> Long = { System.currentTimeMillis() },
) {
    data class Request(
        val sessionGuid: String,
        val deviceId: String,
        val recordingId: String,
        val cameraId: String? = null,
        val targetDurationSeconds: Int,
        val width: Int,
        val height: Int,
        val frameRate: Int,
        val includeAudio: Boolean,
    )

    enum class State(val wireValue: String) {
        RECORDING("recording"),
        FINALIZED("finalized"),
    }

    data class Result(
        val recordingId: String,
        val recordingDirectoryPath: String,
        val state: State,
        val playlistPath: String? = null,
        val initPath: String? = null,
        val chunkPaths: List<String> = emptyList(),
        val durationSeconds: Double? = null,
        val targetDurationSeconds: Int? = null,
        val startedAt: String? = null,
        val finalizedAt: String? = null,
        val nativeTimingMetadataJson: String? = null,
    ) {
        fun toMap(): Map<String, Any?> =
            mapOf(
                "recordingId" to recordingId,
                "recordingDirectoryPath" to recordingDirectoryPath,
                "state" to state.wireValue,
                "playlistPath" to playlistPath,
                "initPath" to initPath,
                "chunkPaths" to chunkPaths,
                "durationSeconds" to durationSeconds,
                "targetDurationSeconds" to targetDurationSeconds,
                "startedAt" to startedAt,
                "finalizedAt" to finalizedAt,
                "nativeTimingMetadataJson" to nativeTimingMetadataJson,
            ).filterValues { it != null }
    }

    private data class ActiveRecording(
        val request: Request,
        val directory: File,
        val startedAtMillis: Long,
        val startedAt: String,
    )

    private val activeRecordings = mutableMapOf<String, ActiveRecording>()

    fun start(request: Request): Result {
        validate(request)
        require(!activeRecordings.containsKey(request.recordingId)) {
            "Recording ${request.recordingId} is already active."
        }

        val directory = File(outputRoot, safeFileName(request.recordingId))
        directory.mkdirs()
        val startedAtMillis = clockMillis()
        val startedAt = isoTimestamp(startedAtMillis)
        activeRecordings[request.recordingId] = ActiveRecording(
            request = request,
            directory = directory,
            startedAtMillis = startedAtMillis,
            startedAt = startedAt,
        )

        return Result(
            recordingId = request.recordingId,
            recordingDirectoryPath = directory.absolutePath,
            state = State.RECORDING,
            targetDurationSeconds = request.targetDurationSeconds,
            startedAt = startedAt,
        )
    }

    fun stop(recordingId: String): Result {
        val active = activeRecordings.remove(recordingId)
            ?: error("Recording $recordingId is not active.")
        val finalizedAtMillis = clockMillis()
        val finalizedAt = isoTimestamp(finalizedAtMillis)
        val request = active.request
        val directory = active.directory
        val targetDurationSeconds = max(1, request.targetDurationSeconds)
        val initFile = File(directory, "init.mp4")
        val playlistFile = File(directory, "playlist.m3u8")

        FixedCameraMp4InitSegmentWriter.write(
            file = initFile,
            width = request.width,
            height = request.height,
            avcConfig = SYNTHETIC_AVC_CONFIG,
            sampleRate = AUDIO_SAMPLE_RATE,
            channelCount = if (request.includeAudio) 1 else 0,
            audioBitRate = AUDIO_BIT_RATE,
        )

        val segments = (0 until SYNTHETIC_SEGMENT_COUNT).map { index ->
            val chunkFileName = FixedCameraHlsPlaylistWriter.chunkFileName(
                request.deviceId,
                request.recordingId,
                index,
            )
            val chunkFile = File(directory, chunkFileName)
            FixedCameraMp4FragmentWriter.write(
                file = chunkFile,
                sequenceNumber = (index + 1).toLong(),
                fragments = trackFragments(
                    index = index,
                    targetDurationSeconds = targetDurationSeconds,
                    includeAudio = request.includeAudio,
                ),
            )
            FixedCameraHlsPlaylistWriter.Segment(
                fileName = chunkFileName,
                durationSeconds = targetDurationSeconds.toDouble(),
            )
        }

        FixedCameraHlsPlaylistWriter.write(
            file = playlistFile,
            initFileName = initFile.name,
            segments = segments,
            isFinal = true,
        )

        val durationSeconds = segments.sumOf { it.durationSeconds }
        val chunkPaths = segments.map { File(directory, it.fileName).absolutePath }
        return Result(
            recordingId = request.recordingId,
            recordingDirectoryPath = directory.absolutePath,
            state = State.FINALIZED,
            playlistPath = playlistFile.absolutePath,
            initPath = initFile.absolutePath,
            chunkPaths = chunkPaths,
            durationSeconds = durationSeconds,
            targetDurationSeconds = targetDurationSeconds,
            startedAt = active.startedAt,
            finalizedAt = finalizedAt,
            nativeTimingMetadataJson = nativeTimingMetadataJson(
                request = request,
                chunkCount = chunkPaths.size,
                durationSeconds = durationSeconds,
                startedAt = active.startedAt,
                finalizedAt = finalizedAt,
                elapsedMillis = finalizedAtMillis - active.startedAtMillis,
            ),
        )
    }

    private fun trackFragments(
        index: Int,
        targetDurationSeconds: Int,
        includeAudio: Boolean,
    ): List<FixedCameraMp4FragmentWriter.TrackFragment> {
        val videoDuration = targetDurationSeconds * VIDEO_TIMESCALE
        val audioDuration = targetDurationSeconds * AUDIO_SAMPLE_RATE
        val videoFragment = FixedCameraMp4FragmentWriter.TrackFragment(
            trackId = VIDEO_TRACK_ID,
            baseMediaDecodeTime = index.toLong() * videoDuration,
            samples = listOf(
                FixedCameraMp4FragmentWriter.Sample.video(
                    duration = videoDuration,
                    data = syntheticVideoSample(index),
                    isSyncSample = true,
                ),
            ),
        )
        if (!includeAudio) {
            return listOf(videoFragment)
        }
        val audioFragment = FixedCameraMp4FragmentWriter.TrackFragment(
            trackId = AUDIO_TRACK_ID,
            baseMediaDecodeTime = index.toLong() * audioDuration,
            samples = listOf(
                FixedCameraMp4FragmentWriter.Sample.audio(
                    duration = audioDuration,
                    data = syntheticAudioSample(index),
                ),
            ),
        )
        return listOf(videoFragment, audioFragment)
    }

    private fun validate(request: Request) {
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

    private fun nativeTimingMetadataJson(
        request: Request,
        chunkCount: Int,
        durationSeconds: Double,
        startedAt: String,
        finalizedAt: String,
        elapsedMillis: Long,
    ): String =
        buildString {
            append("{")
            appendJsonField("recorderMode", "synthetic_local")
            append(",")
            appendJsonField("syncConfidence", "synthetic")
            append(",")
            appendJsonField("sessionGuid", request.sessionGuid)
            append(",")
            appendJsonField("deviceId", request.deviceId)
            append(",")
            appendJsonField("recordingId", request.recordingId)
            append(",")
            appendJsonField("startedAt", startedAt)
            append(",")
            appendJsonField("finalizedAt", finalizedAt)
            append(",\"durationSeconds\":")
            append("%.3f".format(Locale.US, durationSeconds))
            append(",\"targetDurationSeconds\":")
            append(request.targetDurationSeconds)
            append(",\"chunkCount\":")
            append(chunkCount)
            append(",\"elapsedMillis\":")
            append(elapsedMillis)
            append("}")
        }

    private fun StringBuilder.appendJsonField(name: String, value: String) {
        append("\"")
        append(name)
        append("\":\"")
        append(value.replace("\\", "\\\\").replace("\"", "\\\""))
        append("\"")
    }

    private fun syntheticVideoSample(index: Int): ByteArray =
        byteArrayOf(
            0,
            0,
            0,
            6,
            0x65,
            0x88.toByte(),
            0x84.toByte(),
            (0x21 + index).toByte(),
            0xA0.toByte(),
            0x10,
        )

    private fun syntheticAudioSample(index: Int): ByteArray =
        byteArrayOf(
            0x21,
            0x10,
            (0x56 + index).toByte(),
            0xE5.toByte(),
        )

    private fun safeFileName(value: String): String =
        value.replace(Regex("[^A-Za-z0-9._-]"), "_")

    private fun isoTimestamp(millis: Long): String =
        ISO_FORMAT.get()!!.format(Date(millis))

    private companion object {
        const val SYNTHETIC_SEGMENT_COUNT = 2
        const val VIDEO_TRACK_ID = 1
        const val AUDIO_TRACK_ID = 2
        const val VIDEO_TIMESCALE = 90_000
        const val AUDIO_SAMPLE_RATE = 48_000
        const val AUDIO_BIT_RATE = 128_000

        val SYNTHETIC_SPS = byteArrayOf(
            0x67,
            0x64,
            0x00,
            0x1F,
            0xAC.toByte(),
            0xD9.toByte(),
            0x40,
            0x78,
        )
        val SYNTHETIC_PPS = byteArrayOf(
            0x68,
            0xEE.toByte(),
            0x3C,
            0x80.toByte(),
        )
        val SYNTHETIC_AVC_CONFIG: ByteArray = FixedCameraH264AvcConfig.fromCsd(
            csd0 = annexB(SYNTHETIC_SPS),
            csd1 = annexB(SYNTHETIC_PPS),
        )

        val ISO_FORMAT = object : ThreadLocal<SimpleDateFormat>() {
            override fun initialValue(): SimpleDateFormat =
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }
        }

        private fun annexB(nalUnit: ByteArray): ByteArray =
            byteArrayOf(0x00, 0x00, 0x00, 0x01) + nalUnit
    }
}
