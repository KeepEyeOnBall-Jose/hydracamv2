package com.amaia23.hydracam.court

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

    /** The grant does not list this tier (masters): kept on the phone. */
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

    /** Next active item due at [nowMs]: proxy before master, then oldest first. */
    fun nextDue(nowMs: Long): UploadItem?

    /** Earliest `nextAttemptAtMs` among active items, or null when none. */
    fun nextWakeAtMs(): Long?

    fun activeBytes(): Long

    fun activeCount(): Int
}

class InMemoryUploadQueueStore : UploadQueueStore {
    private val sessions = linkedMapOf<String, UploadSession>()
    private val items = linkedMapOf<String, UploadItem>()
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
    override fun nextDue(nowMs: Long): UploadItem? =
        items.values
            .filter { it.uploadState.active && it.nextAttemptAtMs <= nowMs }
            .sortedWith(compareBy({ if (it.tier == C1.TIER_PROXY) 0 else 1 }, { it.createdAtMs }, { it.seq }))
            .firstOrNull()

    @Synchronized
    override fun nextWakeAtMs(): Long? =
        items.values.filter { it.uploadState.active }.minOfOrNull { it.nextAttemptAtMs }

    @Synchronized
    override fun activeBytes(): Long = items.values.filter { it.uploadState.active }.sumOf { it.bytes }

    @Synchronized
    override fun activeCount(): Int = items.values.count { it.uploadState.active }

    override fun lastSeq(sessionId: String, tier: String): Long = seqs.lastSeq(sessionId, tier)

    override fun commitSeq(sessionId: String, tier: String, seq: Long) = seqs.commitSeq(sessionId, tier, seq)
}
