package com.amaia23.hydracam.spike.preview

import android.content.Intent
import android.os.Bundle

/**
 * One spike run, parsed from adb intent extras, e.g.
 * `am start -n com.amaia23.hydracam.spike.preview/.SpikeActivity --es url srt://host:8890?streamid=... --ez preview true`.
 */
data class SpikeConfig(
    val runId: String,
    /** srt://, rtmp:// or rtmps:// publish URL. Null = preview encoder runs but nothing is published. */
    val url: String?,
    val preview: Boolean,
    val proxy: Boolean,
    val record: Boolean,
    val keepFiles: Boolean,
    val masterWidth: Int,
    val masterHeight: Int,
    val cameraFps: Int,
    val masterKbps: Int,
    val proxyKbps: Int,
    val previewWidth: Int,
    val previewHeight: Int,
    val previewFps: Int,
    val previewKbps: Int,
    val srtLatencyMs: Int,
    val insecureTls: Boolean,
    val ntpHost: String?,
    val durationS: Int,
    /** Capture-time NAL carrier, null = none. */
    val timeNal: CaptureTimeNal.Carrier?,
    /** "direct" (camera to encoder surface), "gl" (camera to GlScaler) or "auto" (direct if the size is supported). */
    val previewPath: String,
    /** GlScaler camera size "WxH"; null = smallest supported 16:9 size at least the preview size. */
    val glSource: String?,
) {
    fun toBundle(): Bundle = Bundle().apply {
        putString(EXTRA_RUN_ID, runId)
        putString(EXTRA_URL, url)
        putBoolean(EXTRA_PREVIEW, preview)
        putBoolean(EXTRA_PROXY, proxy)
        putBoolean(EXTRA_RECORD, record)
        putBoolean(EXTRA_KEEP_FILES, keepFiles)
        putString(EXTRA_MASTER_RES, if (masterHeight == 720) "720p" else "1080p")
        putInt(EXTRA_CAMERA_FPS, cameraFps)
        putInt(EXTRA_MASTER_KBPS, masterKbps)
        putInt(EXTRA_PROXY_KBPS, proxyKbps)
        putInt(EXTRA_PREVIEW_FPS, previewFps)
        putInt(EXTRA_PREVIEW_KBPS, previewKbps)
        putInt(EXTRA_SRT_LATENCY_MS, srtLatencyMs)
        putBoolean(EXTRA_INSECURE_TLS, insecureTls)
        putString(EXTRA_NTP_HOST, ntpHost ?: "none")
        putInt(EXTRA_DURATION_S, durationS)
        putString(EXTRA_TIME_NAL, timeNal?.name?.lowercase() ?: "none")
        putString(EXTRA_PREVIEW_PATH, previewPath)
        putString(EXTRA_GL_SOURCE, glSource)
    }

    companion object {
        const val EXTRA_RUN_ID = "run"
        const val EXTRA_URL = "url"
        const val EXTRA_PREVIEW = "preview"
        const val EXTRA_PROXY = "proxy"
        const val EXTRA_RECORD = "record"
        const val EXTRA_KEEP_FILES = "keep"
        const val EXTRA_MASTER_RES = "master"
        const val EXTRA_CAMERA_FPS = "fps"
        const val EXTRA_MASTER_KBPS = "masterKbps"
        const val EXTRA_PROXY_KBPS = "proxyKbps"
        const val EXTRA_PREVIEW_FPS = "previewFps"
        const val EXTRA_PREVIEW_KBPS = "previewKbps"
        const val EXTRA_SRT_LATENCY_MS = "srtLatency"
        const val EXTRA_INSECURE_TLS = "insecureTls"
        const val EXTRA_NTP_HOST = "ntp"
        const val EXTRA_DURATION_S = "duration"
        const val EXTRA_TIME_NAL = "timeNal"
        const val EXTRA_PREVIEW_PATH = "previewPath"
        const val EXTRA_GL_SOURCE = "glSource"

        fun from(intent: Intent): SpikeConfig {
            val e = intent.extras ?: Bundle()
            val master720 = e.getString(EXTRA_MASTER_RES) == "720p"
            return SpikeConfig(
                runId = e.getString(EXTRA_RUN_ID) ?: "run-${System.currentTimeMillis()}",
                url = e.getString(EXTRA_URL)?.takeIf { it.isNotBlank() },
                preview = e.getBoolean(EXTRA_PREVIEW, true),
                proxy = e.getBoolean(EXTRA_PROXY, false),
                record = e.getBoolean(EXTRA_RECORD, true),
                keepFiles = e.getBoolean(EXTRA_KEEP_FILES, false),
                masterWidth = if (master720) 1280 else 1920,
                masterHeight = if (master720) 720 else 1080,
                cameraFps = e.getInt(EXTRA_CAMERA_FPS, 30),
                masterKbps = e.getInt(EXTRA_MASTER_KBPS, if (master720) 4_000 else 8_000),
                proxyKbps = e.getInt(EXTRA_PROXY_KBPS, 2_000),
                // C4 preview stream: 640x360, 20 fps, 700 kbps, GOP 1 s, no audio.
                previewWidth = 640,
                previewHeight = 360,
                previewFps = e.getInt(EXTRA_PREVIEW_FPS, 20),
                previewKbps = e.getInt(EXTRA_PREVIEW_KBPS, 700),
                srtLatencyMs = e.getInt(EXTRA_SRT_LATENCY_MS, 120),
                insecureTls = e.getBoolean(EXTRA_INSECURE_TLS, false),
                ntpHost = (e.getString(EXTRA_NTP_HOST) ?: "time.google.com").takeIf { it != "none" },
                durationS = e.getInt(EXTRA_DURATION_S, 0),
                timeNal = when (e.getString(EXTRA_TIME_NAL) ?: "filler") {
                    "none" -> null
                    "sei" -> CaptureTimeNal.Carrier.SEI
                    else -> CaptureTimeNal.Carrier.FILLER
                },
                previewPath = e.getString(EXTRA_PREVIEW_PATH) ?: "auto",
                glSource = e.getString(EXTRA_GL_SOURCE)?.takeIf { it.isNotBlank() },
            )
        }
    }
}
