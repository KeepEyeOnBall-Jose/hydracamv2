package com.amaia23.hydracam.phonecore

import java.io.File

/**
 * Pure-JVM command bridge between Flutter `MethodChannel` payloads
 * (`hydracamv2/phonecore_live_upload`) and [PhoneCoreLiveSessionUploader].
 */
class PhoneCoreLiveUploadDispatcher(private val uploader: PhoneCoreLiveSessionUploader) {
    class UnknownCommandException(command: String) : IllegalArgumentException("Unknown command: $command")

    fun supports(command: String): Boolean = isSupportedCommand(command)

    fun dispatch(command: String, arguments: Map<String, Any?>? = null): Map<String, Any?>? = when (command) {
        COMMAND_START_SESSION -> startSession(requireArguments(arguments))
        COMMAND_ENQUEUE_SEGMENT -> enqueueSegment(requireArguments(arguments))
        COMMAND_MARK_RECORDING_STOPPED -> markRecordingStopped(requireArguments(arguments))
        COMMAND_DRAIN_ONCE -> drainOnce(arguments)
        COMMAND_GET_SNAPSHOT -> getSnapshot(requireArguments(arguments))
        COMMAND_HAS_PENDING_WORK -> hasPendingWork()
        else -> throw UnknownCommandException(command)
    }

    private fun startSession(args: Map<String, Any?>): Map<String, Any?> {
        val sessionId = requireString(args, KEY_SESSION_ID)
        val slot = requireString(args, KEY_SLOT)
        val uploadGrant = requireString(args, KEY_UPLOAD_GRANT)
        val ingestUrl = requireString(args, KEY_INGEST_URL)
        val nowMs = optionalLong(args, KEY_NOW_MS)
        if (nowMs != null) {
            require(nowMs >= 0) { "$KEY_NOW_MS must be >= 0." }
            uploader.startSession(sessionId, slot, uploadGrant, ingestUrl, nowMs)
        } else {
            uploader.startSession(sessionId, slot, uploadGrant, ingestUrl)
        }
        return requireNotNull(uploader.snapshot(sessionId)).toMap()
    }

    private fun enqueueSegment(args: Map<String, Any?>): Map<String, Any?> {
        val sessionId = requireString(args, KEY_SESSION_ID)
        require(CourtIds.isSafe(sessionId)) { "Unsafe $KEY_SESSION_ID: $sessionId" }
        require(uploader.snapshot(sessionId) != null) { "Unknown $KEY_SESSION_ID: $sessionId" }
        val slot = requireString(args, KEY_SLOT)
        val tier = requireString(args, KEY_TIER)
        val seq = requireLong(args, KEY_SEQ)
        val filePath = requireString(args, KEY_FILE_PATH)
        val sha256 = requireString(args, KEY_SHA256)
        val mediaStartServerMs = requireLong(args, KEY_MEDIA_START_SERVER_MS)
        val durationMs = requireLong(args, KEY_DURATION_MS)
        val nowMs = optionalLong(args, KEY_NOW_MS)
        if (nowMs != null) {
            require(nowMs >= 0) { "$KEY_NOW_MS must be >= 0." }
        }
        uploader.enqueueSegment(
            sessionId = sessionId,
            slot = slot,
            tier = tier,
            seq = seq,
            file = File(filePath),
            sha256 = sha256,
            mediaStartServerMs = mediaStartServerMs,
            durationMs = durationMs,
        )
        return requireNotNull(uploader.snapshot(sessionId)).toMap()
    }

    private fun markRecordingStopped(args: Map<String, Any?>): Map<String, Any?>? {
        val sessionId = requireString(args, KEY_SESSION_ID)
        require(CourtIds.isSafe(sessionId)) { "Unsafe $KEY_SESSION_ID: $sessionId" }
        val stoppedAtMs = optionalLong(args, KEY_STOPPED_AT_MS)
        val updated = if (stoppedAtMs != null) {
            uploader.markRecordingStopped(sessionId, stoppedAtMs)
        } else {
            uploader.markRecordingStopped(sessionId)
        } ?: return null
        return requireNotNull(uploader.snapshot(updated.sessionId)).toMap()
    }

    private fun drainOnce(arguments: Map<String, Any?>?): Map<String, Any?> {
        val maxStepsLong = optionalLong(arguments, KEY_MAX_STEPS) ?: DEFAULT_MAX_DRAIN_STEPS.toLong()
        require(maxStepsLong in MIN_DRAIN_STEPS.toLong()..MAX_DRAIN_STEPS.toLong()) {
            "$KEY_MAX_STEPS must be in $MIN_DRAIN_STEPS..$MAX_DRAIN_STEPS."
        }
        val maxSteps = maxStepsLong.toInt()
        var stepsTaken = 0
        while (stepsTaken < maxSteps && uploader.drainOnce()) {
            stepsTaken += 1
        }
        val nextWakeAtMs = uploader.nextWakeAtMs()
        return mapOf(
            "stepsTaken" to stepsTaken,
            "didWork" to (stepsTaken > 0),
            "hasPendingWork" to (nextWakeAtMs != null),
            "nextWakeAtMs" to nextWakeAtMs,
        )
    }

