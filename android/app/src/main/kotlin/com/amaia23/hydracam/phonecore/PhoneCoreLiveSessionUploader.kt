package com.amaia23.hydracam.phonecore

import okhttp3.OkHttpClient
import java.io.File

/** Point-in-time upload progress for one live hand-held recording session. */
data class LiveSessionUploadSnapshot(
    val sessionId: String,
    val slot: String,
    val grantedTiers: List<String>,
    val stoppedAtMs: Long,
    val lastSeqProxy: Long,
    val lastSeqMaster: Long,
    val manifestState: String?,
    val totalSegments: Int,
    val activeSegments: Int,
    val verifiedSegments: Int,
    val heldSegments: Int,
    val failedSegments: Int,
    val conflictSegments: Int,
    val pendingBytes: Long,
    val items: List<UploadItem>,
) {
    val isComplete: Boolean
        get() = manifestState == UploadSession.MANIFEST_COMPLETE && activeSegments == 0
}

/** Point-in-time pending work summary across all persisted live upload sessions. */
data class LivePendingWorkSummary(
    val hasPendingWork: Boolean,
    val nextWakeAtMs: Long?,
    val pendingSessionCount: Int,
    val pendingSegmentCount: Int,
    val pendingBytes: Long,
    val pendingSessionIds: List<String>,
)

/**
 * H3 Slice 1: Room-free K3 upload coordinator built purely on `phonecore` so live hand-held mode
 * can upload finalized `.ts` segments and complete session manifests via [C2Uploader] without Room
 * or legacy `fixedcamera` helpers.
 */
