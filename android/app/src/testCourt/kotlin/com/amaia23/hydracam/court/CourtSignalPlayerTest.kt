package com.amaia23.hydracam.court

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

    private val clock = FakeClock()
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

    /** Lets every scheduled step run, then reads the log. */
    private fun drainLog(): List<JSONObject> {
        scheduler.shutdown()
        assertTrue(scheduler.awaitTermination(3, TimeUnit.SECONDS))
        return if (logFile.isFile) logFile.readLines().map { JSONObject(it) } else emptyList()
    }

    @Test
    fun unknownSignalIsUnsupported() {
        val result = player(FakeTorch(true)).emit(SignalEmit("fireworks", clock.now, null))

        assertEquals(C1NackCode.UNSUPPORTED, (result as CommandResult.Nack).code)
        assertTrue(drainLog().isEmpty())
    }

    @Test
    fun lateSignalIsSkippedAndLogged() {
        val torch = FakeTorch(true)
        val result = player(torch).emit(SignalEmit(SignalPatterns.REC_START, clock.now - 5_000, "s1"))

        assertEquals(CommandResult.Ack, result)
        val line = drainLog().single()
        assertEquals("late_5000ms", line.getString("skipped"))
        assertTrue(line.isNull("playedServerMs"))
        assertEquals("none", line.getString("torch"))
        assertTrue(tones.played.isEmpty())
        assertTrue(torch.calls.isEmpty())
    }

    @Test
    fun recStartPlaysToneAndTorchAtServerTime() {
        val torch = FakeTorch(true)
        val result = player(torch).emit(SignalEmit(SignalPatterns.REC_START, clock.now + 20, "s1"))

        assertEquals(CommandResult.Ack, result)
        val line = drainLog().single()
        assertEquals(SignalPatterns.REC_START, line.getString("signal"))
        assertEquals(clock.now + 20, line.getLong("atServerMs"))
        assertEquals("A", line.getString("slot"))
        assertEquals("s1", line.getString("sessionId"))
        assertEquals("ok", line.getString("torch"))
        // No clock estimate yet (offset 0) and the fake clock does not move.
        assertEquals(clock.now, line.getLong("playedServerMs"))
        assertEquals(listOf(SignalTone.HIGH to 700), tones.played.toList())
        assertEquals(listOf(true, false), torch.calls.toList())
    }

    @Test
    fun closedCameraSkipsTorchButPlaysTones() {
        val torch = FakeTorch(false)
        player(torch).emit(SignalEmit(SignalPatterns.MARKER_ACK, clock.now, null))

        val line = drainLog().single()
        assertEquals("camera_closed", line.getString("torch"))
        assertTrue(line.isNull("sessionId"))
        assertEquals(listOf(SignalTone.MID to 100, SignalTone.HIGH to 100), tones.played.toList())
        assertFalse(torch.calls.isNotEmpty())
    }
}
