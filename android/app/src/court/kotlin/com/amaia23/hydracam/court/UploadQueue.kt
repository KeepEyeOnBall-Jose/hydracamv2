package com.amaia23.hydracam.court

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

typealias UploadState = com.amaia23.hydracam.phonecore.UploadState
typealias UploadPolicyStore = com.amaia23.hydracam.phonecore.UploadPolicyStore
typealias InMemoryUploadPolicyStore = com.amaia23.hydracam.phonecore.InMemoryUploadPolicyStore
typealias UploadGrant = com.amaia23.hydracam.phonecore.UploadGrant
typealias UploadSessionGrant = com.amaia23.hydracam.phonecore.UploadSessionGrant
typealias UploadGrantCheck = com.amaia23.hydracam.phonecore.UploadGrantCheck
typealias UploadPriorityKey = com.amaia23.hydracam.phonecore.UploadPriorityKey
typealias UploadGrants = com.amaia23.hydracam.phonecore.UploadGrants
typealias UploadLifecycle = com.amaia23.hydracam.phonecore.UploadLifecycle

@Entity(tableName = "upload_items")
data class UploadItem(
    /** `<sessionId>/<tier>/<seq>`. */
    @PrimaryKey val key: String,
    val sessionId: String,
    val slot: String,
    val tier: String,
    val seq: Long,
    val filePath: String,
    val bytes: Long,
    val sha256: String,
    val mediaStartServerMs: Long,
    val durationMs: Long,
    val state: String = UploadState.PENDING.name,
    val uploadId: String? = null,
    /** JSON array `[{n, url}]` from init. */
    val partsJson: String? = null,
    /** JSON object `{"<n>": "<etag>"}` of parts already PUT. */
    val etagsJson: String? = null,
    /** Restarts after K3 failed verification; capped so bad bytes stop re-uploading. */
    @ColumnInfo(defaultValue = "0") val verifyRestarts: Int = 0,
    /** C1 1.11 queue jump: when `masters.upload` last asked for it; higher goes first within a tier. */
    @ColumnInfo(defaultValue = "0") val priority: Long = 0,
    val attempts: Int = 0,
    val nextAttemptAtMs: Long = 0,
    val lastError: String? = null,
    val createdAtMs: Long = 0,
    val updatedAtMs: Long = 0,
) {
    val uploadState: UploadState get() = UploadState.parse(state)

    internal fun priorityKey(): UploadPriorityKey = UploadPriorityKey(tier, priority, createdAtMs, seq)

    override fun toString(): String = "UploadItem($key, state=$state, attempts=$attempts, lastError=$lastError)"

    companion object {
        fun keyOf(sessionId: String, tier: String, seq: Long): String = UploadLifecycle.segmentKey(sessionId, tier, seq)

        fun from(segment: SegmentRecord, nowMs: Long): UploadItem = UploadItem(
            key = keyOf(segment.sessionId, segment.tier, segment.seq),
            sessionId = segment.sessionId,
            slot = segment.slot,
            tier = segment.tier,
            seq = segment.seq,
            filePath = segment.file.absolutePath,
            bytes = segment.bytes,
            sha256 = segment.sha256,
            mediaStartServerMs = segment.mediaStartServerMs,
            durationMs = segment.durationMs,
            createdAtMs = nowMs,
            updatedAtMs = nowMs,
        )
    }
}

/** Per-session upload context from `record.start` (grant, ingest URL) and from the stop. */
@Entity(tableName = "upload_sessions")
data class UploadSession(
    @PrimaryKey val sessionId: String,
    val slot: String,
    /** Upload grant JWT. App-private storage only; never logged. */
    val uploadGrant: String,
    val ingestUrl: String,
    val grantExpMs: Long,
    /** Comma-separated tiers the grant lists. */
    val tiersCsv: String,
    val stoppedAtMs: Long = 0,
    val lastSeqProxy: Long = -1,
    val lastSeqMaster: Long = -1,
    /** null until sent, then `complete` or `partial`. */
    val manifestState: String? = null,
    val manifestAttempts: Int = 0,
    val nextManifestAtMs: Long = 0,
    val createdAtMs: Long = 0,
    /** Grant from the latest accepted `masters.upload` (1.4); never logged. */
    val masterGrant: String? = null,
    val masterIngestUrl: String? = null,
    @ColumnInfo(defaultValue = "0") val masterGrantExpMs: Long = 0,
) {
    val tiers: List<String> get() = UploadGrants.parseTiersCsv(tiersCsv)

    internal fun toGrant(): UploadSessionGrant = UploadSessionGrant(
        uploadGrant = uploadGrant,
        ingestUrl = ingestUrl,
        grantExpMs = grantExpMs,
        grantedTiers = tiers,
        masterGrant = masterGrant,
        masterIngestUrl = masterIngestUrl,
        masterGrantExpMs = masterGrantExpMs,
    )

    override fun toString(): String =
        "UploadSession($sessionId, tiers=$tiersCsv, stoppedAtMs=$stoppedAtMs, manifest=$manifestState)"

    companion object {
        const val MANIFEST_COMPLETE = UploadLifecycle.MANIFEST_COMPLETE
        const val MANIFEST_PARTIAL = UploadLifecycle.MANIFEST_PARTIAL

        fun from(command: RecordStart, slot: String, nowMs: Long): UploadSession {
            val claims = UploadGrantClaims.decode(command.uploadGrant)
            return UploadSession(
                sessionId = command.sessionId,
                slot = slot,
                uploadGrant = command.uploadGrant,
                ingestUrl = command.ingestUrl,
                grantExpMs = UploadGrants.grantExpiryMs(claims),
                // A grant without readable tiers falls back to proxy only: never upload unlisted masters.
                tiersCsv = UploadGrants.grantedTiers(claims).joinToString(","),
                createdAtMs = nowMs,
            )
        }
    }
}