class PhoneCoreLiveSessionUploader(
    http: OkHttpClient,
    private val store: UploadQueueStore = InMemoryUploadQueueStore(),
    private val clock: PhoneClock = PhoneClock.SYSTEM,
    private val logger: PhoneLogger = NoopPhoneLogger,
    throttle: UploadThrottle = UploadThrottle(maxKbps = 0),
    partSizeBytes: Long = C2Uploader.DEFAULT_PART_SIZE_BYTES,
    statusPollMs: Long = DEFAULT_STATUS_POLL_MS,
    baseBackoffMs: Long = UploadLifecycle.DEFAULT_BASE_BACKOFF_MS,
    maxBackoffMs: Long = UploadLifecycle.DEFAULT_MAX_BACKOFF_MS,
    onAlert: (String) -> Unit = {},
    private val mastersAllowed: () -> Boolean = { true },
) {
    private val sessionLock = Any()
    private val uploader = C2Uploader(
        http = http,
        store = store,
        clock = clock,
        logger = logger,
        partSizeBytes = partSizeBytes,
        statusPollMs = statusPollMs,
        baseBackoffMs = baseBackoffMs,
        maxBackoffMs = maxBackoffMs,
        throttle = throttle,
        onAlert = onAlert,
        mastersAllowed = mastersAllowed,
    )

    /** Decodes [uploadGrant] claims and registers (or refreshes) the [UploadSession] for [sessionId]. */
    fun startSession(
        sessionId: String,
        slot: String,
        uploadGrant: String,
        ingestUrl: String,
        nowMs: Long = clock.nowMs(),
    ): UploadSession {
        require(CourtIds.isSafe(sessionId)) { "Unsafe sessionId: $sessionId" }
        require(slot.isNotBlank()) { "slot must not be blank." }
        require(uploadGrant.isNotBlank()) { "uploadGrant must not be blank." }
        require(CourtUrls.isAllowed(ingestUrl)) { "ingestUrl must be https:// (or http:// to loopback)." }
        val claims = UploadGrantClaims.decode(uploadGrant)
        val grantExpMs = UploadGrants.grantExpiryMs(claims)
        val tiersCsv = UploadGrants.grantedTiers(claims).joinToString(",")
        return synchronized(sessionLock) {
            val existing = store.session(sessionId)
            val session = existing?.copy(
                slot = slot,
                uploadGrant = uploadGrant,
                ingestUrl = ingestUrl,
                grantExpMs = grantExpMs,
                tiersCsv = tiersCsv,
            ) ?: UploadSession(
                sessionId = sessionId,
                slot = slot,
                uploadGrant = uploadGrant,
                ingestUrl = ingestUrl,
                grantExpMs = grantExpMs,
                tiersCsv = tiersCsv,
                createdAtMs = nowMs,
            )
            store.upsertSession(session)
            logger.info(TAG, "Registered live upload session $sessionId slot=$slot tiers=$tiersCsv.")
            session
        }
    }

    /** Queues one finalized `.ts` segment for C2 upload. Idempotent per `(sessionId, tier, seq)`. */
    // Mirrors the finalized C2 segment fields handed off when live mode closes a .ts segment.
    @Suppress("LongParameterList")
    fun enqueueSegment(
        sessionId: String,
        slot: String,
        tier: String,
        seq: Long,
        file: File,
        sha256: String,
        mediaStartServerMs: Long,
        durationMs: Long,
    ): UploadItem {
        require(CourtIds.isSafe(sessionId)) { "Unsafe sessionId: $sessionId" }
        require(slot.isNotBlank()) { "slot must not be blank." }
        require(tier in C1.TIERS) { "Unknown tier: $tier" }
        require(seq >= 0) { "seq must be >= 0." }
        require(file.isFile) { "Segment file does not exist: ${file.path}" }
        require(sha256.isNotBlank()) { "sha256 must not be blank." }
        require(durationMs >= 0) { "durationMs must be >= 0." }
        val record = SegmentRecord(
            sessionId = sessionId,
            slot = slot,
            tier = tier,
            seq = seq,
            file = file,
            bytes = file.length(),
            sha256 = sha256,
            mediaStartServerMs = mediaStartServerMs,
            durationMs = durationMs,
            frames = 0,
            offsetMs = 0,
            rttMs = -1,
        )
        return enqueueSegment(record)
    }

    /** Queues a finalized [SegmentRecord] (e.g. directly from [TsSegmenter]). */
    fun enqueueSegment(segment: SegmentRecord): UploadItem {
        synchronized(sessionLock) {
            if (segment.seq > store.lastSeq(segment.sessionId, segment.tier)) {
                store.commitSeq(segment.sessionId, segment.tier, segment.seq)
            }
            uploader.enqueue(segment)
        }
        return requireNotNull(store.item(UploadItem.keyOf(segment.sessionId, segment.tier, segment.seq)))
    }

    /** Marks [sessionId] stopped so K3 manifest completion runs once granted proxy segments settle. */
    fun markRecordingStopped(sessionId: String, stoppedAtMs: Long = clock.nowMs()): UploadSession? {
        require(stoppedAtMs > 0) { "stoppedAtMs must be > 0." }
        return synchronized(sessionLock) {
            val session = store.session(sessionId) ?: return null
            val updated = session.copy(
                stoppedAtMs = stoppedAtMs,
                lastSeqProxy = maxOf(session.lastSeqProxy, store.lastSeq(sessionId, C1.TIER_PROXY)),
                lastSeqMaster = maxOf(session.lastSeqMaster, store.lastSeq(sessionId, C1.TIER_MASTER)),
            )
            store.upsertSession(updated)
            logger.info(
                TAG,
                "Marked live session $sessionId stopped (lastSeq proxy=${updated.lastSeqProxy}, " +
                    "master=${updated.lastSeqMaster}).",
            )
            updated
        }
    }

    /** Advances one due C2 upload or manifest step. Returns true when work was executed. */
    fun drainOnce(includeMasters: Boolean = mastersAllowed()): Boolean = uploader.runOnce(includeMasters)

    /** Cancels an in-flight master part if the master gate has closed. */
    fun preemptMasters() {
        uploader.preemptMasters()
    }

    /** Earliest timestamp at which an active segment, master request, or ready manifest can run. */
    fun nextWakeAtMs(includeMasters: Boolean = mastersAllowed()): Long? =
        pendingWorkSummary(includeMasters).nextWakeAtMs

    /** True while any segment upload, poll/retry, or stopped-session manifest remains pending. */
    fun hasPendingWork(includeMasters: Boolean = mastersAllowed()): Boolean = nextWakeAtMs(includeMasters) != null

    /** Returns an aggregate summary of pending sessions, segments, bytes, and earliest wake time. */
    fun pendingWorkSummary(includeMasters: Boolean = mastersAllowed()): LivePendingWorkSummary {
        val now = clock.nowMs()
        val itemOrRequestWake = store.nextWakeAtMs(includeMasters)
        val pendingSessionIds = mutableListOf<String>()
        var pendingSegmentCount = 0
        var pendingBytes = 0L
        var manifestWake: Long? = null

        for (session in store.sessions()) {
            val wakeItems = store.items(session.sessionId).filter {
                UploadLifecycle.isItemWakeEligible(it.tier, it.uploadState, includeMasters)
            }
            val manifestPending = isManifestPendingAndUnblocked(session, now)
            if (manifestPending) {
                manifestWake = minWake(manifestWake, session.nextManifestAtMs)
            }
            if (wakeItems.isNotEmpty() || manifestPending) {
                pendingSessionIds += session.sessionId
                pendingSegmentCount += wakeItems.size
                pendingBytes += wakeItems.sumOf { it.bytes }
            }
        }

        val nextWake = listOfNotNull(itemOrRequestWake, manifestWake).minOrNull()
        return LivePendingWorkSummary(
            hasPendingWork = nextWake != null,
            nextWakeAtMs = nextWake,
            pendingSessionCount = pendingSessionIds.size,
            pendingSegmentCount = pendingSegmentCount,
            pendingBytes = pendingBytes,
            pendingSessionIds = pendingSessionIds,
        )
    }

    /** Returns a point-in-time upload summary for [sessionId], or null when unknown. */
    fun snapshot(sessionId: String): LiveSessionUploadSnapshot? {
        val session = store.session(sessionId) ?: return null
        val items = store.items(sessionId)
        val active = items.filter { it.uploadState.active }
        return LiveSessionUploadSnapshot(
            sessionId = session.sessionId,
            slot = session.slot,
            grantedTiers = session.tiers,
            stoppedAtMs = session.stoppedAtMs,
            lastSeqProxy = maxOf(session.lastSeqProxy, store.lastSeq(sessionId, C1.TIER_PROXY)),
            lastSeqMaster = maxOf(session.lastSeqMaster, store.lastSeq(sessionId, C1.TIER_MASTER)),
            manifestState = session.manifestState,
            totalSegments = items.size,
            activeSegments = active.size,
            verifiedSegments = items.count { it.uploadState == UploadState.VERIFIED },
            heldSegments = items.count { it.uploadState == UploadState.HELD },
            failedSegments = items.count { it.uploadState == UploadState.FAILED },
            conflictSegments = items.count { it.uploadState == UploadState.CONFLICT },
            pendingBytes = active.sumOf { it.bytes },
            items = items,
        )
    }

    private fun minWake(current: Long?, candidate: Long): Long =
        if (current == null) candidate else minOf(current, candidate)

    private fun isManifestPendingAndUnblocked(session: UploadSession, nowMs: Long): Boolean {
        val manifestPending = session.stoppedAtMs > 0 && session.manifestState != UploadSession.MANIFEST_COMPLETE
        val canRetry = session.nextManifestAtMs < Long.MAX_VALUE && nowMs < session.grantExpMs
        if (!manifestPending || !canRetry) {
            return false
        }
        return store.items(session.sessionId).none {
            UploadLifecycle.isGrantedProxyBlockingManifest(it.uploadState, it.tier, session.tiers)
        }
    }

    companion object {
        private const val DEFAULT_STATUS_POLL_MS = 2_000L
        private const val TAG = "LiveSessionUploader"
    }
}
