package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CourtStateMachineTest {
    private class FakeRecorder : CourtRecorderPort {
        val calls = mutableListOf<String>()

        override fun prepare(sessionId: String, profile: RecordProfile) {
            calls += "prepare:$sessionId:${profile.fps}"
        }

        override fun start(command: RecordStart, profile: RecordProfile) {
            calls += "start:${command.sessionId}:${profile.fps}"
        }

        override fun refresh(command: RecordStart) {
            calls += "refresh:${command.sessionId}"
        }

        override fun stop(sessionId: String, stopAtServerMs: Long, reason: String) {
            calls += "stop:$sessionId:$reason"
        }

        override fun disarm(sessionId: String) {
            calls += "disarm:$sessionId"
        }
    }

    private var rooted = true
    private val recorder = FakeRecorder()
    private val sessions = InMemoryActiveSessionStore()
    private val machine = CourtStateMachine({ rooted }, recorder, sessions)

    private fun start(sessionId: String = "s1") = machine.onStart(RecordStart.fromJson(recordStartBody(sessionId)))

    private fun prepare(sessionId: String = "s1", fps: Int = 60) =
        machine.onPrepare(RecordPrepare(sessionId, RecordProfile(fps = fps)))

    @Test
    fun notRootedRefusesPrepareAndStart() {
        rooted = false

        assertEquals(C1NackCode.NOT_ROOTED, (prepare() as CommandResult.Nack).code)
        assertEquals(C1NackCode.NOT_ROOTED, (start() as CommandResult.Nack).code)
        assertTrue(recorder.calls.isEmpty())
        assertEquals(CourtStateMachine.Phase.Idle, machine.phase)
        assertEquals(CourtMode.DEGRADED, machine.mode(pendingUploads = false))
        assertNull(sessions.load())
    }

    @Test
    fun prepareArmsWithoutRecording() {
        assertEquals(CommandResult.Ack, prepare())

        assertEquals(listOf("prepare:s1:60"), recorder.calls)
        assertTrue(machine.phase is CourtStateMachine.Phase.Armed)
        assertEquals(CourtMode.ARMED, machine.mode(pendingUploads = false))
        assertNull(machine.activeSessionId)
    }

    @Test
    fun startAfterPrepareKeepsPreparedProfile() {
        prepare()
        assertEquals(CommandResult.Ack, start())

        assertEquals(listOf("prepare:s1:60", "start:s1:60"), recorder.calls)
        assertEquals(CourtMode.RECORDING, machine.mode(pendingUploads = false))
        assertEquals("s1", machine.activeSessionId)
        assertEquals("s1", sessions.load())
    }

    @Test
    fun startForAnotherSessionDisarmsAndUsesDefaultProfile() {
        prepare("s0")
        start("s1")

        assertEquals(listOf("prepare:s0:60", "disarm:s0", "start:s1:30"), recorder.calls)
    }

    @Test
    fun resentStartRefreshesInsteadOfRestarting() {
        start()
        assertEquals(CommandResult.Ack, start())

        assertEquals(listOf("start:s1:30", "refresh:s1"), recorder.calls)
    }

    @Test
    fun otherSessionIsBusyWhileRecording() {
        start("s1")

        assertEquals(C1NackCode.BUSY, (start("s2") as CommandResult.Nack).code)
        assertEquals(C1NackCode.BUSY, (prepare("s2") as CommandResult.Nack).code)
        assertEquals(CommandResult.Ack, prepare("s1"))
        assertEquals(listOf("start:s1:30"), recorder.calls)
    }

    @Test
    fun stopIsIdempotentAndClearsActiveSessionWhenRecorderStops() {
        start()
        assertEquals(CommandResult.Ack, machine.onStop(RecordStop("s1", 99)))
        assertEquals(CommandResult.Ack, machine.onStop(RecordStop("s1", 99)))
        assertTrue(machine.phase is CourtStateMachine.Phase.Stopping)
        assertEquals(C1NackCode.BUSY, (start("s2") as CommandResult.Nack).code)

        machine.onRecorderStopped("s1")

        assertEquals(listOf("start:s1:30", "stop:s1:command"), recorder.calls)
        assertEquals(CourtStateMachine.Phase.Idle, machine.phase)
        assertNull(machine.activeSessionId)
        assertNull(sessions.load())
        assertEquals(CourtMode.UPLOADING, machine.mode(pendingUploads = true))
        assertEquals(CourtMode.IDLE, machine.mode(pendingUploads = false))
    }

    @Test
    fun stopForUnknownSessionIsAckedWithNoEffect() {
        assertEquals(CommandResult.Ack, machine.onStop(RecordStop("nope", 0)))
        assertTrue(recorder.calls.isEmpty())
    }

    @Test
    fun stopWhileArmedDisarms() {
        prepare()
        machine.onStop(RecordStop("s1", 0))

        assertEquals(listOf("prepare:s1:60", "disarm:s1"), recorder.calls)
        assertEquals(CourtStateMachine.Phase.Idle, machine.phase)
    }

    @Test
    fun crashLeftSessionIsFinalizedOnStop() {
        val restarted = CourtStateMachine({ true }, recorder, InMemoryActiveSessionStore("s1"))
        assertEquals("s1", restarted.activeSessionId)

        restarted.onStop(RecordStop("s1", 0))

        assertEquals(listOf("stop:s1:${CourtStateMachine.REASON_RECOVERED}"), recorder.calls)
    }

    @Test
    fun recorderFailureStopsAndRecordsError() {
        start()
        machine.onRecorderFailed("s1", "camera_disconnected")

        assertEquals("camera_disconnected", machine.lastError)
        assertEquals(listOf("start:s1:30", "stop:s1:${CourtStateMachine.REASON_ERROR}"), recorder.calls)
    }

    @Test
    fun localStopUsesGivenReason() {
        start()
        machine.onLocalStop("s1", CourtStateMachine.REASON_MAX_DURATION)
        machine.onLocalStop("s1", CourtStateMachine.REASON_MAX_DURATION)

        assertEquals(listOf("start:s1:30", "stop:s1:${CourtStateMachine.REASON_MAX_DURATION}"), recorder.calls)
    }
}
