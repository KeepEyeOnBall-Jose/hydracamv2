package com.amaia23.hydracam.court

import android.media.MediaCodec
import com.pedro.common.ConnectChecker
import com.pedro.common.VideoCodec
import com.pedro.rtmp.rtmp.RtmpClient
import com.pedro.srt.srt.SrtClient
import java.nio.ByteBuffer

/**
 * [PreviewTransport] over RootEncoder's SRT and RTMP(S) clients (H8). One fresh client per
 * connect, with RootEncoder's own retries off: [PreviewController] owns backoff and the RTMPS
 * fallback. Every callback is handed to [post] (the preview executor). Only redacted URLs are logged.
 *
 * Encoder pts are sensor time since boot; each connection rebases them so its stream starts at 0.
 * RootEncoder writes RTMP timestamps as a signed 32-bit ms value (negative after ~24.9 days of
 * uptime, then cut to 24 bits on the wire) and SRT/MPEG-TS wraps 33-bit 90 kHz pts after ~26.5 h.
 */
class RootEncoderPreviewTransport(
    private val post: (Runnable) -> Unit,
    private val logger: CourtLogger = NoopCourtLogger,
    private val width: Int = WIDTH,
    private val height: Int = HEIGHT,
    private val fps: Int = PreviewRateGovernor.MAX_FPS,
) : PreviewTransport {
    private var client: Client? = null
    private var basePtsUs = NO_BASE

    override fun connect(url: String, config: PreviewCodecConfig, listener: PreviewTransport.Listener) {
        disconnect()
        logger.info(TAG, "Preview connecting to ${PreviewUrls.redact(url)}.")
        val checker = Checker(listener)
        val next = if (url.startsWith("$SRT_SCHEME:", ignoreCase = true)) srt(checker) else rtmp(checker)
        client = next
        basePtsUs = NO_BASE
        next.setVideoInfo(ByteBuffer.wrap(config.sps), ByteBuffer.wrap(config.pps))
        next.connect(url)
    }

    override fun send(frame: PreviewFrame) {
        val info = MediaCodec.BufferInfo()
        // Field writes, not BufferInfo.set(): RootEncoder only reads the fields.
        info.offset = 0
        info.size = frame.data.size
        if (basePtsUs == NO_BASE) {
            basePtsUs = frame.ptsUs
        }
        info.presentationTimeUs = (frame.ptsUs - basePtsUs).coerceAtLeast(0)
        info.flags = if (frame.keyFrame) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
        client?.sendVideo(ByteBuffer.wrap(frame.data), info)
    }

    override fun disconnect() {
        client?.disconnect()
        client = null
    }

    private fun srt(checker: Checker): Client {
        val srt = SrtClient(checker).apply {
            setVideoCodec(VideoCodec.H264)
            setOnlyVideo(true)
            setReTries(0)
            setLatency(SRT_LATENCY_MS)
        }
        return Client({ sps, pps ->
            srt.setVideoInfo(sps, pps, null)
        }, { srt.connect(it) }, srt::sendVideo, srt::disconnect)
    }

    private fun rtmp(checker: Checker): Client {
        val rtmp = RtmpClient(checker).apply {
            setVideoCodec(VideoCodec.H264)
            setOnlyVideo(true)
            setReTries(0)
            tlsHostVerification = true
            setVideoResolution(width, height)
            setFps(fps)
        }
        return Client({ sps, pps ->
            rtmp.setVideoInfo(sps, pps, null)
        }, { rtmp.connect(it) }, rtmp::sendVideo, rtmp::disconnect)
    }

    /** The four calls both RootEncoder clients share (they have no common type). */
    private class Client(
        val setVideoInfo: (ByteBuffer, ByteBuffer) -> Unit,
        val connect: (String) -> Unit,
        val sendVideo: (ByteBuffer, MediaCodec.BufferInfo) -> Unit,
        val disconnect: () -> Unit,
    )

    private inner class Checker(private val listener: PreviewTransport.Listener) : ConnectChecker {
        // The URL carries the token; connect() already logged it redacted.
        override fun onConnectionStarted(url: String) = Unit

        override fun onConnectionSuccess() {
            post(Runnable { listener.onConnected() })
        }

        override fun onConnectionFailed(reason: String) {
            post(Runnable { listener.onFailed(reason) })
        }

        override fun onAuthError() {
            post(Runnable { listener.onFailed("auth error") })
        }

        override fun onAuthSuccess() = Unit

        // Our own disconnect() also lands here; a dropped publish arrives as onConnectionFailed.
        override fun onDisconnect() = Unit
    }

    private companion object {
        const val TAG = "CourtPreview"
        const val SRT_SCHEME = "srt"
        const val SRT_LATENCY_MS = 120
        const val WIDTH = 640
        const val HEIGHT = 360
        const val NO_BASE = Long.MIN_VALUE
    }
}
