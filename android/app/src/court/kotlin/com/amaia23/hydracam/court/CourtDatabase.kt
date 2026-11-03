package com.amaia23.hydracam.court

import android.content.Context
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
            "AND nextAttemptAtMs <= :nowMs " +
            "ORDER BY CASE tier WHEN 'proxy' THEN 0 ELSE 1 END, createdAtMs, seq LIMIT 1",
    )
    fun nextDue(nowMs: Long): UploadItem?

    @Query("SELECT MIN(nextAttemptAtMs) FROM upload_items WHERE state IN ('PENDING', 'UPLOADING', 'VERIFYING')")
    fun nextWakeAtMs(): Long?

    @Query("SELECT COALESCE(SUM(bytes), 0) FROM upload_items WHERE state IN ('PENDING', 'UPLOADING', 'VERIFYING')")
    fun activeBytes(): Long

    @Query("SELECT COUNT(*) FROM upload_items WHERE state IN ('PENDING', 'UPLOADING', 'VERIFYING')")
    fun activeCount(): Int

    @Query("SELECT lastSeq FROM seq_counters WHERE sessionId = :sessionId AND tier = :tier")
    fun lastSeq(sessionId: String, tier: String): Long?

    @Upsert
    fun upsertSeq(counter: SeqCounter)
}

@Database(entities = [UploadItem::class, UploadSession::class, SeqCounter::class], version = 1, exportSchema = true)
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

    override fun nextDue(nowMs: Long): UploadItem? = dao.nextDue(nowMs)

    override fun nextWakeAtMs(): Long? = dao.nextWakeAtMs()

    override fun activeBytes(): Long = dao.activeBytes()

    override fun activeCount(): Int = dao.activeCount()

    override fun lastSeq(sessionId: String, tier: String): Long = dao.lastSeq(sessionId, tier) ?: -1

    override fun commitSeq(sessionId: String, tier: String, seq: Long) =
        dao.upsertSeq(SeqCounter(sessionId, tier, seq))
}
