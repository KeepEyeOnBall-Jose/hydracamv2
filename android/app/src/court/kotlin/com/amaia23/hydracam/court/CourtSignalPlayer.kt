package com.amaia23.hydracam.court

import org.json.JSONObject
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/** Torch through the recorder's repeating request (`FLASH_MODE_TORCH`), never `setTorchMode`. */
interface TorchControl {
    /** False while the camera is closed: the torch is skipped and logged. */
    fun torchAvailable(): Boolean

    fun setTorch(on: Boolean)
}

enum class SignalTone {
    /** ≈ 3.7/4.1 kHz (ToneGenerator TONE_CDMA_HIGH_L). */
    HIGH,

    /** ≈ 2.6/2.9 kHz (TONE_CDMA_MED_L). */
    MID,

    /** ≈ 1.3 kHz (TONE_CDMA_LOW_L); outside the 2–4 kHz band, used only for `error`. */
    LOW,
}

interface TonePlayer {
    fun play(tone: SignalTone, durationMs: Int)
}

/** One step of a signal, [atMs] after the signal's start. */
data class SignalStep(val atMs: Long, val tone: SignalTone? = null, val toneMs: Int = 0, val torchOn: Boolean? = null)

/** C6 signal table (court-remote/50-gestures-and-signals.md). Gaps between tones are 300 ms. */
object SignalPatterns {
    const val COUNTDOWN = "countdown"
    const val REC_START = "rec.start"
    const val REC_STOP = "rec.stop"
    const val MARKER_ACK = "marker.ack"
    const val LEASE_WARN = "lease.warn"
    const val ERROR = "error"
    const val SYNC_FLASH = "sync.flash"

    private const val BEEP_MS = 150
    private const val FLASH_MS = 150L

    fun forSignal(signal: String): List<SignalStep>? =
        when (signal) {
            COUNTDOWN -> (0 until 3).flatMap { index ->
                val at = index * 1_000L
                listOf(
                    SignalStep(at, SignalTone.MID, BEEP_MS, torchOn = true),
                    SignalStep(at + FLASH_MS, torchOn = false),
                )
            }
            REC_START -> listOf(
                SignalStep(0, SignalTone.HIGH, 700, torchOn = true),
                SignalStep(200, torchOn = false),
            )
            REC_STOP -> listOf(
                SignalStep(0, SignalTone.HIGH, 250, torchOn = false),
                SignalStep(550, SignalTone.MID, 250),
            )
            MARKER_ACK -> listOf(
                SignalStep(0, SignalTone.MID, 100, torchOn = true),
                SignalStep(100, torchOn = false),
                SignalStep(400, SignalTone.HIGH, 100, torchOn = true),
                SignalStep(500, torchOn = false),
            )
            // K2 repeats lease.warn every 30 s; one emit plays one beep and one slow blink.
            LEASE_WARN -> listOf(
                SignalStep(0, SignalTone.MID, BEEP_MS, torchOn = true),
                SignalStep(600, torchOn = false),
            )
            ERROR -> listOf(SignalStep(0, SignalTone.LOW, 500))
            SYNC_FLASH -> listOf(
                SignalStep(0, torchOn = true),
                SignalStep(100, torchOn = false),
            )
            else -> null
        }
}

/**
 * H15: plays `signal.emit` at its server time. The device never plays signals on its own.
 *
 * - Up to [lateToleranceMs] late: played now. Later: skipped and logged.
 * - Each signal is logged to `signals.jsonl` as `{signal, atServerMs, playedServerMs, slot, ...}`.
 */
class CourtSignalPlayer(
    private val scheduler: ScheduledExecutorService,
    private val clockEstimator: ClockOffsetEstimator,
    private val torch: TorchControl,
    private val tones: TonePlayer,
    private val log: JsonlAppender,
    private val slot: () -> String,
    private val clock: CourtClock = CourtClock.SYSTEM,
    private val logger: CourtLogger = NoopCourtLogger,
    private val lateToleranceMs: Long = 1_000,
) {
    fun emit(signal: SignalEmit): CommandResult {
        val steps = SignalPatterns.forSignal(signal.signal)
            ?: return CommandResult.Nack(C1NackCode.UNSUPPORTED, "Unknown signal ${signal.signal}.")
        val delayMs = clockEstimator.toDeviceMs(signal.atServerMs) - clock.nowMs()
        if (delayMs < -lateToleranceMs) {
            writeLog(signal, playedServerMs = null, torch = "none", skipped = "late_${-delayMs}ms")
            return CommandResult.Ack
        }
        val startDelay = maxOf(0, delayMs)
        val torchReady = torch.torchAvailable()
        val wantsTorch = steps.any { it.torchOn == true }
        scheduler.schedule(
            {
                val torchState = when {
                    !wantsTorch -> "none"
                    torch.torchAvailable() -> "ok"
                    else -> "camera_closed"
                }
                writeLog(signal, clockEstimator.toServerMs(clock.nowMs()), torchState, skipped = null)
            },
            startDelay,
            TimeUnit.MILLISECONDS,
        )
        for (step in steps) {
            scheduler.schedule({ play(step) }, startDelay + step.atMs, TimeUnit.MILLISECONDS)
        }
        if (wantsTorch && !torchReady) {
            logger.info(TAG, "${signal.signal}: camera closed, torch skipped.")
        }
        return CommandResult.Ack
    }

    private fun play(step: SignalStep) {
        try {
            step.tone?.let { tones.play(it, step.toneMs) }
            val torchOn = step.torchOn
            if (torchOn != null && torch.torchAvailable()) {
                torch.setTorch(torchOn)
            }
        } catch (error: RuntimeException) {
            logger.warn(TAG, "Signal step failed.", error)
        }
    }

    private fun writeLog(signal: SignalEmit, playedServerMs: Long?, torch: String, skipped: String?) {
        val json = JSONObject()
            .put("signal", signal.signal)
            .put("atServerMs", signal.atServerMs)
            .put("slot", slot())
            .put("sessionId", signal.sessionId ?: JSONObject.NULL)
            .put("playedServerMs", playedServerMs ?: JSONObject.NULL)
            .put("torch", torch)
        if (skipped != null) {
            json.put("skipped", skipped)
        }
        try {
            log.append(json)
        } catch (error: java.io.IOException) {
            logger.warn(TAG, "Could not write signals.jsonl.", error)
        }
        logger.info(TAG, json.toString())
    }

    private companion object {
        const val TAG = "CourtSignals"
    }
}
