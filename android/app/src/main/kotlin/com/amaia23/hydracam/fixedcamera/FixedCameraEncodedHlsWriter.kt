package com.amaia23.hydracam.fixedcamera

import java.io.File
import java.util.Locale
import kotlin.math.max

object FixedCameraEncodedHlsWriter {
    data class VideoSample(
        val presentationTimeUs: Long,
        val data: ByteArray,
        val isSyncSample: Boolean,
    )

    data class AudioSample(
        val presentationTimeUs: Long,
        val data: ByteArray,
        val duration: Int = AAC_SAMPLE_DURATION,
    )

    fun writeFinalizedBundle(
        request: FixedCameraLocalHlsRecorder.Request,
        outputDirectory: File,
        startedAt: String,
        finalizedAt: String,
        elapsedMillis: Long,
        avcConfig: ByteArray,
        videoSamples: List<VideoSample>,
        audioSamples: List<AudioSample>,
        recorderMode: String,
        syncConfidence: String,
    ): FixedCameraLocalHlsRecorder.Result {
        require(videoSamples.isNotEmpty()) {
            "At least one encoded video sample is required."
        }

        outputDirectory.mkdirs()
        val targetDurationSeconds = max(1, request.targetDurationSeconds)
        val targetDurationUs = targetDurationSeconds * MICROSECONDS_PER_SECOND
        val normalized = normalizeSamples(videoSamples, audioSamples)
        val segments = encodedSegments(
            normalizedVideoSamples = normalized.videoSamples,
            normalizedAudioSamples = normalized.audioSamples,
            targetDurationUs = targetDurationUs,
            frameRate = request.frameRate,
            includeAudio = request.includeAudio,
        )
        require(segments.isNotEmpty()) {
            "At least one HLS segment is required."
        }

        val initFile = File(outputDirectory, INIT_FILE_NAME)
        val playlistFile = File(outputDirectory, PLAYLIST_FILE_NAME)
        FixedCameraMp4InitSegmentWriter.write(
            file = initFile,
            width = request.width,
            height = request.height,
            avcConfig = avcConfig,
            sampleRate = AUDIO_SAMPLE_RATE,
            channelCount = if (request.includeAudio) 1 else 0,
            audioBitRate = AUDIO_BIT_RATE,
        )

        val playlistSegments = segments.mapIndexed { index, segment ->
            val chunkFileName = FixedCameraHlsPlaylistWriter.chunkFileName(
                request.deviceId,
                request.recordingId,
                index,
            )
            FixedCameraMp4FragmentWriter.write(
                file = File(outputDirectory, chunkFileName),
                sequenceNumber = (index + 1).toLong(),
                fragments = segment.fragments,
            )
            FixedCameraHlsPlaylistWriter.Segment(
                fileName = chunkFileName,
                durationSeconds = segment.durationSeconds,
            )
        }

        FixedCameraHlsPlaylistWriter.write(
            file = playlistFile,
            initFileName = initFile.name,
            segments = playlistSegments,
            isFinal = true,
        )

        val chunkPaths = playlistSegments.map { File(outputDirectory, it.fileName).absolutePath }
        val durationSeconds = playlistSegments.sumOf { it.durationSeconds }
        return FixedCameraLocalHlsRecorder.Result(
            recordingId = request.recordingId,
            recordingDirectoryPath = outputDirectory.absolutePath,
            state = FixedCameraLocalHlsRecorder.State.FINALIZED,
            playlistPath = playlistFile.absolutePath,
            initPath = initFile.absolutePath,
            chunkPaths = chunkPaths,
            durationSeconds = durationSeconds,
            targetDurationSeconds = targetDurationSeconds,
            startedAt = startedAt,
            finalizedAt = finalizedAt,
            nativeTimingMetadataJson = nativeTimingMetadataJson(
                request = request,
                chunkCount = chunkPaths.size,
                durationSeconds = durationSeconds,
                startedAt = startedAt,
                finalizedAt = finalizedAt,
                elapsedMillis = elapsedMillis,
                recorderMode = recorderMode,
                syncConfidence = syncConfidence,
                videoSampleCount = videoSamples.size,
                audioSampleCount = audioSamples.size,
            ),
        )
    }

