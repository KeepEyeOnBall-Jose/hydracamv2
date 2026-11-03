package com.amaia23.hydracam.court

import android.content.Context
import androidx.room.AutoMigration
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Upsert

@Dao
interface CourtUploadDao {
    @Upsert
    fun upsertSession(session: UploadSession)

    @Query("SELECT * FROM upload_sessions WHERE sessionId = :sessionId")
    fun session(sessionId: String): UploadSession?

    @Query("SELECT * FROM upload_sessions ORDER BY createdAtMs")
    fun sessions(): List<UploadSession>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    fun insertItem(item: UploadItem)

    @Upsert
    fun upsertItem(item: UploadItem)

    @Query("SELECT * FROM upload_items WHERE `key` = :key")
    fun item(key: String): UploadItem?

    @Query("SELECT * FROM upload_items WHERE sessionId = :sessionId ORDER BY tier, seq")
    fun items(sessionId: String): List<UploadItem>

    @Query(
        "SELECT * FROM upload_items WHERE state IN ('PENDING', 'UPLOADING', 'VERIFYING') " +
            "AND nextAttemptAtMs <= :nowMs AND (:includeMasters OR tier = 'proxy') " +
            "ORDER BY CASE tier WHEN 'proxy' THEN 0 ELSE 1 END, createdAtMs, seq LIMIT 1",
    )
    fun nextDue(nowMs: Long, includeMasters: Boolean): UploadItem?

    @Query(
        "SELECT MIN(nextAttemptAtMs) FROM upload_items WHERE state IN ('PENDING', 'UPLOADING', 'VERIFYING') " +
            "AND (:includeMasters OR tier = 'proxy')",
    )
    fun nextItemWakeAtMs(includeMasters: Boolean): Long?

    @Query("SELECT MIN(nextAttemptAtMs) FROM master_requests WHERE state = 'pending'")
    fun nextRequestWakeAtMs(): Long?

    @Upsert
    fun upsertMasterRequest(request: MasterRequest)

    @Query("SELECT * FROM master_requests WHERE id = :id")
    fun masterRequest(id: String): MasterRequest?

    @Query(
        "SELECT * FROM master_requests WHERE state = 'pending' AND nextAttemptAtMs <= :nowMs " +
            "ORDER BY createdAtMs LIMIT 1",
    )
    fun dueMasterRequest(nowMs: Long): MasterRequest?

    @Query(
        "SELECT * FROM upload_items WHERE tier = 'master' AND state IN ('HELD', 'FAILED') " +
            "AND createdAtMs < :cutoffMs",
    )
    fun idleMastersBefore(cutoffMs: Long): List<UploadItem>

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
    entities = [UploadItem::class, UploadSession::class, SeqCounter::class, MasterRequest::class],
    version = 3,
    exportSchema = true,
    autoMigrations = [AutoMigration(from = 1, to = 2), AutoMigration(from = 2, to = 3)],
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

    override fun upsertSession(session: UploadSession) = dao.upsertSession(session)

    override fun session(sessionId: String): UploadSession? = dao.session(sessionId)

    override fun sessions(): List<UploadSession> = dao.sessions()

    override fun enqueue(item: UploadItem) = dao.insertItem(item)

    override fun update(item: UploadItem) = dao.upsertItem(item)

    override fun item(key: String): UploadItem? = dao.item(key)

    override fun items(sessionId: String): List<UploadItem> = dao.items(sessionId)

    override fun nextDue(nowMs: Long, includeMasters: Boolean): UploadItem? = dao.nextDue(nowMs, includeMasters)

    override fun nextWakeAtMs(includeMasters: Boolean): Long? =
        listOfNotNull(dao.nextItemWakeAtMs(includeMasters), dao.nextRequestWakeAtMs()).minOrNull()

    override fun upsertMasterRequest(request: MasterRequest) = dao.upsertMasterRequest(request)

    override fun masterRequest(id: String): MasterRequest? = dao.masterRequest(id)

    override fun dueMasterRequest(nowMs: Long): MasterRequest? = dao.dueMasterRequest(nowMs)

    override fun idleMastersBefore(cutoffMs: Long): List<UploadItem> = dao.idleMastersBefore(cutoffMs)

    override fun activeBytes(): Long = dao.activeBytes()

    override fun activeCount(): Int = dao.activeCount()

    override fun lastSeq(sessionId: String, tier: String): Long = dao.lastSeq(sessionId, tier) ?: -1

    override fun commitSeq(sessionId: String, tier: String, seq: Long) = dao.upsertSeq(SeqCounter(sessionId, tier, seq))
}
