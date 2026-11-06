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
 * - Recording only ever begins from `record.start`, for the session `record.prepare` armed; any other
 *   start is refused with `not_prepared` (also after a crash: K2 re-sends prepare, then start).
 * - `record.start` for the session already recording is acked with no effect; another session is `busy`.
 * - `record.stop` is idempotent.
 * - C1 1.11 storage: a prepare with `maxDurationS` and every new start are refused with `storage_full`
 *   when the duration does not fit above the reserve; a recording that runs out stops with
 *   `storage_full`. Segments are never deleted to make room.
 */
class CourtStateMachine(
    private val rooted: () -> Boolean,
    private val recorder: CourtRecorderPort,
    private val activeSessions: ActiveSessionStore,
    private val logger: CourtLogger = NoopCourtLogger,
    private val storage: StorageGuard = StorageGuard({ Long.MAX_VALUE }),
) {
    sealed class Phase {
        object Idle : Phase()

        data class Armed(val sessionId: String, val profile: RecordProfile, val maxDurationS: Int? = null) : Phase()

        data class Recording(val sessionId: String) : Phase()

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

    /** The profile `state.blocked` is measured at: the armed one, else the last one used. */
    private var lastProfile = RecordProfile.DEFAULT

    @Synchronized
    fun onPrepare(command: RecordPrepare): CommandResult {
        if (!rooted()) {
            return notRooted()
        }
        return when (val current = phase) {
            is Phase.Recording -> sameOrBusy(current.sessionId, command.sessionId)
            is Phase.Stopping -> sameOrBusy(current.sessionId, command.sessionId)
            is Phase.Armed -> {
                val refused = refusedPrepare(command)
                if (refused != null) {
                    return refused
                }
                if (current.sessionId != command.sessionId) {
                    recorder.disarm(current.sessionId)
                }
                arm(command)
            }
            Phase.Idle -> refusedPrepare(command) ?: arm(command)
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
            is Phase.Armed -> if (current.sessionId == command.sessionId) {
                begin(command, current)
            } else {
                notPrepared(command.sessionId)
            }
            Phase.Idle -> notPrepared(command.sessionId)
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

    /**
     * C1 1.11: called after each committed segment. Stops the recording with [REASON_STORAGE_FULL]
     * once the next segment would eat into the reserve; every segment already written is kept.
     */
    @Synchronized
    fun checkStorage() {
        val current = phase
        if (current is Phase.Recording && storage.exhausted(lastProfile)) {
            logger.warn(TAG, "Storage below the reserve while recording ${current.sessionId}; stopping.")
            onLocalStop(current.sessionId, REASON_STORAGE_FULL)
        }
    }

    /** `state.blocked`: [StateBody.BLOCKED_STORAGE_FULL] while less than ten minutes fit; else null. */
    @Synchronized
    fun storageBlocked(): String? {
        val profile = (phase as? Phase.Armed)?.profile ?: lastProfile
        return if (storage.blocked(profile)) StateBody.BLOCKED_STORAGE_FULL else null
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
            // A failed prepare: disarm so the port does not keep a half-open camera for a session
            // that will never start (the live preview would otherwise see it as armed and keep it).
            phase = Phase.Idle
            recorder.disarm(sessionId)
        }
    }

    @Synchronized
    fun mode(pendingUploads: Boolean, previewing: Boolean = false): CourtMode = when (phase) {
        is Phase.Recording, is Phase.Stopping -> CourtMode.RECORDING
        is Phase.Armed -> CourtMode.ARMED
        Phase.Idle -> when {
            previewing -> CourtMode.PREVIEWING
            pendingUploads -> CourtMode.UPLOADING
            !rooted() -> CourtMode.DEGRADED
            else -> CourtMode.IDLE
        }
    }

    private fun arm(command: RecordPrepare): CommandResult {
        phase = Phase.Armed(command.sessionId, command.profile, command.maxDurationS)
        lastProfile = command.profile
        recorder.prepare(command.sessionId, command.profile)
        return CommandResult.Ack
    }

    /** A prepare that names a duration is refused when it cannot be stored; without one it is not checked. */
    private fun refusedPrepare(command: RecordPrepare): CommandResult? {
        val seconds = command.maxDurationS ?: return null
        return if (storage.refuses(seconds.toLong(), command.profile)) storageFull(command.sessionId, seconds) else null
    }

    private fun begin(command: RecordStart, armed: Phase.Armed): CommandResult {
        // The start's own limit wins; else the prepare's; else the ten minutes `state.blocked` guards.
        val seconds = command.maxDurationS.takeIf { it > 0 }
            ?: armed.maxDurationS
            ?: StorageGuard.BLOCKED_BELOW_S.toInt()
        if (storage.refuses(seconds.toLong(), armed.profile)) {
            phase = Phase.Idle
            recorder.disarm(command.sessionId)
            return storageFull(command.sessionId, seconds)
        }
        phase = Phase.Recording(command.sessionId)
        setActive(command.sessionId)
        recorder.start(command, armed.profile)
        return CommandResult.Ack
    }

    private fun storageFull(sessionId: String, seconds: Int): CommandResult {
        logger.warn(TAG, "$sessionId: ${seconds}s do not fit above the storage reserve; refused.")
        return CommandResult.Nack(C1NackCode.STORAGE_FULL, "Not enough free storage for ${seconds}s of recording.")
    }

    private fun setActive(sessionId: String?) {
        activeSessionId = sessionId
        activeSessions.save(sessionId)
    }

    private fun sameOrBusy(currentId: String, sessionId: String): CommandResult =
        if (currentId == sessionId) CommandResult.Ack else busy(currentId)

    private fun busy(currentSessionId: String): CommandResult =
        CommandResult.Nack(C1NackCode.BUSY, "Recording session $currentSessionId.")

    private fun notPrepared(sessionId: String): CommandResult {
        logger.warn(TAG, "record.start for $sessionId without record.prepare; refused.")
        return CommandResult.Nack(C1NackCode.NOT_PREPARED, "Send record.prepare for $sessionId first.")
    }

    private fun notRooted(): CommandResult =
        CommandResult.Nack(C1NackCode.NOT_ROOTED, "Court recording needs a rooted device.")

    companion object {
        const val REASON_COMMAND = "command"
        const val REASON_MAX_DURATION = "max_duration"
        const val REASON_ERROR = "error"
        const val REASON_RECOVERED = "recovered"

        /** C1 1.11 `recording.stopped.reason`: free space ran down to the reserve mid-recording. */
        const val REASON_STORAGE_FULL = "storage_full"
        private const val TAG = "CourtState"
    }
}
