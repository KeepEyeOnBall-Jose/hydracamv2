package com.amaia23.hydracam.phonecore

import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Durable store of device events K2 has not acked yet. C1: un-acked events are re-sent with the
 * same id, so they must survive reconnects and process death.
 */
class EventOutbox(
    private val directory: File?,
    private val maxEntries: Int = 5_000,
    private val logger: PhoneLogger = NoopPhoneLogger,
) {
    private data class Entry(val envelope: C1Envelope, val order: Long, var lastSentAtMs: Long)

    private val entries = LinkedHashMap<String, Entry>()
    private var nextOrder = 0L

    init {
        load()
    }

    @Synchronized
    fun add(envelope: C1Envelope) {
        val entry = Entry(envelope, nextOrder++, lastSentAtMs = 0)
        entries[envelope.id] = entry
        persist(entry)
        while (entries.size > maxEntries) {
            val oldest = entries.values.first()
            logger.warn(TAG, "Outbox full; dropping ${oldest.envelope.type} id=${oldest.envelope.id}.")
            remove(oldest.envelope.id)
        }
    }

    /** Returns true when [id] was pending. */
    @Synchronized
    fun ack(id: String): Boolean = remove(id)

    @Synchronized
    fun size(): Int = entries.size

    @Synchronized
    fun pendingIds(): List<String> = entries.keys.toList()

    /** Entries never sent, or sent longer than [resendAfterMs] ago. Marks them sent at [nowMs]. */
    @Synchronized
    fun takeDue(nowMs: Long, resendAfterMs: Long): List<C1Envelope> {
        val due = entries.values.filter {
            it.lastSentAtMs == 0L || nowMs - it.lastSentAtMs >= resendAfterMs
        }
        due.forEach { it.lastSentAtMs = nowMs }
        return due.map { it.envelope }
    }

    /** New connection: everything pending is due again. */
    @Synchronized
    fun markAllUnsent() {
        entries.values.forEach { it.lastSentAtMs = 0 }
    }

    private fun remove(id: String): Boolean {
        val entry = entries.remove(id) ?: return false
        directory?.let { File(it, fileName(entry)).delete() }
        return true
    }

    private fun persist(entry: Entry) {
        val dir = directory ?: return
        val json = JSONObject()
            .put("order", entry.order)
            .put("envelope", JSONObject(entry.envelope.encode()))
        try {
            dir.mkdirs()
            val temp = File(dir, fileName(entry) + ".tmp")
            // Synced before the rename, so a power cut cannot leave an empty file that load() drops.
            FileOutputStream(temp).use { stream ->
                stream.write(json.toString().toByteArray())
                stream.fd.sync()
            }
            if (!temp.renameTo(File(dir, fileName(entry)))) {
                throw IOException("rename failed")
            }
        } catch (error: IOException) {
            logger.warn(TAG, "Could not persist outbox entry ${entry.envelope.id}.", error)
        }
    }

    private fun load() {
        val dir = directory ?: return
        val files = dir.listFiles { file -> file.name.endsWith(".json") } ?: return
        val loaded = files.mapNotNull { file ->
            val failure: Exception = try {
                val json = JSONObject(file.readText())
                val envelope = C1Envelope.decode(json.getJSONObject("envelope").toString())
                return@mapNotNull Entry(envelope, json.getLong("order"), lastSentAtMs = 0)
            } catch (error: IOException) {
                error
            } catch (error: JSONException) {
                error
            } catch (error: C1ProtocolException) {
                error
            }
            logger.warn(TAG, "Dropping unreadable outbox file ${file.name}.", failure)
            file.delete()
            null
        }
        loaded.sortedBy { it.order }.forEach { entries[it.envelope.id] = it }
        nextOrder = (loaded.maxOfOrNull { it.order } ?: -1) + 1
    }

    private fun fileName(entry: Entry): String = "%012d-%s.json".format(entry.order, entry.envelope.id)

    private companion object {
        const val TAG = "CourtOutbox"
    }
}
