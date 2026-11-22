package com.amaia23.hydracam.phonecore

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * Pure-JVM, crash-safe file-backed [UploadQueueStore] for hand-held live upload mode.
 *
 * Persists sessions, queued items, master requests, and segment seq counters as a single JSON
 * document written to a sibling `.tmp` file, fsynced, and atomically moved into place.
 */
class FileUploadQueueStore(private val file: File, private val logger: PhoneLogger = NoopPhoneLogger) :
    UploadQueueStore {
    private data class SeqKey(val sessionId: String, val tier: String)

    private val parentDir: File = checkNotNull(file.absoluteFile.parentFile) {
        "Queue file must have a parent directory: $file"
    }
    private val sessions = linkedMapOf<String, UploadSession>()
    private val items = linkedMapOf<String, UploadItem>()
    private val masterRequests = linkedMapOf<String, MasterRequest>()
    private val seqs = linkedMapOf<SeqKey, Long>()

    init {
        loadLocked()
    }

    @Synchronized
    override fun upsertSession(session: UploadSession) {
        sessions[session.sessionId] = session
        flushLocked()
    }

    @Synchronized
    override fun session(sessionId: String): UploadSession? = sessions[sessionId]

    @Synchronized
    override fun sessions(): List<UploadSession> = sessions.values.toList()

    @Synchronized
    override fun enqueue(item: UploadItem) {
        if (items.putIfAbsent(item.key, item) == null) {
            flushLocked()
        }
    }

    @Synchronized
    override fun update(item: UploadItem) {
        items[item.key] = item
        flushLocked()
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
        flushLocked()
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

    @Synchronized
    override fun lastSeq(sessionId: String, tier: String): Long = seqs[SeqKey(sessionId, tier)] ?: -1L

    @Synchronized
    override fun commitSeq(sessionId: String, tier: String, seq: Long) {
        seqs[SeqKey(sessionId, tier)] = seq
        flushLocked()
    }

    /**
     * Removes finished items, completed/rejected master requests, and completed sessions older than
     * [cutoffMs], persisting the compacted queue if anything was removed.
     */
    @Synchronized
    fun purgeFinishedBefore(cutoffMs: Long): Int {
        val expiredItemKeys = items.values
            .filter { isItemFinishedBefore(it, cutoffMs) }
            .map { it.key }
        expiredItemKeys.forEach { items.remove(it) }

        val expiredRequestIds = masterRequests.values
            .filter { it.state != MasterRequest.STATE_PENDING && it.createdAtMs < cutoffMs }
            .map { it.id }
        expiredRequestIds.forEach { masterRequests.remove(it) }

        val expiredSessionIds = sessions.values
            .filter { isSessionFinishedBefore(it, cutoffMs) }
            .map { it.sessionId }
        expiredSessionIds.forEach { sessionId ->
            sessions.remove(sessionId)
            seqs.keys.removeAll { it.sessionId == sessionId }
        }

        val removed = expiredItemKeys.size + expiredRequestIds.size + expiredSessionIds.size
        if (removed > 0) {
            flushLocked()
        }
        return removed
    }

    private fun isItemFinishedBefore(item: UploadItem, cutoffMs: Long): Boolean {
        val state = item.uploadState
        val finished = !state.active && state != UploadState.HELD
        val finishedAtMs = if (item.updatedAtMs > 0L) item.updatedAtMs else item.createdAtMs
        return finished && finishedAtMs < cutoffMs
    }

    private fun isSessionFinishedBefore(session: UploadSession, cutoffMs: Long): Boolean {
        val manifestFinished = session.manifestState == UploadSession.MANIFEST_COMPLETE ||
            (session.manifestState == UploadSession.MANIFEST_PARTIAL && session.nextManifestAtMs == Long.MAX_VALUE)
        val stoppedBeforeCutoff = session.stoppedAtMs > 0L && session.stoppedAtMs < cutoffMs
        return stoppedBeforeCutoff &&
            manifestFinished &&
            items.values.none { it.sessionId == session.sessionId } &&
            masterRequests.values.none { it.sessionId == session.sessionId }
    }

    private fun loadLocked() {
        val staleTemp = tempFile()
        if (staleTemp.isFile) {
            staleTemp.delete()
        }
        if (!file.isFile) {
            return
        }
        try {
            decodeAndPopulate(file.readText(StandardCharsets.UTF_8))
        } catch (error: IOException) {
            recoverFromCorruptFile(error)
        } catch (error: JSONException) {
            recoverFromCorruptFile(error)
        }
    }

    private fun decodeAndPopulate(text: String) {
        if (text.isBlank()) {
            throw JSONException("Queue file is blank")
        }
        val root = JSONObject(text)
        val version = root.strictInt(KEY_VERSION)
        if (version != SCHEMA_VERSION) {
            throw JSONException("Unsupported queue schema version: $version")
        }
        val decodedSessions = root.optArrayOrEmpty(KEY_SESSIONS).mapObjects(::decodeSession)
        val decodedItems = root.optArrayOrEmpty(KEY_ITEMS).mapObjects(::decodeItem)
        val decodedRequests = root.optArrayOrEmpty(KEY_MASTER_REQUESTS).mapObjects(::decodeMasterRequest)
        val decodedSeqs = root.optArrayOrEmpty(KEY_SEQS).mapObjects(::decodeSeq)

        sessions.clear()
        decodedSessions.forEach { sessions[it.sessionId] = it }
        items.clear()
        decodedItems.forEach { items[it.key] = it }
        masterRequests.clear()
        decodedRequests.forEach { masterRequests[it.id] = it }
        seqs.clear()
        decodedSeqs.forEach { (key, seq) -> seqs[key] = seq }
    }

    private fun recoverFromCorruptFile(error: Exception) {
        sessions.clear()
        items.clear()
        masterRequests.clear()
        seqs.clear()
        val backup = corruptBackupFile()
        logger.warn(
            TAG,
            "Corrupt upload queue at ${file.name}; preserving backup at ${backup.name} and starting empty.",
            error,
        )
        try {
            replaceTarget(file, backup)
        } catch (moveError: IOException) {
            logger.warn(TAG, "Failed to move corrupt queue file ${file.name} to ${backup.name}.", moveError)
        }
    }

    private fun corruptBackupFile(): File {
        val base = File(parentDir, "${file.name}.corrupt")
        if (!base.exists()) {
            return base
        }
        var index = 1
        while (File(parentDir, "${file.name}.corrupt.$index").exists()) {
            index += 1
        }
        return File(parentDir, "${file.name}.corrupt.$index")
    }

    private fun flushLocked() {
        val payload = encode().toString().toByteArray(StandardCharsets.UTF_8)
        val temp = tempFile()
        try {
            if (!parentDir.isDirectory && !parentDir.mkdirs()) {
                throw IOException("Could not create queue directory: ${parentDir.path}")
            }
            FileOutputStream(temp).use { stream ->
                stream.write(payload)
                stream.flush()
                stream.fd.sync()
            }
            replaceTarget(temp, file)
        } catch (error: IOException) {
            logger.warn(TAG, "Could not persist upload queue to ${file.name}.", error)
        } finally {
            if (temp.exists()) {
                temp.delete()
            }
        }
    }

    private fun tempFile(): File = File(parentDir, "${file.name}.tmp")

    private fun replaceTarget(source: File, target: File) {
        try {
            Files.move(
                source.toPath(),
                target.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
        } catch (error: IOException) {
            if (!source.renameTo(target)) {
                throw IOException("Failed to move ${source.name} to ${target.name}.", error)
            }
        }
    }

    private fun encode(): JSONObject = JSONObject()
        .put(KEY_VERSION, SCHEMA_VERSION)
        .put(KEY_SESSIONS, JSONArray(sessions.values.map { it.toJson() }))
        .put(KEY_ITEMS, JSONArray(items.values.map { it.toJson() }))
        .put(KEY_MASTER_REQUESTS, JSONArray(masterRequests.values.map { it.toJson() }))
        .put(
            KEY_SEQS,
            JSONArray(
                seqs.entries.map { (key, seq) ->
                    JSONObject()
                        .put("sessionId", key.sessionId)
                        .put("tier", key.tier)
                        .put("seq", seq)
                },
            ),
        )

    private fun UploadSession.toJson(): JSONObject = JSONObject()
        .put("sessionId", sessionId)
        .put("slot", slot)
        .put("uploadGrant", uploadGrant)
        .put("ingestUrl", ingestUrl)
        .put("grantExpMs", grantExpMs)
        .put("tiersCsv", tiersCsv)
        .put("stoppedAtMs", stoppedAtMs)
        .put("lastSeqProxy", lastSeqProxy)
        .put("lastSeqMaster", lastSeqMaster)
        .put("manifestState", manifestState ?: JSONObject.NULL)
        .put("manifestAttempts", manifestAttempts)
        .put("nextManifestAtMs", nextManifestAtMs)
        .put("createdAtMs", createdAtMs)
        .put("masterGrant", masterGrant ?: JSONObject.NULL)
        .put("masterIngestUrl", masterIngestUrl ?: JSONObject.NULL)
        .put("masterGrantExpMs", masterGrantExpMs)

    private fun decodeSession(json: JSONObject): UploadSession = UploadSession(
        sessionId = json.strictString("sessionId"),
        slot = json.strictString("slot"),
        uploadGrant = json.strictString("uploadGrant"),
        ingestUrl = json.strictString("ingestUrl"),
        grantExpMs = json.strictLong("grantExpMs"),
        tiersCsv = json.strictString("tiersCsv"),
        stoppedAtMs = json.strictLong("stoppedAtMs"),
        lastSeqProxy = json.strictLong("lastSeqProxy"),
        lastSeqMaster = json.strictLong("lastSeqMaster"),
        manifestState = json.nullableString("manifestState"),
        manifestAttempts = json.strictInt("manifestAttempts"),
        nextManifestAtMs = json.strictLong("nextManifestAtMs"),
        createdAtMs = json.strictLong("createdAtMs"),
        masterGrant = json.nullableString("masterGrant"),
        masterIngestUrl = json.nullableString("masterIngestUrl"),
        masterGrantExpMs = json.strictLong("masterGrantExpMs"),
    )

    private fun UploadItem.toJson(): JSONObject = JSONObject()
        .put("key", key)
        .put("sessionId", sessionId)
        .put("slot", slot)
        .put("tier", tier)
        .put("seq", seq)
        .put("filePath", filePath)
        .put("bytes", bytes)
        .put("sha256", sha256)
        .put("mediaStartServerMs", mediaStartServerMs)
        .put("durationMs", durationMs)
        .put("state", state)
        .put("uploadId", uploadId ?: JSONObject.NULL)
        .put("partsJson", partsJson ?: JSONObject.NULL)
        .put("etagsJson", etagsJson ?: JSONObject.NULL)
        .put("verifyRestarts", verifyRestarts)
        .put("priority", priority)
        .put("attempts", attempts)
        .put("nextAttemptAtMs", nextAttemptAtMs)
        .put("lastError", lastError ?: JSONObject.NULL)
        .put("createdAtMs", createdAtMs)
        .put("updatedAtMs", updatedAtMs)

    private fun decodeItem(json: JSONObject): UploadItem = UploadItem(
        key = json.strictString("key"),
        sessionId = json.strictString("sessionId"),
        slot = json.strictString("slot"),
        tier = json.strictString("tier"),
        seq = json.strictLong("seq"),
        filePath = json.strictString("filePath"),
        bytes = json.strictLong("bytes"),
        sha256 = json.strictString("sha256"),
        mediaStartServerMs = json.strictLong("mediaStartServerMs"),
        durationMs = json.strictLong("durationMs"),
        state = json.strictString("state"),
        uploadId = json.nullableString("uploadId"),
        partsJson = json.nullableString("partsJson"),
        etagsJson = json.nullableString("etagsJson"),
        verifyRestarts = json.strictInt("verifyRestarts"),
        priority = json.strictLong("priority"),
        attempts = json.strictInt("attempts"),
        nextAttemptAtMs = json.strictLong("nextAttemptAtMs"),
        lastError = json.nullableString("lastError"),
        createdAtMs = json.strictLong("createdAtMs"),
        updatedAtMs = json.strictLong("updatedAtMs"),
    )

    private fun MasterRequest.toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("sessionId", sessionId)
        .put("slot", slot)
        .put("uploadGrant", uploadGrant)
        .put("ingestUrl", ingestUrl)
        .put("grantExpMs", grantExpMs)
        .put("seqsJson", seqsJson)
        .put("state", state)
        .put("attempts", attempts)
        .put("nextAttemptAtMs", nextAttemptAtMs)
        .put("lastError", lastError ?: JSONObject.NULL)
        .put("createdAtMs", createdAtMs)

    private fun decodeMasterRequest(json: JSONObject): MasterRequest = MasterRequest(
        id = json.strictString("id"),
        sessionId = json.strictString("sessionId"),
        slot = json.strictString("slot"),
        uploadGrant = json.strictString("uploadGrant"),
        ingestUrl = json.strictString("ingestUrl"),
        grantExpMs = json.strictLong("grantExpMs"),
        seqsJson = json.strictString("seqsJson"),
        state = json.strictString("state"),
        attempts = json.strictInt("attempts"),
        nextAttemptAtMs = json.strictLong("nextAttemptAtMs"),
        lastError = json.nullableString("lastError"),
        createdAtMs = json.strictLong("createdAtMs"),
    )

    private fun decodeSeq(json: JSONObject): Pair<SeqKey, Long> =
        SeqKey(json.strictString("sessionId"), json.strictString("tier")) to json.strictLong("seq")

    private fun JSONObject.optArrayOrEmpty(name: String): JSONArray {
        if (!has(name) || isNull(name)) {
            return JSONArray()
        }
        return get(name) as? JSONArray ?: throw JSONException("$name must be a JSON array")
    }

    private inline fun <T> JSONArray.mapObjects(decode: (JSONObject) -> T): List<T> = (0 until length()).map { index ->
        val element = get(index) as? JSONObject ?: throw JSONException("Array element at $index must be an object")
        decode(element)
    }

    private fun JSONObject.strictString(name: String): String {
        val value = if (has(name) && !isNull(name)) get(name) else throw JSONException("Missing $name")
        return value as? String ?: throw JSONException("$name must be a string")
    }

    private fun JSONObject.nullableString(name: String): String? {
        if (!has(name) || isNull(name)) {
            return null
        }
        return get(name) as? String ?: throw JSONException("$name must be a string")
    }

    private fun JSONObject.strictLong(name: String): Long {
        val value = if (has(name) && !isNull(name)) get(name) else throw JSONException("Missing $name")
        if (value !is Int && value !is Long) {
            throw JSONException("$name must be an integer")
        }
        return value.toLong()
    }

    private fun JSONObject.strictInt(name: String): Int {
        val value = strictLong(name)
        if (value !in Int.MIN_VALUE..Int.MAX_VALUE) {
            throw JSONException("$name out of Int range: $value")
        }
        return value.toInt()
    }

    private companion object {
        const val SCHEMA_VERSION = 1
        const val KEY_VERSION = "version"
        const val KEY_SESSIONS = "sessions"
        const val KEY_ITEMS = "items"
        const val KEY_MASTER_REQUESTS = "masterRequests"
        const val KEY_SEQS = "seqs"
        const val TAG = "FileUploadQueueStore"
    }
}
