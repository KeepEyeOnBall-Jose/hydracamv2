package com.amaia23.hydracam.spike.preview

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicLong

/**
 * One H.264 surface encoder with its own drain thread. Counts frames and PTS gaps so recorder
 * frame loss can be compared with and without the preview encoder running.
 */
class H264Track(
    val name: String,
    private val width: Int,
    private val height: Int,
    private val fps: Int,
    private val kbps: Int,
    private val baseline: Boolean,
    private val sink: Sink,
) {
    interface Sink {
        fun onFormat(format: MediaFormat)
        /** [buffer] is only valid during the call. */
        fun onSample(buffer: ByteBuffer, info: MediaCodec.BufferInfo)
        fun onEnd() {}
    }

    private val codec: MediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    lateinit var inputSurface: Surface
        private set
    private var drainThread: Thread? = null

    val frames = AtomicLong()
    val keyframes = AtomicLong()
    val bytes = AtomicLong()
    /** Gaps between consecutive output PTS larger than 1.5x the nominal frame interval. */
    val ptsGaps = AtomicLong()
    /** Frames missing inside those gaps (gap / interval - 1, rounded). */
    val ptsGapFrames = AtomicLong()
    val maxGapUs = AtomicLong()
    @Volatile var firstPtsUs = -1L
        private set
    @Volatile var lastPtsUs = -1L
        private set
    @Volatile var configuredWith = ""
        private set

    // Preview fps from a 30 fps camera is uneven (33/67 ms), so gaps are judged against the
    // nominal interval of this track, not the camera.
    private val nominalIntervalUs = 1_000_000L / fps

    fun prepare() {
        var lastError: Exception? = null
        for (attempt in attempts()) {
            try {
                codec.configure(attempt.second, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                configuredWith = attempt.first
                inputSurface = codec.createInputSurface()
                Log.i(TAG, "$name configured (${attempt.first}) codec=${codec.name} ${width}x$height@$fps ${kbps}kbps")
                return
            } catch (e: Exception) {
                lastError = e
                Log.w(TAG, "$name configure failed (${attempt.first}): ${e.message}")
                codec.reset()
            }
        }
        throw IllegalStateException("$name encoder could not be configured", lastError)
    }

    fun start() {
        codec.start()
        drainThread = Thread({ drain() }, "h8-drain-$name").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    fun stop() {
        runCatching { codec.signalEndOfInputStream() }
        drainThread?.join(3_000)
        runCatching { codec.stop() }
        runCatching { codec.release() }
        runCatching { inputSurface.release() }
        sink.onEnd()
    }

    /** Frames that the nominal fps predicts between the first and last output PTS. */
    fun expectedFrames(): Long {
        if (firstPtsUs < 0 || lastPtsUs <= firstPtsUs) return frames.get()
        return Math.round((lastPtsUs - firstPtsUs).toDouble() / nominalIntervalUs) + 1
    }

    private fun drain() {
        val info = MediaCodec.BufferInfo()
        var formatSent = false
        while (true) {
            val index = try {
                codec.dequeueOutputBuffer(info, 10_000)
            } catch (e: IllegalStateException) {
                Log.w(TAG, "$name drain stopped: ${e.message}")
                return
            }
            when {
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    sink.onFormat(codec.outputFormat)
                    formatSent = true
                }
                index >= 0 -> {
                    val buffer = codec.getOutputBuffer(index)
                    val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (buffer != null && info.size > 0 && !isConfig && formatSent) {
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        count(info)
                        sink.onSample(buffer, info)
                    }
                    codec.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    private fun count(info: MediaCodec.BufferInfo) {
        val pts = info.presentationTimeUs
        frames.incrementAndGet()
        bytes.addAndGet(info.size.toLong())
        if (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0) keyframes.incrementAndGet()
        if (firstPtsUs < 0) firstPtsUs = pts
        val previous = lastPtsUs
        if (previous >= 0) {
            val gap = pts - previous
            if (gap > nominalIntervalUs * 3 / 2) {
                ptsGaps.incrementAndGet()
                ptsGapFrames.addAndGet(Math.round(gap.toDouble() / nominalIntervalUs) - 1)
            }
            if (gap > maxGapUs.get()) maxGapUs.set(gap)
        }
        lastPtsUs = pts
    }

    private fun attempts(): List<Pair<String, MediaFormat>> {
        val caps = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            .firstOrNull { it.name == codec.name }
            ?.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
        val cbr = caps?.encoderCapabilities?.isBitrateModeSupported(
            MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR,
        ) == true
        fun base(): MediaFormat = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, kbps * 1_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            // 0 = realtime.
            setInteger(MediaFormat.KEY_PRIORITY, 0)
        }
        val full = base().apply {
            setInteger(
                MediaFormat.KEY_BITRATE_MODE,
                if (cbr) MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR
                else MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR,
            )
            if (baseline) {
                // Baseline keeps WebRTC (WHEP) viewers on every browser and never emits B-frames.
                setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
                setInteger(MediaFormat.KEY_LEVEL, MediaCodecInfo.CodecProfileLevel.AVCLevel31)
            }
        }
        val mode = if (cbr) "cbr" else "vbr"
        return listOf(
            "$mode${if (baseline) "+baseline" else ""}" to full,
            "default" to base(),
        )
    }

    companion object {
        private const val TAG = "H8Spike"
    }
}
