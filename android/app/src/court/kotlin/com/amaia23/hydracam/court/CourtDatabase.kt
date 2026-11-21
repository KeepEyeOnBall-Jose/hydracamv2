package com.amaia23.hydracam.court

import android.content.Context
import androidx.room.AutoMigration
import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Upsert

@Entity(tableName = "upload_items")
data class UploadItemEntity(
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
    val partsJson: String? = null,
    val etagsJson: String? = null,
    @ColumnInfo(defaultValue = "0") val verifyRestarts: Int = 0,
    @ColumnInfo(defaultValue = "0") val priority: Long = 0,
    val attempts: Int = 0,
    val nextAttemptAtMs: Long = 0,
    val lastError: String? = null,
    val createdAtMs: Long = 0,
    val updatedAtMs: Long = 0,
) {
    fun toDomain(): UploadItem = UploadItem(
        key = key,
        sessionId = sessionId,
        slot = slot,
        tier = tier,
        seq = seq,
        filePath = filePath,
        bytes = bytes,
        sha256 = sha256,
        mediaStartServerMs = mediaStartServerMs,
        durationMs = durationMs,
        state = state,
        uploadId = uploadId,
        partsJson = partsJson,
        etagsJson = etagsJson,
        verifyRestarts = verifyRestarts,
        priority = priority,
        attempts = attempts,
        nextAttemptAtMs = nextAttemptAtMs,
        lastError = lastError,
        createdAtMs = createdAtMs,
        updatedAtMs = updatedAtMs,
    )

    companion object {
        fun fromDomain(item: UploadItem): UploadItemEntity = UploadItemEntity(
            key = item.key,
            sessionId = item.sessionId,
            slot = item.slot,
            tier = item.tier,
            seq = item.seq,
            filePath = item.filePath,
            bytes = item.bytes,
            sha256 = item.sha256,
            mediaStartServerMs = item.mediaStartServerMs,
            durationMs = item.durationMs,
            state = item.state,
            uploadId = item.uploadId,
            partsJson = item.partsJson,
            etagsJson = item.etagsJson,
            verifyRestarts = item.verifyRestarts,
            priority = item.priority,
            attempts = item.attempts,
            nextAttemptAtMs = item.nextAttemptAtMs,
            lastError = item.lastError,
            createdAtMs = item.createdAtMs,
            updatedAtMs = item.updatedAtMs,
        )
    }
}

@Entity(tableName = "upload_sessions")
data class UploadSessionEntity(
    @PrimaryKey val sessionId: String,
    val slot: String,
    val uploadGrant: String,
    val ingestUrl: String,
    val grantExpMs: Long,
    val tiersCsv: String,
    val stoppedAtMs: Long = 0,
    val lastSeqProxy: Long = -1,
    val lastSeqMaster: Long = -1,
    val manifestState: String? = null,
    val manifestAttempts: Int = 0,
    val nextManifestAtMs: Long = 0,
    val createdAtMs: Long = 0,
    val masterGrant: String? = null,
    val masterIngestUrl: String? = null,
    @ColumnInfo(defaultValue = "0") val masterGrantExpMs: Long = 0,
) {
    fun toDomain(): UploadSession = UploadSession(
        sessionId = sessionId,
        slot = slot,
        uploadGrant = uploadGrant,
        ingestUrl = ingestUrl,
        grantExpMs = grantExpMs,
        tiersCsv = tiersCsv,
        stoppedAtMs = stoppedAtMs,
        lastSeqProxy = lastSeqProxy,
        lastSeqMaster = lastSeqMaster,
        manifestState = manifestState,
        manifestAttempts = manifestAttempts,
        nextManifestAtMs = nextManifestAtMs,
        createdAtMs = createdAtMs,
        masterGrant = masterGrant,
        masterIngestUrl = masterIngestUrl,
        masterGrantExpMs = masterGrantExpMs,
    )

    companion object {
        fun fromDomain(session: UploadSession): UploadSessionEntity = UploadSessionEntity(
            sessionId = session.sessionId,
            slot = session.slot,
            uploadGrant = session.uploadGrant,
            ingestUrl = session.ingestUrl,
            grantExpMs = session.grantExpMs,
            tiersCsv = session.tiersCsv,
            stoppedAtMs = session.stoppedAtMs,
            lastSeqProxy = session.lastSeqProxy,
            lastSeqMaster = session.lastSeqMaster,
            manifestState = session.manifestState,
            manifestAttempts = session.manifestAttempts,
            nextManifestAtMs = session.nextManifestAtMs,
            createdAtMs = session.createdAtMs,
            masterGrant = session.masterGrant,
            masterIngestUrl = session.masterIngestUrl,
            masterGrantExpMs = session.masterGrantExpMs,
        )
    }
}

