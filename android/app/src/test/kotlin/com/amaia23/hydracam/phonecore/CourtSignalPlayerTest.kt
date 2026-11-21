package com.amaia23.hydracam.phonecore

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class CourtSignalPlayerTest {
    @get:Rule
    val temp = TemporaryFolder()

    private inner class FakeTorch(var available: Boolean) : TorchControl {
        val calls = LinkedBlockingQueue<Boolean>()

        override fun torchAvailable(): Boolean = available

        override fun setTorch(on: Boolean) {
            calls.put(on)
        }
    }

    private inner class FakeTones : TonePlayer {
        val played = LinkedBlockingQueue<Pair<SignalTone, Int>>()

        override fun play(tone: SignalTone, durationMs: Int) {
            played.put(tone to durationMs)
        }
    }

    private val clock = FakePhoneClock()
    private val tones = FakeTones()
    private lateinit var scheduler: ScheduledExecutorService
    private lateinit var logFile: File

    @Before
    fun setUp() {
        scheduler = Executors.newSingleThreadScheduledExecutor()
        logFile = File(temp.root, "signals.jsonl")
    }

    private fun player(torch: TorchControl) = CourtSignalPlayer(
        scheduler = scheduler,
        clockEstimator = ClockOffsetEstimator(),
        torch = torch,
        tones = tones,
        log = JsonlAppender(logFile),
        slot = { "A" },
        clock = clock,
    )

    private fun drainLog(): List<JSONObject> {
        scheduler.shutdown()
        assertTrue(scheduler.awaitTermination(3, TimeUnit.SECONDS))
        return if (logFile.isFile) logFile.readLines().map { JSONObject(it) } else emptyList()
    }

    @Test
    fun allContractSignalIdsProduceExpectedStepSequences() {
        assertEquals(6, SignalPatterns.forSignal(SignalPatterns.COUNTDOWN)?.size)
        assertEquals(2, SignalPatterns.forSignal(SignalPatterns.REC_START)?.size)
        assertEquals(2, SignalPatterns.forSignal(SignalPatterns.REC_STOP)?.size)
        assertEquals(4, SignalPatterns.forSignal(SignalPatterns.MARKER_ACK)?.size)
        assertEquals(2, SignalPatterns.forSignal(SignalPatterns.LEASE_WARN)?.size)
        assertEquals(1, SignalPatterns.forSignal(SignalPatterns.ERROR)?.size)
        assertEquals(2, SignalPatterns.forSignal(SignalPatterns.SYNC_FLASH)?.size)
        assertNull(SignalPatterns.forSignal("unknown"))
    }

    @Test
    fun unknownSignalIsUnsupportedAndLateSignalIsSkipped() {
        val torch = FakeTorch(true)
        val signalPlayer = player(torch)

        val unknown = signalPlayer.emit(SignalEmit("fireworks", clock.now, null))
        assertEquals(C1NackCode.UNSUPPORTED, (unknown as CommandResult.Nack).code)

        val late = signalPlayer.emit(SignalEmit(SignalPatterns.REC_START, clock.now - 5_000, "s1"))
        assertEquals(CommandResult.Ack, late)

        val line = drainLog().single()
        assertEquals("late_5000ms", line.getString("skipped"))
        assertTrue(line.isNull("playedServerMs"))
        assertEquals("none", line.getString("torch"))
        assertTrue(tones.played.isEmpty())
        assertTrue(torch.calls.isEmpty())
    }

    @Test
    fun recStartAndNoTorchSignalsExecuteStepsAndLog() {
        val torch = FakeTorch(true)
        val signalPlayer = player(torch)

        assertEquals(CommandResult.Ack, signalPlayer.emit(SignalEmit(SignalPatterns.ERROR, clock.now, "s1")))
        assertEquals(CommandResult.Ack, signalPlayer.emit(SignalEmit(SignalPatterns.SYNC_FLASH, clock.now, "s1")))

        val lines = drainLog()
        assertEquals(2, lines.size)
        assertEquals("none", lines[0].getString("torch"))
        assertEquals("ok", lines[1].getString("torch"))
        assertEquals(listOf(SignalTone.LOW to 500), tones.played.toList())
        assertEquals(listOf(true, false), torch.calls.toList())
    }

    @Test
    fun closedCameraSkipsTorchAndRuntimeFailureIsCaught() {
        val closedTorch = FakeTorch(false)
        assertEquals(
            CommandResult.Ack,
            player(closedTorch).emit(SignalEmit(SignalPatterns.MARKER_ACK, clock.now, null)),
        )
        val closedLine = drainLog().single()
        assertEquals("camera_closed", closedLine.getString("torch"))
        assertFalse(closedTorch.calls.isNotEmpty())

        scheduler = Executors.newSingleThreadScheduledExecutor()
        val throwingTones = object : TonePlayer {
            override fun play(tone: SignalTone, durationMs: Int): Unit = error("audio busy")
        }
        val logger = RecordingPhoneLogger()
        val p = CourtSignalPlayer(
            scheduler = scheduler,
            clockEstimator = ClockOffsetEstimator(),
            torch = FakeTorch(true),
            tones = throwingTones,
            log = JsonlAppender(File(temp.root, "signals2.jsonl")),
            slot = { "A" },
            clock = clock,
            logger = logger,
        )
        assertEquals(CommandResult.Ack, p.emit(SignalEmit(SignalPatterns.ERROR, clock.now, null)))
        scheduler.shutdown()
        assertTrue(scheduler.awaitTermination(3, TimeUnit.SECONDS))
        assertTrue(logger.warnings.any { it.contains("Signal step failed.") })
    }
}
