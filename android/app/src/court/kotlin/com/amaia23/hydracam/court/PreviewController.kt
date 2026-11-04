package com.amaia23.hydracam.court

/** One encoded H.264 access unit (Annex B) from the preview encoder. */
class PreviewFrame(val data: ByteArray, val ptsUs: Long, val keyFrame: Boolean)

/** The preview encoder's SPS and PPS (Annex B), needed before a publisher can connect. */
data class PreviewCodecConfig(val sps: ByteArray, val pps: ByteArray) {
    override fun equals(other: Any?): Boolean =
        other is PreviewCodecConfig && sps.contentEquals(other.sps) && pps.contentEquals(other.pps)

    override fun hashCode(): Int = 31 * sps.contentHashCode() + pps.contentHashCode()
}

/** The live knobs of the dedicated preview encoder (never the proxy encoder). */
interface PreviewEncoderControl {
    fun requestKeyFrame()

    fun setBitrateKbps(kbps: Int)
}

/**
 * Publishes preview frames to one relay URL. Callbacks may come from any thread; the device
 * implementation posts them to the preview executor before they reach [PreviewController].
 */
interface PreviewTransport {
    fun connect(url: String, config: PreviewCodecConfig, listener: Listener)

    fun send(frame: PreviewFrame)

    fun disconnect()

    interface Listener {
        fun onConnected()

        fun onFailed(reason: String)
    }
}

data class PreviewTuning(
    val baseBackoffMs: Long = 1_000,
    val maxBackoffMs: Long = 8_000,
    val failuresBeforeFallback: Int = 2,
    val keyFrameRequestIntervalMs: Long = 500,
    /** How long the camera may take to open before the preview asks for it again (then as often). */
    val cameraRetryMs: Long = 5_000,
)

/**
 * H8/S1 live preview, driven by C1 `preview.start` / `preview.stop` (K2 re-arms with a fresh token
 * before the TTL runs out). The preview never touches the recording: it only holds the camera open
 * and changes the preview fps of the repeating burst through [CourtPreviewSeam].
 *
 * Not thread-safe: every call comes from one executor (frames, transport callbacks, ticks, commands).
 */