@Entity(tableName = "master_requests")
data class MasterRequestEntity(
    @PrimaryKey val id: String,
    val sessionId: String,
    val slot: String,
    val uploadGrant: String,
    val ingestUrl: String,
    val grantExpMs: Long,
    val seqsJson: String,
    val state: String = MasterRequest.STATE_PENDING,
    val attempts: Int = 0,
    val nextAttemptAtMs: Long = 0,
    val lastError: String? = null,
    val createdAtMs: Long = 0,
) {
    fun toDomain(): MasterRequest = MasterRequest(
        id = id,
        sessionId = sessionId,
        slot = slot,
        uploadGrant = uploadGrant,
        ingestUrl = ingestUrl,
        grantExpMs = grantExpMs,
        seqsJson = seqsJson,
        state = state,
        attempts = attempts,
        nextAttemptAtMs = nextAttemptAtMs,
        lastError = lastError,
        createdAtMs = createdAtMs,
    )

    companion object {
        fun fromDomain(request: MasterRequest): MasterRequestEntity = MasterRequestEntity(
            id = request.id,
            sessionId = request.sessionId,
            slot = request.slot,
            uploadGrant = request.uploadGrant,
            ingestUrl = request.ingestUrl,
            grantExpMs = request.grantExpMs,
            seqsJson = request.seqsJson,
            state = request.state,
            attempts = request.attempts,
            nextAttemptAtMs = request.nextAttemptAtMs,
            lastError = request.lastError,
            createdAtMs = request.createdAtMs,
        )
    }
}

@Entity(tableName = "seq_counters", primaryKeys = ["sessionId", "tier"])
data class SeqCounter(val sessionId: String, val tier: String, val lastSeq: Long)

@Dao
interface CourtUploadDao {
    @Upsert
    fun upsertSession(session: UploadSessionEntity)

    @Query("SELECT * FROM upload_sessions WHERE sessionId = :sessionId")
    fun session(sessionId: String): UploadSessionEntity?

    @Query("SELECT * FROM upload_sessions ORDER BY createdAtMs")
    fun sessions(): List<UploadSessionEntity>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    fun insertItem(item: UploadItemEntity)

    @Upsert
    fun upsertItem(item: UploadItemEntity)

    @Query("SELECT * FROM upload_items WHERE `key` = :key")
    fun item(key: String): UploadItemEntity?

    @Query("SELECT * FROM upload_items WHERE sessionId = :sessionId ORDER BY tier, seq")
    fun items(sessionId: String): List<UploadItemEntity>

    @Query(
        "SELECT * FROM upload_items WHERE state IN ('PENDING', 'UPLOADING', 'VERIFYING') " +
            "AND nextAttemptAtMs <= :nowMs AND (:includeMasters OR tier = 'proxy') " +
            "ORDER BY CASE tier WHEN 'proxy' THEN 0 ELSE 1 END, priority DESC, createdAtMs, seq LIMIT 1",
    )
    fun nextDue(nowMs: Long, includeMasters: Boolean): UploadItemEntity?

    @Query(
        "SELECT MIN(nextAttemptAtMs) FROM upload_items WHERE state IN ('PENDING', 'UPLOADING', 'VERIFYING') " +
            "AND (:includeMasters OR tier = 'proxy')",
    )
    fun nextItemWakeAtMs(includeMasters: Boolean): Long?