    private data class NormalizedSamples(
        val videoSamples: List<VideoSample>,
        val audioSamples: List<AudioSample>,
    )

    private data class EncodedSegment(
        val fragments: List<FixedCameraMp4FragmentWriter.TrackFragment>,
        val durationSeconds: Double,
    )

    private fun normalizeSamples(
        videoSamples: List<VideoSample>,
        audioSamples: List<AudioSample>,
    ): NormalizedSamples {
        val sortedVideo = videoSamples.sortedBy { it.presentationTimeUs }
        val sortedAudio = audioSamples.sortedBy { it.presentationTimeUs }
        val firstPresentationTimeUs = listOfNotNull(
            sortedVideo.firstOrNull()?.presentationTimeUs,
            sortedAudio.firstOrNull()?.presentationTimeUs,
        ).minOrNull() ?: 0

        return NormalizedSamples(
            videoSamples = sortedVideo.map {
                it.copy(presentationTimeUs = it.presentationTimeUs - firstPresentationTimeUs)
            },
            audioSamples = sortedAudio.map {
                it.copy(presentationTimeUs = it.presentationTimeUs - firstPresentationTimeUs)
            },
        )
    }

    private fun encodedSegments(
        normalizedVideoSamples: List<VideoSample>,
        normalizedAudioSamples: List<AudioSample>,
        targetDurationUs: Long,
        frameRate: Int,
        includeAudio: Boolean,
    ): List<EncodedSegment> {
        val lastPresentationTimeUs = listOfNotNull(
            normalizedVideoSamples.lastOrNull()?.presentationTimeUs,
            normalizedAudioSamples.lastOrNull()?.presentationTimeUs,
        ).maxOrNull() ?: 0
        val segmentCount = (lastPresentationTimeUs / targetDurationUs).toInt() + 1
        val videoSamplesWithDuration = videoSamplesWithDuration(
            samples = normalizedVideoSamples,
            frameRate = frameRate,
        )

        return (0 until segmentCount).mapNotNull { segmentIndex ->
            val segmentStartUs = segmentIndex * targetDurationUs
            val segmentEndUs = segmentStartUs + targetDurationUs
            val videoSamples = videoSamplesWithDuration
                .filter { it.sample.presentationTimeUs in segmentStartUs until segmentEndUs }
            val audioSamples = normalizedAudioSamples
                .filter { it.presentationTimeUs in segmentStartUs until segmentEndUs }

            val fragments = mutableListOf<FixedCameraMp4FragmentWriter.TrackFragment>()
            if (videoSamples.isNotEmpty()) {
                fragments += FixedCameraMp4FragmentWriter.TrackFragment(
                    trackId = VIDEO_TRACK_ID,
                    baseMediaDecodeTime = videoSamples.first()
                        .sample.presentationTimeUs.toVideoTimescale(),
                    samples = videoSamples.map { videoSample ->
                        FixedCameraMp4FragmentWriter.Sample.video(
                            duration = videoSample.durationUs.toVideoDuration(),
                            data = videoSample.sample.data,
                            isSyncSample = videoSample.sample.isSyncSample,
                        )
                    },
                )
            }
            if (includeAudio && audioSamples.isNotEmpty()) {
                fragments += FixedCameraMp4FragmentWriter.TrackFragment(
                    trackId = AUDIO_TRACK_ID,
                    baseMediaDecodeTime = audioSamples.first()
                        .presentationTimeUs.toAudioTimescale(),
                    samples = audioSamples.map { audioSample ->
                        FixedCameraMp4FragmentWriter.Sample.audio(
                            duration = audioSample.duration,
                            data = audioSample.data,
                        )
                    },
                )
            }
            if (fragments.isEmpty()) {
                return@mapNotNull null
            }

            val segmentDurationUs = maxSegmentDurationUs(
                segmentStartUs = segmentStartUs,
                videoSamples = videoSamples,
                audioSamples = audioSamples,
                includeAudio = includeAudio,
            )
            EncodedSegment(
                fragments = fragments,
                durationSeconds = segmentDurationUs.toDouble() / MICROSECONDS_PER_SECOND,
            )
        }
    }