class PreviewController(
    private val camera: CourtPreviewSeam,
    private val encoder: PreviewEncoderControl?,
    private val transport: PreviewTransport,
    private val clock: CourtClock,
    private val logger: CourtLogger = NoopCourtLogger,
    private val tuning: PreviewTuning = PreviewTuning(),
) {
    private sealed class State(val name: String) {
        object Off : State("off")

        object Waiting : State("waiting")

        class Connecting(val generation: Int) : State("connecting")

        class Publishing(val generation: Int) : State("publishing")

        class Backoff(val untilMs: Long) : State("backoff")
    }

    private var state: State = State.Off
    private var target: PreviewTarget? = null
    private var config: PreviewCodecConfig? = null
    private var expiresAtMs = 0L
    private var generation = 0
    private var urlIndex = 0
    private var urlFailures = 0
    private var attempts = 0
    private var awaitingKey = true
    private var lastDropKeyRequestMs = Long.MIN_VALUE
    private var framesSent = 0
    private var framesDropped = 0
    private var reconnects = 0
    private var cameraFailed = false
    private var cameraRetries = 0
    private var cameraCheckAtMs = 0L
    private val governor = PreviewRateGovernor(capKbps = MAX_KBPS)

    val isActive: Boolean get() = state != State.Off

    /** Active with the camera open (or still opening): what the `previewing` mode reports. */
    val isPreviewing: Boolean get() = isActive && !cameraFailed

    /** Why an active preview shows nothing, for `state.lastError`; null when it is fine. */
    val problem: String? get() = if (isActive && cameraFailed) CAMERA_PROBLEM else null

    val stateName: String get() = state.name

    fun start(command: PreviewStart, identity: PreviewIdentity?): CommandResult {
        if (encoder == null) {
            return CommandResult.Nack(C1NackCode.UNSUPPORTED, "no preview encoder on this device")
        }
        if (identity == null) {
            return CommandResult.Nack(C1NackCode.NOT_ENROLLED, "preview needs an enrolled court slot")
        }
        val next = PreviewUrls.target(command.publishUrl, command.token, identity)
        val now = clock.nowMs()
        expiresAtMs = expiry(now, command.ttlS)
        governor.capKbps = command.kbps
        val previous = target
        target = next
        when {
            !isActive -> begin(now, encoder)
            previous?.key == next.key -> {
                // A re-arm: the fresh token is for the next reconnect; the stream keeps going.
                reopenCameraIfClosed()
                applyLevels(encoder)
                encoder.requestKeyFrame()
            }
            else -> {
                logger.info(TAG, "Preview target changed to ${next.key}.")
                reopenCameraIfClosed()
                applyLevels(encoder)
                transport.disconnect()
                urlIndex = 0
                urlFailures = 0
                connect()
            }
        }
        logger.info(TAG, "Preview armed: ${next.key}, ${command.kbps} kbps, ttl ${command.ttlS} s.")
        return CommandResult.Ack
    }

    fun stop(reason: String) {
        if (!isActive) {
            return
        }
        generation++
        state = State.Off
        target = null
        transport.disconnect()
        camera.setPreviewFps(0)
        camera.holdCameraForPreview(false)
        logger.info(TAG, "Preview stopped ($reason); sent $framesSent, dropped $framesDropped.")
    }

    fun onCodecConfig(next: PreviewCodecConfig) {
        if (config != null && config != next) {
            logger.info(TAG, "Preview codec config changed; used from the next connect.")
        }
        config = next
        if (state == State.Waiting) {
            connect()
        }
    }

    fun onFrame(frame: PreviewFrame) {
        val enc = encoder
        if (state !is State.Publishing || enc == null) {
            return
        }
        if (awaitingKey && !frame.keyFrame) {
            framesDropped++
            return
        }
        if (admit(frame, enc)) {
            awaitingKey = false
            framesSent++
            transport.send(frame)
        }
    }

    /** False when the governor drops [frame]; the stream then waits for a fresh key frame. */
    private fun admit(frame: PreviewFrame, enc: PreviewEncoderControl): Boolean {
        val now = clock.nowMs()
        if (governor.admit(frame.data.size, now)) {
            return true
        }
        framesDropped++
        awaitingKey = true
        if (lastDropKeyRequestMs == Long.MIN_VALUE ||
            now - lastDropKeyRequestMs >= tuning.keyFrameRequestIntervalMs
        ) {
            lastDropKeyRequestMs = now
            enc.requestKeyFrame()
        }
        return false
    }

    /** Called about every 500 ms: TTL, the camera, backoff and the rate loop. */
    fun tick() {
        val now = clock.nowMs()
        val current = state
        when {
            current == State.Off -> return
            now >= expiresAtMs -> stop("ttl")
            else -> {
                watchCamera(now)
                if (current is State.Backoff && now >= current.untilMs) {
                    connect()
                } else if (governor.adjust(now)) {
                    encoder?.let(::applyLevels)
                }
            }
        }
    }

    fun measuredKbps(): Int = if (isActive) governor.measuredKbps(clock.nowMs()) else 0

    fun stats(): Map<String, Any?> = mapOf(
        "state" to state.name,
        "target" to target?.key,
        "urlIndex" to urlIndex,
        "fps" to governor.fps,
        "encoderKbps" to governor.encoderKbps,
        "capKbps" to governor.capKbps,
        "measuredKbps" to measuredKbps(),
        "framesSent" to framesSent,
        "framesDropped" to framesDropped,
        "reconnects" to reconnects,
        "camera" to cameraStatus(),
        "cameraRetries" to cameraRetries,
    )

    private fun begin(now: Long, enc: PreviewEncoderControl) {
        camera.holdCameraForPreview(true)
        cameraFailed = false
        cameraRetries = 0
        cameraCheckAtMs = now + tuning.cameraRetryMs
        governor.reset(now)
        applyLevels(enc)
        urlIndex = 0
        urlFailures = 0
        attempts = 0
        if (config == null) {
            state = State.Waiting
        } else {
            connect()
        }
    }

    private fun connect() {
        val urls = target?.urls ?: return
        val cfg = config
        if (cfg == null) {
            state = State.Waiting
            return
        }
        val gen = ++generation
        state = State.Connecting(gen)
        transport.connect(urls[urlIndex % urls.size], cfg, Listener(gen))
    }

    private fun onConnected(gen: Int) {
        if (gen != generation || state !is State.Connecting) {
            return
        }
        state = State.Publishing(gen)
        attempts = 0
        urlFailures = 0
        awaitingKey = true
        governor.reset(clock.nowMs())
        encoder?.requestKeyFrame()
        logger.info(TAG, "Preview publishing to ${target?.key} (url ${urlIndex + 1}).")
    }

    private fun onFailed(gen: Int, reason: String) {
        if (gen != generation || !isActive) {
            return
        }
        generation++
        transport.disconnect()
        attempts++
        urlFailures++
        reconnects++
        val urls = target?.urls.orEmpty()
        if (urlFailures >= tuning.failuresBeforeFallback && urls.size > 1) {
            urlIndex = (urlIndex + 1) % urls.size
            urlFailures = 0
        }
        val delay = backoffMs(attempts)
        state = State.Backoff(clock.nowMs() + delay)
        logger.warn(TAG, "Preview publish failed ($reason); retry in $delay ms on url ${urlIndex + 1}.")
    }

    /**
     * The camera open is async and its failure only logged: while the camera stays closed, ask for it
     * again every [PreviewTuning.cameraRetryMs] and report the preview as failed, not previewing.
     */
    private fun watchCamera(now: Long) {
        if (camera.cameraOpen()) {
            if (cameraFailed) {
                logger.info(TAG, "Preview camera open after $cameraRetries retries.")
                cameraFailed = false
                encoder?.requestKeyFrame()
            }
            cameraRetries = 0
            cameraCheckAtMs = now + tuning.cameraRetryMs
        } else if (now >= cameraCheckAtMs) {
            if (!cameraFailed) {
                logger.warn(TAG, "Preview camera did not open; retrying every ${tuning.cameraRetryMs} ms.")
            }
            cameraFailed = true
            cameraRetries++
            cameraCheckAtMs = now + tuning.cameraRetryMs
            camera.holdCameraForPreview(true)
        }
    }

    /** A re-arm also retries a camera that failed to open (or that a recording closed). */
    private fun reopenCameraIfClosed() {
        if (!camera.cameraOpen()) {
            camera.holdCameraForPreview(true)
        }
    }

    private fun cameraStatus(): String = when {
        !isActive -> "off"
        cameraFailed -> "failed"
        camera.cameraOpen() -> "open"
        else -> "opening"
    }

    /** [now] + [ttlS] seconds, saturating: C1 allows a TTL up to `Long.MAX_VALUE / 1000` s. */
    private fun expiry(now: Long, ttlS: Long): Long =
        if (ttlS >= (Long.MAX_VALUE - now) / MS_PER_S) Long.MAX_VALUE else now + ttlS * MS_PER_S

    private fun backoffMs(attempt: Int): Long {
        var delay = tuning.baseBackoffMs
        repeat(attempt - 1) {
            if (delay >= tuning.maxBackoffMs) return tuning.maxBackoffMs
            delay *= 2
        }
        return minOf(delay, tuning.maxBackoffMs)
    }

    private fun applyLevels(enc: PreviewEncoderControl) {
        enc.setBitrateKbps(governor.encoderKbps)
        camera.setPreviewFps(governor.fps)
    }

    private inner class Listener(private val gen: Int) : PreviewTransport.Listener {
        override fun onConnected() = this@PreviewController.onConnected(gen)

        override fun onFailed(reason: String) = this@PreviewController.onFailed(gen, reason)
    }

    private companion object {
        const val TAG = "CourtPreview"
        const val MAX_KBPS = 1_000
        const val MS_PER_S = 1_000L
        const val CAMERA_PROBLEM = "preview_camera_closed"
    }
}
