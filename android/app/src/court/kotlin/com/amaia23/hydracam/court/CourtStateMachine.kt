package com.amaia23.hydracam.court

/** What the state machine asks of the camera pipeline. Every call returns quickly; work is async. */
interface CourtRecorderPort {
    /** Open the camera, warm up and lock AE/AF/AWB. */
    fun prepare(sessionId: String, profile: RecordProfile)

    /** Start (or resume after a crash) segmenting [command.sessionId] at `startAtServerMs`. */
    fun start(command: RecordStart, profile: RecordProfile)

    /** K2 re-sent `record.start` for the session already recording: keep going, refresh the grant. */
    fun refresh(command: RecordStart)

    /**
     * Stop at [stopAtServerMs] (0 = now) and emit `recording.stopped`. Also called for a session left
     * active by a crash, so the port must finalize from persisted state when nothing is running.
     */
    fun stop(sessionId: String, stopAtServerMs: Long, reason: String)

    /** Close a prepared-but-unused camera. */
    fun disarm(sessionId: String)
}

/** Persists the session the device was recording, so `hello.activeSessionId` survives process death. */
interface ActiveSessionStore {
    fun load(): String?

    fun save(sessionId: String?)
}

class InMemoryActiveSessionStore(private var value: String? = null) : ActiveSessionStore {
    @Synchronized
    override fun load(): String? = value

    @Synchronized
    override fun save(sessionId: String?) {
        value = sessionId
    }
}

/**
 * Court device record lifecycle (H4/H15 + C1 resend rules).
 *
 * - Not rooted: `record.prepare`/`record.start` are refused with `not_rooted`.
 * - Recording only ever begins from `record.start`.
 * - `record.start` for the session already recording is acked with no effect; another session is `busy`.
 * - `record.stop` is idempotent.
 */
