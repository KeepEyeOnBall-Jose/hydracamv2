package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** C1 1.11 storage guard on the record lifecycle. The default profile records 8000 + 2000 kbps = 1.25 MB/s. */
class CourtStateMachineStorageTest {
    private class FakeRecorder : CourtRecorderPort {
        val calls = mutableListOf<String>()

        override fun prepare(sessionId: String, profile: RecordProfile, capture: CaptureTarget) {
            calls += "prepare:$sessionId:${profile.fps}"
        }

        override fun start(command: RecordStart, profile: RecordProfile, capture: CaptureTarget) {
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

    private val recorder = FakeRecorder()
    private var freeBytes = Long.MAX_VALUE
    private val guarded = CourtStateMachine(
        { true },
        recorder,
        InMemoryActiveSessionStore(),
        storage = StorageGuard({ freeBytes }),
    )
    private val anHour = StorageGuard.RESERVE_BYTES + 4_500_000_000L
    private val tenMinutes = StorageGuard.RESERVE_BYTES + 750_000_000L

    private fun guardedPrepare(
        sessionId: String = "s1",
        maxDurationS: Int? = null,
        profile: RecordProfile = RecordProfile(),
    ) = guarded.onPrepare(RecordPrepare(sessionId, profile, maxDurationS))

    private fun guardedStart(sessionId: String = "s1", maxDurationS: Int = 600) =
        guarded.onStart(RecordStart.fromJson(recordStartBody(sessionId).put("maxDurationS", maxDurationS)))

    private fun storageFull(result: CommandResult) =
        assertEquals(C1NackCode.STORAGE_FULL, (result as CommandResult.Nack).code)

    @Test
    fun prepareWhoseDurationDoesNotFitIsStorageFull() {
        freeBytes = anHour - 1
        storageFull(guardedPrepare(maxDurationS = 3_600))
        assertEquals(CourtStateMachine.Phase.Idle, guarded.phase)
        assertTrue(recorder.calls.isEmpty())

        freeBytes = anHour
        assertEquals(CommandResult.Ack, guardedPrepare(maxDurationS = 3_600))
        assertEquals(CourtStateMachine.Phase.Armed("s1", RecordProfile(), 3_600), guarded.phase)
    }

    @Test
    fun prepareWithoutADurationIsNotRefused() {
        freeBytes = 0
        assertEquals(CommandResult.Ack, guardedPrepare())
    }

    @Test
    fun aRefusedPrepareLeavesTheArmedSessionAlone() {
        guardedPrepare("s0")
        freeBytes = 0

        storageFull(guardedPrepare("s1", maxDurationS = 60))

        assertEquals(CourtStateMachine.Phase.Armed("s0", RecordProfile()), guarded.phase)
        assertEquals(listOf("prepare:s0:30"), recorder.calls)
    }

    @Test
    fun startChecksItsOwnDurationBeforeThePrepares() {
        freeBytes = anHour
        guardedPrepare(maxDurationS = 3_600)
        freeBytes = tenMinutes

        assertEquals(CommandResult.Ack, guardedStart(maxDurationS = 600))
        assertEquals("s1", guarded.activeSessionId)
    }

    @Test
    fun startWithoutADurationUsesThePreparesAndDisarmsWhenItDoesNotFit() {
        freeBytes = anHour
        guardedPrepare(maxDurationS = 3_600)
        freeBytes = anHour - 1

        storageFull(guardedStart(maxDurationS = 0))

        assertEquals(CourtStateMachine.Phase.Idle, guarded.phase)
        assertNull(guarded.activeSessionId)
        assertEquals(listOf("prepare:s1:30", "disarm:s1"), recorder.calls)
    }

    @Test
    fun startWithNoDurationAnywhereNeedsTenMinutes() {
        guardedPrepare()
        freeBytes = tenMinutes - 1
        storageFull(guardedStart(maxDurationS = 0))

        guardedPrepare()
        freeBytes = tenMinutes
        assertEquals(CommandResult.Ack, guardedStart(maxDurationS = 0))
    }

    @Test
    fun aResentStartForTheRecordingSessionIsNotChecked() {
        guardedPrepare()
        guardedStart()
        freeBytes = 0

        assertEquals(CommandResult.Ack, guardedStart())
    }

    @Test
    fun runningOutMidRecordingStopsWithStorageFull() {
        guardedPrepare()
        guardedStart()

        // One 6 s segment (7.5 MB) still fits above the reserve.
        freeBytes = StorageGuard.RESERVE_BYTES + 7_500_000L
        guarded.checkStorage()
        assertTrue(guarded.phase is CourtStateMachine.Phase.Recording)

        freeBytes -= 1
        guarded.checkStorage()
        guarded.checkStorage()

        assertTrue(guarded.phase is CourtStateMachine.Phase.Stopping)
        assertEquals(
            listOf("prepare:s1:30", "start:s1:30", "stop:s1:${CourtStateMachine.REASON_STORAGE_FULL}"),
            recorder.calls,
        )
    }

    @Test
    fun checkStorageOutsideARecordingDoesNothing() {
        freeBytes = 0
        guarded.checkStorage()
        guardedPrepare()
        guarded.checkStorage()

        assertTrue(guarded.phase is CourtStateMachine.Phase.Armed)
        assertEquals(listOf("prepare:s1:30"), recorder.calls)
    }

    @Test
    fun stateIsBlockedWhileLessThanTenMinutesFitAtTheSessionRate() {
        freeBytes = tenMinutes
        assertNull(guarded.storageBlocked())

        freeBytes -= 1
        assertEquals(StateBody.BLOCKED_STORAGE_FULL, guarded.storageBlocked())

        // A lighter armed profile (1500 kbps) fits ten minutes in the same space.
        guardedPrepare(profile = RecordProfile(masterKbps = 1_000, proxyKbps = 500))
        assertNull(guarded.storageBlocked())

        // The last profile still sets the rate once the device is idle again.
        guarded.onStop(RecordStop("s1", 0))
        assertNull(guarded.storageBlocked())
        // Without a storage probe the guard never blocks.
        assertNull(CourtStateMachine({ true }, recorder, InMemoryActiveSessionStore()).storageBlocked())
    }
}