    private fun getSnapshot(args: Map<String, Any?>): Map<String, Any?>? {
        val sessionId = requireString(args, KEY_SESSION_ID)
        require(CourtIds.isSafe(sessionId)) { "Unsafe $KEY_SESSION_ID: $sessionId" }
        return uploader.snapshot(sessionId)?.toMap()
    }

    private fun hasPendingWork(): Map<String, Any?> {
        val nextWakeAtMs = uploader.nextWakeAtMs()
        return mapOf(
            "hasPendingWork" to (nextWakeAtMs != null),
            "nextWakeAtMs" to nextWakeAtMs,
        )
    }

    private fun requireArguments(arguments: Map<String, Any?>?): Map<String, Any?> =
        requireNotNull(arguments) { "Arguments map is required." }

    private fun requireString(args: Map<String, Any?>, key: String): String {
        val raw = args[key]
        require(raw is String && raw.isNotBlank()) { "$key must be a non-blank String." }
        return raw
    }

    private fun requireLong(args: Map<String, Any?>, key: String): Long = parseIntegral(args[key], key)

    private fun optionalLong(args: Map<String, Any?>?, key: String): Long? {
        val raw = args?.get(key) ?: return null
        return parseIntegral(raw, key)
    }

    private fun parseIntegral(raw: Any?, key: String): Long = when (raw) {
        is Int -> raw.toLong()
        is Long -> raw
        else -> throw IllegalArgumentException("$key must be an integer.")
    }

    private fun LiveSessionUploadSnapshot.toMap(): Map<String, Any?> = mapOf(
        "sessionId" to sessionId,
        "slot" to slot,
        "grantedTiers" to grantedTiers,
        "stoppedAtMs" to stoppedAtMs,
        "lastSeqProxy" to lastSeqProxy,
        "lastSeqMaster" to lastSeqMaster,
        "manifestState" to manifestState,
        "totalSegments" to totalSegments,
        "activeSegments" to activeSegments,
        "verifiedSegments" to verifiedSegments,
        "heldSegments" to heldSegments,
        "failedSegments" to failedSegments,
        "conflictSegments" to conflictSegments,
        "pendingBytes" to pendingBytes,
        "isComplete" to isComplete,
        "items" to items.map { it.toMap() },
    )

    private fun UploadItem.toMap(): Map<String, Any?> = mapOf(
        "key" to key,
        "sessionId" to sessionId,
        "slot" to slot,
        "tier" to tier,
        "seq" to seq,
        "filePath" to filePath,
        "bytes" to bytes,
        "sha256" to sha256,
        "mediaStartServerMs" to mediaStartServerMs,
        "durationMs" to durationMs,
        "state" to state,
        "uploadId" to uploadId,
        "verifyRestarts" to verifyRestarts,
        "attempts" to attempts,
        "nextAttemptAtMs" to nextAttemptAtMs,
        "lastError" to lastError,
        "createdAtMs" to createdAtMs,
        "updatedAtMs" to updatedAtMs,
    )

    companion object {
        private const val COMMAND_START_SESSION = "startSession"
        private const val COMMAND_ENQUEUE_SEGMENT = "enqueueSegment"
        private const val COMMAND_MARK_RECORDING_STOPPED = "markRecordingStopped"
        private const val COMMAND_DRAIN_ONCE = "drainOnce"
        private const val COMMAND_GET_SNAPSHOT = "getSnapshot"
        private const val COMMAND_HAS_PENDING_WORK = "hasPendingWork"

        private val SUPPORTED_COMMANDS = setOf(
            COMMAND_START_SESSION,
            COMMAND_ENQUEUE_SEGMENT,
            COMMAND_MARK_RECORDING_STOPPED,
            COMMAND_DRAIN_ONCE,
            COMMAND_GET_SNAPSHOT,
            COMMAND_HAS_PENDING_WORK,
        )

        private const val KEY_SESSION_ID = "sessionId"
        private const val KEY_SLOT = "slot"
        private const val KEY_UPLOAD_GRANT = "uploadGrant"
        private const val KEY_INGEST_URL = "ingestUrl"
        private const val KEY_NOW_MS = "nowMs"
        private const val KEY_TIER = "tier"
        private const val KEY_SEQ = "seq"
        private const val KEY_FILE_PATH = "filePath"
        private const val KEY_SHA256 = "sha256"
        private const val KEY_MEDIA_START_SERVER_MS = "mediaStartServerMs"
        private const val KEY_DURATION_MS = "durationMs"
        private const val KEY_STOPPED_AT_MS = "stoppedAtMs"
        private const val KEY_MAX_STEPS = "maxSteps"

        private const val MIN_DRAIN_STEPS = 1
        private const val DEFAULT_MAX_DRAIN_STEPS = 16
        private const val MAX_DRAIN_STEPS = 50

        fun isSupportedCommand(command: String): Boolean = command in SUPPORTED_COMMANDS
    }
}