    private data class VideoSampleWithDuration(
        val sample: VideoSample,
        val durationUs: Long,
    )

    private fun videoSamplesWithDuration(
        samples: List<VideoSample>,
        frameRate: Int,
    ): List<VideoSampleWithDuration> {
        val fallbackDurationUs = max(1, MICROSECONDS_PER_SECOND / max(1, frameRate))
        return samples.mapIndexed { index, sample ->
            val nextSample = samples.getOrNull(index + 1)
            val durationUs = nextSample
                ?.let { max(1, it.presentationTimeUs - sample.presentationTimeUs) }
                ?: fallbackDurationUs
            VideoSampleWithDuration(sample = sample, durationUs = durationUs)
        }
    }

    private fun maxSegmentDurationUs(
        segmentStartUs: Long,
        videoSamples: List<VideoSampleWithDuration>,
        audioSamples: List<AudioSample>,
        includeAudio: Boolean,
    ): Long {
        val videoEndUs = videoSamples.maxOfOrNull {
            it.sample.presentationTimeUs + it.durationUs
        }
        val audioEndUs = if (includeAudio) {
            audioSamples.maxOfOrNull {
                it.presentationTimeUs + it.duration.toAudioDurationUs()
            }
        } else {
            null
        }
        return max(
            1,
            (listOfNotNull(videoEndUs, audioEndUs).maxOrNull() ?: segmentStartUs) -
                segmentStartUs,
        )
    }

    private fun nativeTimingMetadataJson(
        request: FixedCameraLocalHlsRecorder.Request,
        chunkCount: Int,
        durationSeconds: Double,
        startedAt: String,
        finalizedAt: String,
        elapsedMillis: Long,
        recorderMode: String,
        syncConfidence: String,
        videoSampleCount: Int,
        audioSampleCount: Int,
    ): String =
        buildString {
            append("{")
            appendJsonField("recorderMode", recorderMode)
            append(",")
            appendJsonField("syncConfidence", syncConfidence)
            append(",")
            appendJsonField("sessionGuid", request.sessionGuid)
            append(",")
            appendJsonField("deviceId", request.deviceId)
            append(",")
            appendJsonField("recordingId", request.recordingId)
            request.cameraId?.let { cameraId ->
                append(",")
                appendJsonField("cameraId", cameraId)
            }
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
            append(",\"videoSampleCount\":")
            append(videoSampleCount)
            append(",\"audioSampleCount\":")
            append(audioSampleCount)
            append("}")
        }

    private fun StringBuilder.appendJsonField(name: String, value: String) {
        append("\"")
        append(name)
        append("\":\"")
        append(value.replace("\\", "\\\\").replace("\"", "\\\""))
        append("\"")
    }

    private fun Long.toVideoTimescale(): Long =
        this * VIDEO_TIMESCALE / MICROSECONDS_PER_SECOND

    private fun Long.toVideoDuration(): Int =
        max(1, toVideoTimescale().toInt())

    private fun Long.toAudioTimescale(): Long =
        this * AUDIO_SAMPLE_RATE / MICROSECONDS_PER_SECOND

    private fun Int.toAudioDurationUs(): Long =
        this.toLong() * MICROSECONDS_PER_SECOND / AUDIO_SAMPLE_RATE

    private const val INIT_FILE_NAME = "init.mp4"
    private const val PLAYLIST_FILE_NAME = "playlist.m3u8"
    private const val VIDEO_TRACK_ID = 1
    private const val AUDIO_TRACK_ID = 2
    private const val VIDEO_TIMESCALE = 90_000
    private const val AUDIO_SAMPLE_RATE = 48_000
    private const val AUDIO_BIT_RATE = 128_000
    private const val AAC_SAMPLE_DURATION = 1_024
    private const val MICROSECONDS_PER_SECOND = 1_000_000L
}