class CourtStateMachine(
    private val rooted: () -> Boolean,
    private val recorder: CourtRecorderPort,
    private val activeSessions: ActiveSessionStore,
    private val logger: CourtLogger = NoopCourtLogger,
) {
    sealed class Phase {
        object Idle : Phase()

        data class Armed(val sessionId: String, val profile: RecordProfile) : Phase()

        data class Recording(val sessionId: String, val leaseId: String, val profile: RecordProfile) : Phase()

        data class Stopping(val sessionId: String) : Phase()
    }

    @get:Synchronized
    var phase: Phase = Phase.Idle
        private set

    @get:Synchronized
    @set:Synchronized
    var lastError: String? = null

    @get:Synchronized
    var activeSessionId: String? = activeSessions.load()
        private set

    @Synchronized
    fun onPrepare(command: RecordPrepare): CommandResult {
        if (!rooted()) {
            return notRooted()
        }
        return when (val current = phase) {
            is Phase.Recording, is Phase.Stopping -> sameOrBusy(current, command.sessionId)
            is Phase.Armed -> {
                if (current.sessionId != command.sessionId) {
                    recorder.disarm(current.sessionId)
                }
                arm(command)
            }
            Phase.Idle -> arm(command)
        }
    }

    @Synchronized
    fun onStart(command: RecordStart): CommandResult {
        if (!rooted()) {
            return notRooted()
        }
        return when (val current = phase) {
            is Phase.Recording -> {
                if (current.sessionId == command.sessionId) {
                    logger.info(TAG, "record.start re-sent for ${command.sessionId}; still recording.")
                    recorder.refresh(command)
                    CommandResult.Ack
                } else {
                    busy(current.sessionId)
                }
            }
            is Phase.Stopping -> busy(current.sessionId)
            is Phase.Armed -> {
                val profile = if (current.sessionId == command.sessionId) {
                    current.profile
                } else {
                    recorder.disarm(current.sessionId)
                    RecordProfile.DEFAULT
                }
                begin(command, profile)
            }
            Phase.Idle -> begin(command, RecordProfile.DEFAULT)
        }
    }

    @Synchronized
    fun onStop(command: RecordStop): CommandResult {
        val current = phase
        when {
            current is Phase.Recording && current.sessionId == command.sessionId -> {
                phase = Phase.Stopping(command.sessionId)
                recorder.stop(command.sessionId, command.stopAtServerMs, REASON_COMMAND)
            }
            current is Phase.Armed && current.sessionId == command.sessionId -> {
                phase = Phase.Idle
                recorder.disarm(command.sessionId)
            }
            current is Phase.Idle && activeSessionId == command.sessionId -> {
                // Left active by a crash: let the port send recording.stopped from persisted seqs.
                phase = Phase.Stopping(command.sessionId)
                recorder.stop(command.sessionId, command.stopAtServerMs, REASON_RECOVERED)
            }
            else -> logger.info(TAG, "record.stop for ${command.sessionId}: nothing to stop.")
        }
        return CommandResult.Ack
    }

    /** Local stop (max duration, thermal, error) for the current session. */
    @Synchronized
    fun onLocalStop(sessionId: String, reason: String) {
        val current = phase
        if (current is Phase.Recording && current.sessionId == sessionId) {
            phase = Phase.Stopping(sessionId)
            recorder.stop(sessionId, 0, reason)
        }
    }

    @Synchronized
    fun onRecorderStopped(sessionId: String) {
        val stoppedSession = when (val current = phase) {
            is Phase.Stopping -> current.sessionId
            is Phase.Recording -> current.sessionId
            else -> null
        }
        if (stoppedSession == sessionId) {
            phase = Phase.Idle
        }
        if (activeSessionId == sessionId) {
            setActive(null)
        }
    }

    @Synchronized
    fun onRecorderFailed(sessionId: String, error: String) {
        lastError = error
        logger.warn(TAG, "Recorder failed for $sessionId: $error")
        val current = phase
        if (current is Phase.Recording && current.sessionId == sessionId) {
            phase = Phase.Stopping(sessionId)
            recorder.stop(sessionId, 0, REASON_ERROR)
        } else if (current is Phase.Armed && current.sessionId == sessionId) {
            phase = Phase.Idle
        }
    }

    @Synchronized
    fun mode(pendingUploads: Boolean): CourtMode = when (phase) {
        is Phase.Recording, is Phase.Stopping -> CourtMode.RECORDING
        is Phase.Armed -> CourtMode.ARMED
        Phase.Idle -> when {
            pendingUploads -> CourtMode.UPLOADING
            !rooted() -> CourtMode.DEGRADED
            else -> CourtMode.IDLE
        }
    }

    private fun arm(command: RecordPrepare): CommandResult {
        phase = Phase.Armed(command.sessionId, command.profile)
        recorder.prepare(command.sessionId, command.profile)
        return CommandResult.Ack
    }

    private fun begin(command: RecordStart, profile: RecordProfile): CommandResult {
        phase = Phase.Recording(command.sessionId, command.leaseId, profile)
        setActive(command.sessionId)
        recorder.start(command, profile)
        return CommandResult.Ack
    }

    private fun setActive(sessionId: String?) {
        activeSessionId = sessionId
        activeSessions.save(sessionId)
    }

    private fun sameOrBusy(current: Phase, sessionId: String): CommandResult {
        val currentId = when (current) {
            is Phase.Recording -> current.sessionId
            is Phase.Stopping -> current.sessionId
            else -> null
        }
        return if (currentId == sessionId) CommandResult.Ack else busy(currentId)
    }

    private fun busy(currentSessionId: String?): CommandResult =
        CommandResult.Nack(C1NackCode.BUSY, "Recording session $currentSessionId.")

    private fun notRooted(): CommandResult =
        CommandResult.Nack(C1NackCode.NOT_ROOTED, "Court recording needs a rooted device.")

    companion object {
        const val REASON_COMMAND = "command"
        const val REASON_MAX_DURATION = "max_duration"
        const val REASON_ERROR = "error"
        const val REASON_RECOVERED = "recovered"
        private const val TAG = "CourtState"
    }
}