    @Query("SELECT MIN(nextAttemptAtMs) FROM master_requests WHERE state = 'pending'")
    fun nextRequestWakeAtMs(): Long?

    @Upsert
    fun upsertMasterRequest(request: MasterRequestEntity)

    @Query("SELECT * FROM master_requests WHERE id = :id")
    fun masterRequest(id: String): MasterRequestEntity?

    @Query(
        "SELECT * FROM master_requests WHERE state = 'pending' AND nextAttemptAtMs <= :nowMs " +
            "ORDER BY createdAtMs LIMIT 1",
    )
    fun dueMasterRequest(nowMs: Long): MasterRequestEntity?

    @Query("SELECT COALESCE(SUM(bytes), 0) FROM upload_items WHERE state IN ('PENDING', 'UPLOADING', 'VERIFYING')")
    fun activeBytes(): Long

    @Query("SELECT COUNT(*) FROM upload_items WHERE state IN ('PENDING', 'UPLOADING', 'VERIFYING')")
    fun activeCount(): Int

    @Query("SELECT lastSeq FROM seq_counters WHERE sessionId = :sessionId AND tier = :tier")
    fun lastSeq(sessionId: String, tier: String): Long?

    @Upsert
    fun upsertSeq(counter: SeqCounter)
}

@Database(
    entities = [
        UploadItemEntity::class,
        UploadSessionEntity::class,
        SeqCounter::class,
        MasterRequestEntity::class,
    ],
    version = 4,
    exportSchema = true,
    autoMigrations = [
        AutoMigration(from = 1, to = 2),
        AutoMigration(from = 2, to = 3),
        AutoMigration(from = 3, to = 4),
    ],
)
abstract class CourtDatabase : RoomDatabase() {
    abstract fun uploads(): CourtUploadDao

    companion object {
        fun open(context: Context): CourtDatabase =
            Room.databaseBuilder(context.applicationContext, CourtDatabase::class.java, "court.db").build()
    }
}

/** Room-backed [UploadQueueStore]. Calls block; use from background threads only. */
class RoomUploadQueueStore(database: CourtDatabase) : UploadQueueStore {
    private val dao = database.uploads()

    override fun upsertSession(session: UploadSession) = dao.upsertSession(UploadSessionEntity.fromDomain(session))

    override fun session(sessionId: String): UploadSession? = dao.session(sessionId)?.toDomain()

    override fun sessions(): List<UploadSession> = dao.sessions().map { it.toDomain() }

    override fun enqueue(item: UploadItem) = dao.insertItem(UploadItemEntity.fromDomain(item))

    override fun update(item: UploadItem) = dao.upsertItem(UploadItemEntity.fromDomain(item))

    override fun item(key: String): UploadItem? = dao.item(key)?.toDomain()

    override fun items(sessionId: String): List<UploadItem> = dao.items(sessionId).map { it.toDomain() }

    override fun nextDue(nowMs: Long, includeMasters: Boolean): UploadItem? =
        dao.nextDue(nowMs, includeMasters)?.toDomain()

    override fun nextWakeAtMs(includeMasters: Boolean): Long? =
        listOfNotNull(dao.nextItemWakeAtMs(includeMasters), dao.nextRequestWakeAtMs()).minOrNull()

    override fun upsertMasterRequest(request: MasterRequest) =
        dao.upsertMasterRequest(MasterRequestEntity.fromDomain(request))

    override fun masterRequest(id: String): MasterRequest? = dao.masterRequest(id)?.toDomain()

    override fun dueMasterRequest(nowMs: Long): MasterRequest? = dao.dueMasterRequest(nowMs)?.toDomain()

    override fun activeBytes(): Long = dao.activeBytes()

    override fun activeCount(): Int = dao.activeCount()

    override fun lastSeq(sessionId: String, tier: String): Long = dao.lastSeq(sessionId, tier) ?: -1

    override fun commitSeq(sessionId: String, tier: String, seq: Long) = dao.upsertSeq(SeqCounter(sessionId, tier, seq))
}
