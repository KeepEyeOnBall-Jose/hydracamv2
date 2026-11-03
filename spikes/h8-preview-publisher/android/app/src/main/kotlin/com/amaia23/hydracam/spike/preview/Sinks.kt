package com.amaia23.hydracam.spike.preview

import android.media.MediaCodec
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import java.nio.ByteBuffer

/** Recorder stand-in: writes the track to an MP4 so disk I/O is part of the load. */
class Mp4Sink(private val file: File?, private val keep: Boolean) : H264Track.Sink {
    private var muxer: MediaMuxer? = null
    private var track = -1

    override fun onFormat(format: MediaFormat) {
        if (file == null) return
        muxer = MediaMuxer(file.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4).also {
            track = it.addTrack(format)
            it.start()
        }
    }

    override fun onSample(buffer: ByteBuffer, info: MediaCodec.BufferInfo) {
        muxer?.writeSampleData(track, buffer, info)
    }

    override fun onEnd() {
        runCatching { muxer?.stop() }.onFailure { Log.w("H8Spike", "muxer stop: ${it.message}") }
        runCatching { muxer?.release() }
        if (!keep) file?.delete()
    }
}

/**
 * Preview encoder output to the publisher. Prepends the capture-time NAL to every access unit
 * and measures capture-to-encoded latency on the device.
 */
class PreviewSink(
    private val publisher: PreviewPublisher?,
    private val camera: () -> SharedCameraSession?,
    private val ntpOffsetMs: Double,
    private val timeNal: CaptureTimeNal.Carrier?,
) : H264Track.Sink {
    private var connected = false
    private var seq = 0L
    private val window = ArrayList<Double>(256)
    @Volatile var ptsMatched = 0L
        private set
    @Volatile var ptsChecked = 0L
        private set

    override fun onFormat(format: MediaFormat) {
        val sps = format.getByteBuffer("csd-0")
        val pps = format.getByteBuffer("csd-1")
        if (publisher == null || sps == null || pps == null) return
        publisher.setVideoInfo(sps, pps)
        if (!connected) {
            publisher.connect()
            connected = true
        }
    }

    override fun onSample(buffer: ByteBuffer, info: MediaCodec.BufferInfo) {
        val session = camera()
        val sensorToWallNs = session?.sensorToWallNs
        val captureWallMs = if (sensorToWallNs != null) {
            val ms = (info.presentationTimeUs * 1_000 + sensorToWallNs) / 1_000_000.0
            synchronized(window) { window += System.currentTimeMillis() - ms }
            Math.round(ms + ntpOffsetMs)
        } else 0L
        if (session != null && ptsChecked < 200) checkPts(session, info.presentationTimeUs)
        if (publisher == null) return

        val tag = timeNal?.let { CaptureTimeNal.nal(it, captureWallMs, seq++) } ?: ByteArray(0)
        val au = ByteArray(tag.size + info.size)
        System.arraycopy(tag, 0, au, 0, tag.size)
        buffer.get(au, tag.size, info.size)
        val out = MediaCodec.BufferInfo().apply { set(0, au.size, info.presentationTimeUs, info.flags) }
        publisher.send(ByteBuffer.wrap(au), out)
    }

    override fun onEnd() {
        runCatching { publisher?.disconnect() }
    }

    /** Capture-to-encoder-output latency (ms) percentiles since the last call. */
    fun drainLatency(): Map<String, Double?> {
        val values = synchronized(window) { window.sorted().also { window.clear() } }
        fun pct(p: Double) = if (values.isEmpty()) null else Math.round(values[((values.size - 1) * p).toInt()] * 10) / 10.0
        return mapOf("encodeLatencyP50Ms" to pct(0.5), "encodeLatencyP95Ms" to pct(0.95))
    }

    private fun checkPts(session: SharedCameraSession, ptsUs: Long) {
        val n = minOf(session.recentSensorCount, session.recentSensorUs.size.toLong()).toInt()
        ptsChecked++
        for (i in 0 until n) {
            if (Math.abs(session.recentSensorUs[i] - ptsUs) <= 1) {
                ptsMatched++
                return
            }
        }
    }
}
