package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CourtStateMachineTest {
    private class FakeRecorder : CourtRecorderPort {
        val calls = mutableListOf<String>()
        val captures = mutableListOf<CaptureTarget>()
        var refusal: CaptureUnsupported? = null

        override fun unsupported(profile: RecordProfile, capture: CaptureTarget): CaptureUnsupported? = refusal

        override fun prepare(sessionId: String, profile: RecordProfile, capture: CaptureTarget) {
            calls += "prepare:$sessionId:${profile.fps}"
            captures += capture
        }

        override fun start(command: RecordStart, profile: RecordProfile, capture: CaptureTarget) {
            calls += "start:${command.sessionId}:${profile.fps}"
            captures += capture
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
    private var freeBytes = Long.MAX_VALUE
    private val recorder = FakeRecorder()
    private val sessions = InMemoryActiveSessionStore()
    private val machine = CourtStateMachine(
        rooted = { rooted },
        recorder = recorder,
        activeSessions = sessions,
        storage = StorageGuard({ freeBytes }),
    )

    private fun prepare(
        sessionId: String = "s1",
        fps: Int = 30,
        maxDurationS: Int? = null,
        capture: CaptureTarget? = null,
    ) = machine.onPrepare(RecordPrepare(sessionId, RecordProfile(fps = fps), maxDurationS, capture))

    private fun start(sessionId: String = "s1", maxDurationS: Int = 600) =
        machine.onStart(RecordStart.fromJson(testRecordStartBody(sessionId).put("maxDurationS", maxDurationS)))

    @Test
    fun notRootedRefusesPrepareAndStartAndReportsDegradedMode() {
        rooted = false

        assertEquals(C1NackCode.NOT_ROOTED, (prepare() as CommandResult.Nack).code)
        assertEquals(C1NackCode.NOT_ROOTED, (start() as CommandResult.Nack).code)
        assertTrue(recorder.calls.isEmpty())
        assertEquals(CourtStateMachine.Phase.Idle, machine.phase)
        assertEquals(CourtMode.DEGRADED, machine.mode(pendingUploads = false))
        assertEquals(CourtMode.PREVIEWING, machine.mode(pendingUploads = true, previewing = true))
    }

    @Test
    fun prepareStartRefreshBusyAndStopLifecycle() {
        val tele = CaptureTarget(lens = CaptureTarget.LENS_TELE)
        assertEquals(CommandResult.Ack, prepare("s1", fps = 60, capture = tele))
        assertEquals(CourtMode.ARMED, machine.mode(pendingUploads = true, previewing = true))
        assertEquals(C1NackCode.NOT_PREPARED, (start("other") as CommandResult.Nack).code)
        assertEquals(CommandResult.Ack, start("s1"))
        assertEquals(CourtMode.RECORDING, machine.mode(pendingUploads = false, previewing = true))
        assertEquals("s1", machine.activeSessionId)
        assertEquals("s1", sessions.load())

        assertEquals(CommandResult.Ack, start("s1"))
        assertEquals(CommandResult.Ack, prepare("s1"))
        assertEquals(C1NackCode.BUSY, (start("s2") as CommandResult.Nack).code)
        assertEquals(C1NackCode.BUSY, (prepare("s2") as CommandResult.Nack).code)

        assertEquals(CommandResult.Ack, machine.onStop(RecordStop("s1", 99)))
        assertEquals(CommandResult.Ack, machine.onStop(RecordStop("s1", 99)))
        assertTrue(machine.phase is CourtStateMachine.Phase.Stopping)
        assertEquals(CommandResult.Ack, prepare("s1"))
        assertEquals(C1NackCode.BUSY, (prepare("s2") as CommandResult.Nack).code)
        assertEquals(C1NackCode.BUSY, (start("s2") as CommandResult.Nack).code)

        machine.onRecorderStopped("s1")
        assertEquals(CourtStateMachine.Phase.Idle, machine.phase)
        assertNull(machine.activeSessionId)
        assertNull(sessions.load())
        assertEquals(CourtMode.UPLOADING, machine.mode(pendingUploads = true))
        assertEquals(CourtMode.IDLE, machine.mode(pendingUploads = false))
        assertEquals(
            listOf("prepare:s1:60", "start:s1:60", "refresh:s1", "stop:s1:${CourtStateMachine.REASON_COMMAND}"),
            recorder.calls,
        )
        assertEquals(2, recorder.captures.size)
        assertEquals(CaptureTarget.LENS_TELE, recorder.captures[0].lens)
    }

    @Test
    fun reprepareDisarmsPreviousAndStopWhileArmedDisarms() {
        assertEquals(CommandResult.Ack, prepare("s0"))
        assertEquals(CommandResult.Ack, prepare("s1", fps = 50))
        assertEquals(CommandResult.Ack, machine.onStop(RecordStop("s1", 0)))
        assertEquals(CommandResult.Ack, machine.onStop(RecordStop("missing", 0)))

        assertEquals(listOf("prepare:s0:30", "disarm:s0", "prepare:s1:50", "disarm:s1"), recorder.calls)
        assertEquals(CourtStateMachine.Phase.Idle, machine.phase)
    }

    @Test
    fun recoveredCrashSessionCanStopOrRePrepareBeforeStart() {
        val restarted = CourtStateMachine({ true }, recorder, InMemoryActiveSessionStore("s1"))
        assertEquals("s1", restarted.activeSessionId)
        val bare = restarted.onStart(RecordStart.fromJson(testRecordStartBody("s1"))) as CommandResult.Nack
        assertEquals(C1NackCode.NOT_PREPARED, bare.code)

        assertEquals(CommandResult.Ack, restarted.onStop(RecordStop("s1", 0)))
        assertEquals(listOf("stop:s1:${CourtStateMachine.REASON_RECOVERED}"), recorder.calls)
        restarted.onRecorderStopped("s1")
        assertNull(restarted.activeSessionId)
    }

    @Test
    fun failureAndLocalStopTransitionsHandleMatchingAndForeignSessions() {
        prepare("s1")
        machine.onLocalStop("s1", CourtStateMachine.REASON_MAX_DURATION)
        machine.onRecorderFailed("other", "ignored_phase")
        assertTrue(machine.phase is CourtStateMachine.Phase.Armed)
        assertEquals("ignored_phase", machine.lastError)

        machine.onRecorderFailed("s1", "camera_open_failed")
        assertEquals(CourtStateMachine.Phase.Idle, machine.phase)

        prepare("s2")
        start("s2")
        machine.onLocalStop("other", CourtStateMachine.REASON_MAX_DURATION)
        assertTrue(machine.phase is CourtStateMachine.Phase.Recording)
        machine.onRecorderFailed("s2", "camera_disconnected")
        assertTrue(machine.phase is CourtStateMachine.Phase.Stopping)
        assertEquals(
            listOf(
                "prepare:s1:30",
                "disarm:s1",
                "prepare:s2:30",
                "start:s2:30",
                "stop:s2:${CourtStateMachine.REASON_ERROR}",
            ),
            recorder.calls,
        )
    }

    @Test
    fun unsupportedAndStorageGuardChecksEnforceLimits() {
        recorder.refusal = CaptureUnsupported("profile.fps", "no 60 fps")
        val unsupported = prepare(fps = 60) as CommandResult.Nack
        assertEquals(C1NackCode.UNSUPPORTED, unsupported.code)
        assertEquals("profile.fps: no 60 fps", unsupported.reason)
        recorder.refusal = null

        val tenMinutes = StorageGuard.RESERVE_BYTES + 750_000_000L
        freeBytes = tenMinutes - 1
        assertEquals(StateBody.BLOCKED_STORAGE_FULL, machine.storageBlocked())
        assertEquals(C1NackCode.STORAGE_FULL, (prepare(maxDurationS = 600) as CommandResult.Nack).code)

        freeBytes = StorageGuard.RESERVE_BYTES + 1_500_000_000L
        assertNull(machine.storageBlocked())
        assertEquals(CommandResult.Ack, prepare(maxDurationS = 1_200))
        freeBytes = tenMinutes
        assertEquals(C1NackCode.STORAGE_FULL, (start(maxDurationS = 0) as CommandResult.Nack).code)
        assertEquals(CourtStateMachine.Phase.Idle, machine.phase)

        prepare()
        start(maxDurationS = 600)
        freeBytes = StorageGuard.RESERVE_BYTES + 7_500_000L - 1
        machine.checkStorage()
        assertTrue(machine.phase is CourtStateMachine.Phase.Stopping)
        assertEquals(CourtStateMachine.REASON_STORAGE_FULL, recorder.calls.last().substringAfterLast(':'))
    }
}
