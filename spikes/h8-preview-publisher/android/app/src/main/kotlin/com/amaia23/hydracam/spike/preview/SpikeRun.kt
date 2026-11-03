package com.amaia23.hydracam.spike.preview

import android.content.Context
import android.graphics.SurfaceTexture
import android.media.MediaCodec
import android.os.Build
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Master (+ optional proxy) recorder encoders and the optional C4 preview encoder on one camera. */
class SpikeRun(private val context: Context, private val config: SpikeConfig) {
    private val dir = File(context.getExternalFilesDir(null), "h8/${config.runId}").apply { mkdirs() }
    private val statsFile = File(dir, "stats.jsonl")
    private val ticker = Executors.newSingleThreadScheduledExecutor()
    private val device = DeviceStats(context)
    private val startedAtMs = System.currentTimeMillis()

    private var camera: SharedCameraSession? = null
    private val tracks = mutableListOf<H264Track>()
    private var previewSink: PreviewSink? = null
    private var scaler: GlScaler? = null
    private var publisher: PreviewPublisher? = null
    private var ntp: Sntp.Result? = null
    private val lastFrames = mutableMapOf<String, Long>()

    fun start() {
        ntp = config.ntpHost?.let { runCatching { Sntp.query(it) }.getOrNull() }
        Log.i(TAG, "start ${config.copy(url = config.url?.substringBefore('?'))} ntp=$ntp")

        val master = H264Track(
            "master", config.masterWidth, config.masterHeight, config.cameraFps, config.masterKbps,
            baseline = false,
            sink = Mp4Sink(if (config.record) File(dir, "master.mp4") else null, config.keepFiles),
        )
        tracks += master
        if (config.proxy) {
            tracks += H264Track(
                "proxy", 1280, 720, config.cameraFps, config.proxyKbps,
                baseline = false,
                sink = Mp4Sink(if (config.record) File(dir, "proxy.mp4") else null, config.keepFiles),
            )
        }
        if (config.preview) {
            publisher = config.url?.let { PreviewPublisher.create(it, config) }
            val sink = PreviewSink(publisher, { camera }, ntp?.offsetMs ?: 0.0, config.timeNal)
            previewSink = sink
            tracks += H264Track(
                "preview", config.previewWidth, config.previewHeight, config.previewFps, config.previewKbps,
                baseline = true,
                sink = sink,
            )
        }
        tracks.forEach { it.prepare() }
        tracks.forEach { it.start() }

        val previewSurface = tracks.firstOrNull { it.name == "preview" }?.let { track ->
            scaler = glSource()?.let { (w, h) ->
                GlScaler(track.inputSurface, config.previewWidth, config.previewHeight, w, h).also { it.start() }
            }
            scaler?.inputSurface ?: track.inputSurface
        }
        val fpsOf = mapOf("preview" to config.previewFps)
        camera = SharedCameraSession(
            context,
            config.cameraFps,
            tracks.map {
                val surface = if (it.name == "preview") previewSurface!! else it.inputSurface
                SharedCameraSession.Target(it.name, surface, fpsOf[it.name] ?: config.cameraFps)
            },
        ).also { it.open() }
        ticker.scheduleWithFixedDelay({ runCatching { tick() }.onFailure { Log.w(TAG, "tick", it) } }, 5, 5, TimeUnit.SECONDS)
    }

    /** Camera size for the GlScaler, or null when the camera feeds the preview encoder directly. */
    private fun glSource(): Pair<Int, Int>? {
        val (pw, ph) = config.previewWidth to config.previewHeight
        val direct = SharedCameraSession.outputSizes(context, MediaCodec::class.java)
            .any { it.width == pw && it.height == ph }
        val useGl = when (config.previewPath) {
            "gl" -> true
            "direct" -> false
            else -> !direct
        }
        Log.i(TAG, "preview ${pw}x$ph directSupported=$direct path=${if (useGl) "gl" else "direct"}")
        if (!useGl) return null
        config.glSource?.split('x')?.let { return it[0].toInt() to it[1].toInt() }
        val size = SharedCameraSession.outputSizes(context, SurfaceTexture::class.java)
            .filter { it.width * ph == it.height * pw && it.width >= pw }
            .minBy { it.width }
        return size.width to size.height
    }

    fun stop() {
        ticker.shutdownNow()
        runCatching { camera?.close() }
        runCatching { scaler?.release() }
        tracks.forEach { track -> runCatching { track.stop() }.onFailure { Log.w(TAG, "stop ${track.name}", it) } }
        val summary = JSONObject(snapshot(final = true)).toString(2)
        File(dir, "summary.json").writeText(summary)
        Log.i(TAG, "summary $summary")
    }

    private fun tick() {
        val line = JSONObject(snapshot(final = false)).toString()
        statsFile.appendText(line + "\n")
        Log.i(TAG, "stats $line")
    }

    private fun snapshot(final: Boolean): Map<String, Any?> {
        val elapsedS = (System.currentTimeMillis() - startedAtMs) / 1_000.0
        val cam = camera
        return linkedMapOf(
            "t" to System.currentTimeMillis(),
            "run" to config.runId,
            "final" to final,
            "elapsedS" to elapsedS,
            "device" to "${Build.MANUFACTURER} ${Build.MODEL} API ${Build.VERSION.SDK_INT}",
            "config" to mapOf(
                "preview" to config.preview,
                "proxy" to config.proxy,
                "record" to config.record,
                "master" to "${config.masterWidth}x${config.masterHeight}@${config.cameraFps} ${config.masterKbps}kbps",
                "previewSpec" to "${config.previewWidth}x${config.previewHeight}@${config.previewFps} ${config.previewKbps}kbps",
                "protocol" to config.url?.substringBefore("://"),
                "timeNal" to config.timeNal?.name,
                "previewPath" to if (scaler != null) "gl" else "direct",
            ),
            "ntp" to ntp?.let { mapOf("offsetMs" to it.offsetMs, "rttMs" to it.rttMs, "server" to it.server) },
            "camera" to cam?.let {
                linkedMapOf<String, Any?>(
                    "started" to it.captureStarted.get(),
                    "completed" to it.captureCompleted.get(),
                    "failed" to it.captureFailed.get(),
                ) + it.info
            },
            "tracks" to tracks.associate { track ->
                val frames = track.frames.get()
                val fps = if (final) null else (frames - (lastFrames[track.name] ?: 0)) / 5.0
                lastFrames[track.name] = frames
                track.name to linkedMapOf(
                    "codecConfig" to track.configuredWith,
                    "frames" to frames,
                    "expectedFrames" to track.expectedFrames(),
                    "keyframes" to track.keyframes.get(),
                    "kbpsAvg" to if (elapsedS > 0) Math.round(track.bytes.get() * 8 / elapsedS / 1_000) else null,
                    "fpsWindow" to fps,
                    "ptsGaps" to track.ptsGaps.get(),
                    "ptsGapFrames" to track.ptsGapFrames.get(),
                    "maxGapMs" to track.maxGapUs.get() / 1_000.0,
                    "bufferLost" to cam?.let { c -> c.targetBufferLost(track.name) },
                )
            },
            "preview" to previewSink?.let { sink ->
                sink.drainLatency() + mapOf("ptsMatchedSensor" to "${sink.ptsMatched}/${sink.ptsChecked}")
            },
            "publisher" to publisher?.stats(),
            "scaler" to scaler?.stats(),
            "deviceStats" to device.sample(),
        )
    }

    companion object {
        private const val TAG = "H8Spike"
    }
}
