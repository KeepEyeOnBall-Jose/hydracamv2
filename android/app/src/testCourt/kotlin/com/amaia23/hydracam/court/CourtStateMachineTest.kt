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

    /** prepare (30 fps) + start; only the start shows in [FakeRecorder.calls]. */
    private fun record(sessionId: String = "s1"): CommandResult {
        prepare(sessionId, fps = 30)
        recorder.calls.removeAt(recorder.calls.lastIndex)
        return start(sessionId)
    }

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
    fun startWithoutPrepareIsRefused() {
        val result = start() as CommandResult.Nack

        assertEquals(C1NackCode.NOT_PREPARED, result.code)
        assertTrue(recorder.calls.isEmpty())
        assertEquals(CourtStateMachine.Phase.Idle, machine.phase)
        assertNull(machine.activeSessionId)
        assertNull(sessions.load())
    }

    @Test
    fun startForAnotherSessionIsRefusedAndKeepsThePreparedCamera() {
        prepare("s0")

        assertEquals(C1NackCode.NOT_PREPARED, (start("s1") as CommandResult.Nack).code)

        assertEquals(listOf("prepare:s0:60"), recorder.calls)
        assertEquals(CourtStateMachine.Phase.Armed("s0", RecordProfile(fps = 60)), machine.phase)
        assertEquals(CommandResult.Ack, start("s0"))
    }

    @Test
    fun crashLeftSessionResumesOnlyAfterPrepare() {
        val restarted = CourtStateMachine({ true }, recorder, InMemoryActiveSessionStore("s1"))

        val bare = restarted.onStart(RecordStart.fromJson(recordStartBody("s1"))) as CommandResult.Nack
        restarted.onPrepare(RecordPrepare("s1", RecordProfile(fps = 50)))
        val resumed = restarted.onStart(RecordStart.fromJson(recordStartBody("s1")))

        assertEquals(C1NackCode.NOT_PREPARED, bare.code)
        assertEquals(CommandResult.Ack, resumed)
        assertEquals(listOf("prepare:s1:50", "start:s1:50"), recorder.calls)
    }

    @Test
    fun resentStartRefreshesInsteadOfRestarting() {
        record()
        assertEquals(CommandResult.Ack, start())

        assertEquals(listOf("start:s1:30", "refresh:s1"), recorder.calls)
    }

    @Test
    fun otherSessionIsBusyWhileRecording() {
        record("s1")

        assertEquals(C1NackCode.BUSY, (start("s2") as CommandResult.Nack).code)
        assertEquals(C1NackCode.BUSY, (prepare("s2") as CommandResult.Nack).code)
        assertEquals(CommandResult.Ack, prepare("s1"))
        assertEquals(listOf("start:s1:30"), recorder.calls)
    }

    @Test
    fun stopIsIdempotentAndClearsActiveSessionWhenRecorderStops() {
        record()
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
        record()
        machine.onRecorderFailed("s1", "camera_disconnected")

        assertEquals("camera_disconnected", machine.lastError)
        assertEquals(listOf("start:s1:30", "stop:s1:${CourtStateMachine.REASON_ERROR}"), recorder.calls)
    }

    @Test
    fun prepareForAnotherSessionDisarmsTheFirst() {
        prepare("s0")
        assertEquals(CommandResult.Ack, prepare("s1", fps = 25))
        assertEquals(CommandResult.Ack, prepare("s1", fps = 50))

        assertEquals(listOf("prepare:s0:60", "disarm:s0", "prepare:s1:25", "prepare:s1:50"), recorder.calls)
        assertEquals(CourtStateMachine.Phase.Armed("s1", RecordProfile(fps = 50)), machine.phase)
    }

    @Test
    fun whileStoppingTheSameSessionIsAckedAndOthersAreBusy() {
        record("s1")
        machine.onStop(RecordStop("s1", 0))

        assertEquals(CommandResult.Ack, prepare("s1"))
        assertEquals(C1NackCode.BUSY, (prepare("s2") as CommandResult.Nack).code)
        assertEquals(CourtMode.RECORDING, machine.mode(pendingUploads = true))
        assertEquals(listOf("start:s1:30", "stop:s1:command"), recorder.calls)
    }

    @Test
    fun eventsForOtherSessionsLeaveTheRecordingAlone() {
        record("s1")

        machine.onStop(RecordStop("s2", 0))
        machine.onLocalStop("s2", CourtStateMachine.REASON_MAX_DURATION)
        machine.onRecorderFailed("s2", "camera_busy")
        machine.onRecorderStopped("s2")

        assertTrue(machine.phase is CourtStateMachine.Phase.Recording)
        assertEquals("s1", machine.activeSessionId)
        assertEquals("camera_busy", machine.lastError)
        assertEquals(listOf("start:s1:30"), recorder.calls)
    }

    @Test
    fun armedPhaseIgnoresOtherSessionsAndRecorderFailureDisarms() {
        prepare("s1")

        machine.onStop(RecordStop("s2", 0))
        machine.onLocalStop("s1", CourtStateMachine.REASON_MAX_DURATION)
        machine.onRecorderFailed("s2", "camera_busy")
        machine.onRecorderStopped("s1")
        assertTrue(machine.phase is CourtStateMachine.Phase.Armed)

        machine.onRecorderFailed("s1", "camera_open_failed")

        assertEquals(CourtStateMachine.Phase.Idle, machine.phase)
        assertEquals("camera_open_failed", machine.lastError)
        assertEquals(listOf("prepare:s1:60"), recorder.calls)
    }

    @Test
    fun recorderStoppingByItselfEndsTheRecording() {
        record("s1")

        machine.onRecorderStopped("s1")

        assertEquals(CourtStateMachine.Phase.Idle, machine.phase)
        assertNull(machine.activeSessionId)
    }

    @Test
    fun idleRecorderFailureOnlyRecordsTheError() {
        machine.onRecorderFailed("s1", "camera_disconnected")

        assertEquals(CourtStateMachine.Phase.Idle, machine.phase)
        assertEquals("camera_disconnected", machine.lastError)
        assertTrue(recorder.calls.isEmpty())
    }

    @Test
    fun localStopUsesGivenReason() {
        record()
        machine.onLocalStop("s1", CourtStateMachine.REASON_MAX_DURATION)
        machine.onLocalStop("s1", CourtStateMachine.REASON_MAX_DURATION)

        assertEquals(listOf("start:s1:30", "stop:s1:${CourtStateMachine.REASON_MAX_DURATION}"), recorder.calls)
    }
}
