package com.amaia23.hydracam.court

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/** Upload lifecycle of one segment (H7). Files are deleted only on [VERIFIED]. */
enum class UploadState {
    PENDING,
    UPLOADING,
    VERIFYING,
    VERIFIED,

    /** K3 holds different bytes for the same key: the file is kept, lastError set. */
    CONFLICT,

    /** Terminal: grant expired or missing, or the file is gone. */
    FAILED,

    /** No grant lists this tier yet (masters before `masters.upload`): kept on the phone. */
    HELD,
    ;

    val active: Boolean get() = this == PENDING || this == UPLOADING || this == VERIFYING

    companion object {
        fun parse(value: String): UploadState = entries.firstOrNull { it.name == value } ?: PENDING
    }
}

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
    val attempts: Int = 0,
    val nextAttemptAtMs: Long = 0,
    val lastError: String? = null,
    val createdAtMs: Long = 0,
    val updatedAtMs: Long = 0,
) {
    val uploadState: UploadState get() = UploadState.parse(state)

    override fun toString(): String = "UploadItem($key, state=$state, attempts=$attempts, lastError=$lastError)"

    companion object {
        fun keyOf(sessionId: String, tier: String, seq: Long): String = "$sessionId/$tier/$seq"

        fun from(segment: SegmentRecord, nowMs: Long): UploadItem =
            UploadItem(
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
    val tiers: List<String> get() = tiersCsv.split(',').filter { it.isNotBlank() }

    override fun toString(): String =
        "UploadSession($sessionId, tiers=$tiersCsv, stoppedAtMs=$stoppedAtMs, manifest=$manifestState)"

    companion object {
        const val MANIFEST_COMPLETE = "complete"
        const val MANIFEST_PARTIAL = "partial"

        fun from(command: RecordStart, slot: String, nowMs: Long): UploadSession {
            val claims = UploadGrantClaims.decode(command.uploadGrant)
            return UploadSession(
                sessionId = command.sessionId,
                slot = slot,
                uploadGrant = command.uploadGrant,
                ingestUrl = command.ingestUrl,
                grantExpMs = claims?.expMs?.takeIf { it > 0 } ?: Long.MAX_VALUE,
                // A grant without readable tiers falls back to proxy only: never upload unlisted masters.
                tiersCsv = (claims?.tiers?.takeIf { it.isNotEmpty() } ?: listOf(C1.TIER_PROXY)).joinToString(","),
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
        const val STATE_PENDING = "pending"
        const val STATE_SENT = "sent"
        const val STATE_REJECTED = "rejected"
        const val STATE_GONE = "gone"
    }
}

@Entity(tableName = "seq_counters", primaryKeys = ["sessionId", "tier"])
data class SeqCounter(val sessionId: String, val tier: String, val lastSeq: Long)

/** Last applied `upload.policy` (R10). Android: SharedPreferences; tests: [InMemoryUploadPolicyStore]. */
interface UploadPolicyStore {
    fun load(): UploadPolicy

    fun save(policy: UploadPolicy)
}

class InMemoryUploadPolicyStore(private var policy: UploadPolicy = UploadPolicy.DEFAULT) : UploadPolicyStore {
    @Synchronized
    override fun load(): UploadPolicy = policy

    @Synchronized
    override fun save(policy: UploadPolicy) {
        this.policy = policy
    }
}

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

    /** Next active item due at [nowMs]: proxy before master, then oldest first. */
    fun nextDue(nowMs: Long, includeMasters: Boolean = true): UploadItem?

    /** Earliest `nextAttemptAtMs` among active items and pending master requests, or null when none. */
    fun nextWakeAtMs(includeMasters: Boolean = true): Long?

    fun upsertMasterRequest(request: MasterRequest)

    fun masterRequest(id: String): MasterRequest?

    /** Oldest pending master request due at [nowMs]. */
    fun dueMasterRequest(nowMs: Long): MasterRequest?

    /** HELD or FAILED masters created before [cutoffMs] (keepDays pruning). */
    fun idleMastersBefore(cutoffMs: Long): List<UploadItem>

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
    override fun nextDue(nowMs: Long, includeMasters: Boolean): UploadItem? =
        items.values
            .filter { it.uploadState.active && it.nextAttemptAtMs <= nowMs && (includeMasters || it.tier == C1.TIER_PROXY) }
            .sortedWith(compareBy({ if (it.tier == C1.TIER_PROXY) 0 else 1 }, { it.createdAtMs }, { it.seq }))
            .firstOrNull()

    @Synchronized
    override fun nextWakeAtMs(includeMasters: Boolean): Long? {
        val itemWake = items.values
            .filter { it.uploadState.active && (includeMasters || it.tier == C1.TIER_PROXY) }
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
    override fun dueMasterRequest(nowMs: Long): MasterRequest? =
        masterRequests.values
            .filter { it.state == MasterRequest.STATE_PENDING && it.nextAttemptAtMs <= nowMs }
            .minByOrNull { it.createdAtMs }

    @Synchronized
    override fun idleMastersBefore(cutoffMs: Long): List<UploadItem> =
        items.values.filter {
            it.tier == C1.TIER_MASTER && it.createdAtMs < cutoffMs &&
                (it.uploadState == UploadState.HELD || it.uploadState == UploadState.FAILED)
        }

    @Synchronized
    override fun activeBytes(): Long = items.values.filter { it.uploadState.active }.sumOf { it.bytes }

    @Synchronized
    override fun activeCount(): Int = items.values.count { it.uploadState.active }

    override fun lastSeq(sessionId: String, tier: String): Long = seqs.lastSeq(sessionId, tier)

    override fun commitSeq(sessionId: String, tier: String, seq: Long) = seqs.commitSeq(sessionId, tier, seq)
}