/** One `masters.upload` (1.4) awaiting or past its master-tier manifest. Keyed by the envelope id. */
@Entity(tableName = "master_requests")
data class MasterRequest(
    @PrimaryKey val id: String,
    val sessionId: String,
    val slot: String,
    /** Grant of this command (tiers ["master"]); never logged. */
    val uploadGrant: String,
    val ingestUrl: String,
    val grantExpMs: Long,
    /** JSON array of the master seqs held when the command arrived. */
    val seqsJson: String,
    val state: String = STATE_PENDING,
    val attempts: Int = 0,
    val nextAttemptAtMs: Long = 0,
    val lastError: String? = null,
    val createdAtMs: Long = 0,
) {
    override fun toString(): String = "MasterRequest($id, session=$sessionId, state=$state, lastError=$lastError)"

    companion object {
        const val STATE_PENDING = UploadLifecycle.MASTER_STATE_PENDING
        const val STATE_SENT = UploadLifecycle.MASTER_STATE_SENT
        const val STATE_REJECTED = UploadLifecycle.MASTER_STATE_REJECTED
        const val STATE_GONE = UploadLifecycle.MASTER_STATE_GONE
    }
}

@Entity(tableName = "seq_counters", primaryKeys = ["sessionId", "tier"])
data class SeqCounter(val sessionId: String, val tier: String, val lastSeq: Long)

/** Durable queue + seq counters. Android: Room ([RoomUploadQueueStore]); tests: [InMemoryUploadQueueStore]. */
interface UploadQueueStore : SegmentSeqStore {
    fun upsertSession(session: UploadSession)

    fun session(sessionId: String): UploadSession?

    fun sessions(): List<UploadSession>

    /** No-op when the key already exists (segment re-announced after a crash). */
    fun enqueue(item: UploadItem)

    fun update(item: UploadItem)

    fun item(key: String): UploadItem?

    fun items(sessionId: String): List<UploadItem>

    /** Next active item due at [nowMs]: proxy before master, then the latest queue jump, then oldest. */
    fun nextDue(nowMs: Long, includeMasters: Boolean = true): UploadItem?

    /** Earliest `nextAttemptAtMs` among active items and pending master requests, or null when none. */
    fun nextWakeAtMs(includeMasters: Boolean = true): Long?

    fun upsertMasterRequest(request: MasterRequest)

    fun masterRequest(id: String): MasterRequest?

    /** Oldest pending master request due at [nowMs]. */
    fun dueMasterRequest(nowMs: Long): MasterRequest?

    fun activeBytes(): Long

    fun activeCount(): Int
}

class InMemoryUploadQueueStore : UploadQueueStore {
    private val sessions = linkedMapOf<String, UploadSession>()
    private val items = linkedMapOf<String, UploadItem>()
    private val masterRequests = linkedMapOf<String, MasterRequest>()
    private val seqs = InMemorySegmentSeqStore()

    @Synchronized
    override fun upsertSession(session: UploadSession) {
        sessions[session.sessionId] = session
    }

    @Synchronized
    override fun session(sessionId: String): UploadSession? = sessions[sessionId]

    @Synchronized
    override fun sessions(): List<UploadSession> = sessions.values.toList()

    @Synchronized
    override fun enqueue(item: UploadItem) {
        items.putIfAbsent(item.key, item)
    }

    @Synchronized
    override fun update(item: UploadItem) {
        items[item.key] = item
    }

    @Synchronized
    override fun item(key: String): UploadItem? = items[key]

    @Synchronized
    override fun items(sessionId: String): List<UploadItem> =
        items.values.filter { it.sessionId == sessionId }.sortedWith(compareBy({ it.tier }, { it.seq }))

    @Synchronized
    override fun nextDue(nowMs: Long, includeMasters: Boolean): UploadItem? = items.values
        .filter { UploadLifecycle.isItemDue(it.tier, it.uploadState, it.nextAttemptAtMs, nowMs, includeMasters) }
        .sortedBy { it.priorityKey() }
        .firstOrNull()

    @Synchronized
    override fun nextWakeAtMs(includeMasters: Boolean): Long? {
        val itemWake = items.values
            .filter { UploadLifecycle.isItemWakeEligible(it.tier, it.uploadState, includeMasters) }
            .minOfOrNull { it.nextAttemptAtMs }
        val requestWake = masterRequests.values
            .filter { it.state == MasterRequest.STATE_PENDING }
            .minOfOrNull { it.nextAttemptAtMs }
        return listOfNotNull(itemWake, requestWake).minOrNull()
    }

    @Synchronized
    override fun upsertMasterRequest(request: MasterRequest) {
        masterRequests[request.id] = request
    }

    @Synchronized
    override fun masterRequest(id: String): MasterRequest? = masterRequests[id]

    @Synchronized
    override fun dueMasterRequest(nowMs: Long): MasterRequest? = masterRequests.values
        .filter { it.state == MasterRequest.STATE_PENDING && it.nextAttemptAtMs <= nowMs }
        .minByOrNull { it.createdAtMs }

    @Synchronized
    override fun activeBytes(): Long = items.values.filter { it.uploadState.active }.sumOf { it.bytes }

    @Synchronized
    override fun activeCount(): Int = items.values.count { it.uploadState.active }

    override fun lastSeq(sessionId: String, tier: String): Long = seqs.lastSeq(sessionId, tier)

    override fun commitSeq(sessionId: String, tier: String, seq: Long) = seqs.commitSeq(sessionId, tier, seq)
}
