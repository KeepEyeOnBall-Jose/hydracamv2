package com.amaia23.hydracam.spike.preview

import android.annotation.SuppressLint
import android.media.MediaCodec
import android.util.Log
import com.pedro.common.ConnectChecker
import com.pedro.common.StreamingStatsReport
import com.pedro.common.VideoCodec
import com.pedro.rtmp.rtmp.RtmpClient
import com.pedro.srt.srt.SrtClient
import java.nio.ByteBuffer
import java.security.cert.X509Certificate
import java.util.concurrent.atomic.AtomicLong
import javax.net.ssl.X509TrustManager

/** Publishes encoded preview access units. SRT is primary, RTMP(S) the fallback (C4). */
interface PreviewPublisher {
    fun setVideoInfo(sps: ByteBuffer, pps: ByteBuffer)
    fun connect()
    fun send(accessUnit: ByteBuffer, info: MediaCodec.BufferInfo)
    fun disconnect()
    fun stats(): Map<String, Any?>

    companion object {
        fun create(url: String, config: SpikeConfig): PreviewPublisher = when {
            url.startsWith("srt://") -> SrtPreviewPublisher(url, config)
            url.startsWith("rtmp://") || url.startsWith("rtmps://") -> RtmpPreviewPublisher(url, config)
            else -> throw IllegalArgumentException("unsupported publish URL scheme: ${url.substringBefore(':')}")
        }
    }
}

/** Connection callbacks shared by both transports: logs, counts and reconnects. */
private class Checker(private val protocol: String, private val reconnect: (String) -> Unit) : ConnectChecker {
    val connects = AtomicLong()
    val failures = AtomicLong()
    val disconnects = AtomicLong()
    @Volatile var connected = false
    @Volatile var lastError: String? = null
    @Volatile var connectedAtMs = 0L
    @Volatile var startedAtMs = 0L
    @Volatile var lastReport: StreamingStatsReport? = null

    override fun onConnectionStarted(url: String) {
        startedAtMs = System.currentTimeMillis()
        Log.i(TAG, "$protocol connecting to ${redact(url)}")
    }

    override fun onConnectionSuccess() {
        connected = true
        connects.incrementAndGet()
        connectedAtMs = System.currentTimeMillis()
        Log.i(TAG, "$protocol connected in ${connectedAtMs - startedAtMs} ms")
    }

    override fun onConnectionFailed(reason: String) {
        connected = false
        failures.incrementAndGet()
        lastError = reason
        Log.w(TAG, "$protocol connection failed: $reason")
        reconnect(reason)
    }

    override fun onDisconnect() {
        connected = false
        disconnects.incrementAndGet()
        Log.i(TAG, "$protocol disconnected")
    }

    override fun onAuthError() {
        lastError = "auth error"
        Log.w(TAG, "$protocol auth error")
    }

    override fun onAuthSuccess() {
        Log.i(TAG, "$protocol auth ok")
    }

    override fun onStreamingStats(report: StreamingStatsReport) {
        lastReport = report
    }

    fun stats(): Map<String, Any?> = mapOf(
        "connected" to connected,
        "connects" to connects.get(),
        "failures" to failures.get(),
        "disconnects" to disconnects.get(),
        "lastError" to lastError,
        "bytesOutPerS" to lastReport?.bytesOutPerSecond,
        "queueCongestionPct" to lastReport?.queueCongestionPercent,
    )

    companion object {
        private const val TAG = "H8Spike"

        /** Never log tokens: keep scheme, host and path only. */
        fun redact(url: String): String = url.substringBefore('?') + if ('?' in url) "?<redacted>" else ""
    }
}

private class SrtPreviewPublisher(private val url: String, config: SpikeConfig) : PreviewPublisher {
    private lateinit var client: SrtClient
    private val checker = Checker("srt") { reason ->
        if (client.shouldRetry(reason)) client.reConnect(RETRY_MS)
    }

    init {
        client = SrtClient(checker).apply {
            setVideoCodec(VideoCodec.H264)
            setOnlyVideo(true)
            setLatency(config.srtLatencyMs)
            setReTries(Int.MAX_VALUE)
        }
    }

    override fun setVideoInfo(sps: ByteBuffer, pps: ByteBuffer) = client.setVideoInfo(sps, pps, null)
    override fun connect() = client.connect(url)
    override fun send(accessUnit: ByteBuffer, info: MediaCodec.BufferInfo) = client.sendVideo(accessUnit, info)
    override fun disconnect() = client.disconnect()

    override fun stats(): Map<String, Any?> = checker.stats() + mapOf(
        "protocol" to "srt",
        "sentFrames" to client.sentVideoFrames,
        "droppedFrames" to client.droppedVideoFrames,
        "bytesSent" to client.bytesSend,
        "itemsInCache" to client.getItemsInCache(),
    )
}

private class RtmpPreviewPublisher(private val url: String, config: SpikeConfig) : PreviewPublisher {
    private lateinit var client: RtmpClient
    private val checker = Checker(if (url.startsWith("rtmps")) "rtmps" else "rtmp") { reason ->
        if (client.shouldRetry(reason)) client.reConnect(RETRY_MS)
    }

    init {
        client = RtmpClient(checker).apply {
            setVideoCodec(VideoCodec.H264)
            setOnlyVideo(true)
            setReTries(Int.MAX_VALUE)
            setFps(config.previewFps)
            setVideoResolution(config.previewWidth, config.previewHeight)
            // RootEncoder defaults to false; production must verify the relay hostname.
            tlsHostVerification = !config.insecureTls
            if (config.insecureTls) addCertificates(TrustAll)
        }
    }

    override fun setVideoInfo(sps: ByteBuffer, pps: ByteBuffer) = client.setVideoInfo(sps, pps, null)
    override fun connect() = client.connect(url)
    override fun send(accessUnit: ByteBuffer, info: MediaCodec.BufferInfo) = client.sendVideo(accessUnit, info)
    override fun disconnect() = client.disconnect()

    override fun stats(): Map<String, Any?> = checker.stats() + mapOf(
        "protocol" to if (url.startsWith("rtmps")) "rtmps" else "rtmp",
        "sentFrames" to client.sentVideoFrames,
        "droppedFrames" to client.droppedVideoFrames,
        "bytesSent" to client.bytesSend,
    )
}

/** Spike only (self-signed local relay). Never ship. */
@SuppressLint("CustomX509TrustManager", "TrustAllX509TrustManager")
private object TrustAll : X509TrustManager {
    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
}

private const val RETRY_MS = 2_000L
