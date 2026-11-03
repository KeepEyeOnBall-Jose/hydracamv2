package com.amaia23.hydracam.court

import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okio.BufferedSink
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import kotlin.math.min

/**
 * H7: C2 v2 uploader. One [runOnce] call advances one due item by one step (or sends one manifest).
 *
 * - Proxy before master; a tier the grant does not list is [UploadState.HELD] and stays on disk.
 * - Resumable: uploadId, presigned parts and per-part ETags are persisted after every step.
 * - The local file is deleted only when K3 reports `verified`.
 * - After `recording.stopped`, once every item of the session is settled, the manifest is sent and
 *   any `missing` segment still on disk is re-queued.
 */
class C2Uploader(
    private val http: OkHttpClient,
    private val store: UploadQueueStore,
    private val clock: CourtClock = CourtClock.SYSTEM,
    private val logger: CourtLogger = NoopCourtLogger,
    private val partSizeBytes: Long = DEFAULT_PART_SIZE_BYTES,
    private val statusPollMs: Long = 2_000,
    private val baseBackoffMs: Long = 2_000,
    private val maxBackoffMs: Long = 5 * 60_000L,
) {
    /** Returns true when it did any work (call again), false when nothing is due. */
    fun runOnce(): Boolean {
        val now = clock.nowMs()
        val item = store.nextDue(now)
        if (item != null) {
            step(item, now)
            return true
        }
        return sendDueManifest(now)
    }

    /** Called by the runtime after `recording.stopped`. */
    fun onSessionStopped(sessionId: String, lastSeqProxy: Long, lastSeqMaster: Long) {
        val session = store.session(sessionId) ?: return
        store.upsertSession(
            session.copy(
                stoppedAtMs = clock.nowMs(),
                lastSeqProxy = lastSeqProxy,
                lastSeqMaster = lastSeqMaster,
            ),
        )
    }

    fun enqueue(segment: SegmentRecord) {
        val now = clock.nowMs()
        val item = UploadItem.from(segment, now)
        val session = store.session(segment.sessionId)
        val held = session != null && segment.tier !in session.tiers
        store.enqueue(if (held) item.copy(state = UploadState.HELD.name) else item)
    }

    private fun step(item: UploadItem, now: Long) {
        val session = store.session(item.sessionId)
        if (session == null) {
            finish(item, UploadState.FAILED, "no_grant")
            return
        }
        if (item.tier !in session.tiers) {
            finish(item, UploadState.HELD, null)
            return
        }
        if (now >= session.grantExpMs) {
            finish(item, UploadState.FAILED, "grant_expired")
            return
        }
        val file = File(item.filePath)
        if (item.uploadState != UploadState.VERIFYING && !file.isFile) {
            finish(item, UploadState.FAILED, "file_missing")
            return
        }
        try {
            when (item.uploadState) {
                UploadState.PENDING -> initUpload(item, session, file)
                UploadState.UPLOADING -> uploadParts(item, session, file)
                UploadState.VERIFYING -> pollStatus(item, session, file)
                else -> Unit
            }
        } catch (error: IOException) {
            retryLater(item, error.message ?: error.javaClass.simpleName)
        } catch (error: JSONException) {
            retryLater(item, "bad_response")
        }
    }

    private fun initUpload(item: UploadItem, session: UploadSession, file: File) {
        val body = JSONObject()
            .put("sessionId", item.sessionId)
            .put("slot", item.slot)
            .put("tier", item.tier)
            .put("seq", item.seq)
            .put("bytes", item.bytes)
            .put("sha256", item.sha256)
            .put("contentType", CONTENT_TYPE_TS)
            .put("mediaStartServerMs", item.mediaStartServerMs)
            .put("durationMs", item.durationMs)
        val request = Request.Builder()
            .url(ingest(session, "/v2/uploads"))
            .header("Authorization", "Bearer ${session.uploadGrant}")
            .post(body.toString().toRequestBody(JSON_MEDIA_TYPE))
            .build()
        http.newCall(request).execute().use { response ->
            val json = response.jsonBody()
            when (response.code) {
                201 -> {
                    val parts = json.getJSONArray("parts")
                    val started = item.copy(
                        state = UploadState.UPLOADING.name,
                        uploadId = json.getString("uploadId"),
                        partsJson = parts.toString(),
                        etagsJson = JSONObject().toString(),
                        lastError = null,
                        updatedAtMs = clock.nowMs(),
                    )
                    store.update(started)
                    uploadParts(started, session, file)
                }
                200 -> verified(item.copy(uploadId = json.optStringOrNull("uploadId")), file)
                409 -> finish(item, UploadState.CONFLICT, "conflict: ${json.optStringOrNull("reason") ?: "different bytes"}")
                401, 403 -> finish(item, UploadState.FAILED, "grant_rejected_${response.code}")
                else -> retryLater(item, "init_http_${response.code}")
            }
        }
    }

    private fun uploadParts(item: UploadItem, session: UploadSession, file: File) {
        val parts = JSONArray(item.partsJson ?: "[]")
        val etags = JSONObject(item.etagsJson ?: "{}")
        var current = item
        for (index in 0 until parts.length()) {
            val part = parts.getJSONObject(index)
            val number = part.getInt("n")
            if (etags.has(number.toString())) {
                continue
            }
            val offset = (number - 1) * partSizeBytes
            val length = min(partSizeBytes, file.length() - offset)
            if (length <= 0) {
                retryLater(current, "part_${number}_out_of_range")
                return
            }
            val request = Request.Builder()
                .url(part.getString("url"))
                .put(FileRangeBody(file, offset, length, CONTENT_TYPE_TS.toMediaType()))
                .build()
            http.newCall(request).execute().use { response ->
                when {
                    response.isSuccessful -> {
                        val etag = response.header("ETag")
                            ?: run {
                                retryLater(current, "part_${number}_no_etag")
                                return
                            }
                        etags.put(number.toString(), etag)
                        current = current.copy(etagsJson = etags.toString(), updatedAtMs = clock.nowMs())
                        store.update(current)
                    }
                    response.code == 403 -> {
                        // Presigned URL expired: start over with a fresh init.
                        restart(current, "part_url_expired")
                        return
                    }
                    else -> {
                        retryLater(current, "part_${number}_http_${response.code}")
                        return
                    }
                }
            }
        }
        complete(current, session, parts, etags)
    }

    private fun complete(item: UploadItem, session: UploadSession, parts: JSONArray, etags: JSONObject) {
        val partList = JSONArray()
        for (index in 0 until parts.length()) {
            val number = parts.getJSONObject(index).getInt("n")
            partList.put(JSONObject().put("n", number).put("etag", etags.getString(number.toString())))
        }
        val request = Request.Builder()
            .url(ingest(session, "/v2/uploads/${item.uploadId}/complete"))
            .header("Authorization", "Bearer ${session.uploadGrant}")
            .post(JSONObject().put("parts", partList).toString().toRequestBody(JSON_MEDIA_TYPE))
            .build()
        http.newCall(request).execute().use { response ->
            when {
                response.isSuccessful -> store.update(
                    item.copy(
                        state = UploadState.VERIFYING.name,
                        nextAttemptAtMs = clock.nowMs() + statusPollMs,
                        lastError = null,
                        updatedAtMs = clock.nowMs(),
                    ),
                )
                response.code == 404 -> restart(item, "upload_unknown")
                else -> retryLater(item, "complete_http_${response.code}")
            }
        }
    }

    private fun pollStatus(item: UploadItem, session: UploadSession, file: File) {
        val request = Request.Builder()
            .url(ingest(session, "/v2/uploads/${item.uploadId}"))
            .header("Authorization", "Bearer ${session.uploadGrant}")
            .get()
            .build()
        http.newCall(request).execute().use { response ->
            if (response.code == 404) {
                restart(item, "upload_unknown")
                return
            }
            if (!response.isSuccessful) {
                retryLater(item, "status_http_${response.code}")
                return
            }
            val json = response.jsonBody()
            when (json.optStringOrNull("state")) {
                "verified" -> verified(item, file)
                "failed" -> restart(item, "verify_failed: ${json.optStringOrNull("reason") ?: "unknown"}")
                else -> store.update(item.copy(nextAttemptAtMs = clock.nowMs() + statusPollMs, updatedAtMs = clock.nowMs()))
            }
        }
    }

    private fun sendDueManifest(now: Long): Boolean {
        for (session in store.sessions()) {
            if (session.stoppedAtMs <= 0 ||
                session.manifestState == UploadSession.MANIFEST_COMPLETE ||
                session.nextManifestAtMs > now ||
                now >= session.grantExpMs
            ) {
                continue
            }
            val items = store.items(session.sessionId)
            if (items.any { it.uploadState.active }) {
                continue
            }
            sendManifest(session, items)
            return true
        }
        return false
    }

    private fun sendManifest(session: UploadSession, items: List<UploadItem>) {
        val segments = JSONArray()
        // Only granted tiers: HELD masters were never offered to K3. lastSeq still reports them.
        items.filter {
            it.tier in session.tiers && (it.uploadState != UploadState.FAILED || File(it.filePath).isFile)
        }.forEach { item ->
            segments.put(JSONObject().put("tier", item.tier).put("seq", item.seq).put("sha256", item.sha256))
        }
        val body = JSONObject()
            .put("slot", session.slot)
            .put("lastSeq", JSONObject().put(C1.TIER_PROXY, session.lastSeqProxy).put(C1.TIER_MASTER, session.lastSeqMaster))
            .put("segments", segments)
        val request = Request.Builder()
            .url(ingest(session, "/v2/sessions/${session.sessionId}/manifest"))
            .header("Authorization", "Bearer ${session.uploadGrant}")
            .post(body.toString().toRequestBody(JSON_MEDIA_TYPE))
            .build()
        try {
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    manifestRetry(session, null, "manifest_http_${response.code}")
                    return
                }
                val json = response.jsonBody()
                val state = json.optStringOrNull("state")
                if (state == UploadSession.MANIFEST_COMPLETE) {
                    logger.info(TAG, "Manifest complete for ${session.sessionId}.")
                    store.upsertSession(session.copy(manifestState = state, manifestAttempts = session.manifestAttempts + 1))
                    return
                }
                val requeued = requeueMissing(session, json.optJSONArray("missing") ?: JSONArray())
                logger.info(TAG, "Manifest partial for ${session.sessionId}; re-queued $requeued segment(s).")
                if (requeued == 0) {
                    // Nothing left on the phone can fill the gap; re-sending would only loop until the grant expires.
                    store.upsertSession(
                        session.copy(
                            manifestState = UploadSession.MANIFEST_PARTIAL,
                            manifestAttempts = session.manifestAttempts + 1,
                            nextManifestAtMs = Long.MAX_VALUE,
                        ),
                    )
                    return
                }
                manifestRetry(session, UploadSession.MANIFEST_PARTIAL, null)
            }
        } catch (error: IOException) {
            manifestRetry(session, null, error.message ?: "manifest_io")
        } catch (error: JSONException) {
            manifestRetry(session, null, "manifest_bad_response")
        }
    }

    private fun requeueMissing(session: UploadSession, missing: JSONArray): Int {
        var count = 0
        for (index in 0 until missing.length()) {
            val entry = missing.getJSONObject(index)
            val key = UploadItem.keyOf(session.sessionId, entry.getString("tier"), entry.getLong("seq"))
            val item = store.item(key) ?: continue
            if (File(item.filePath).isFile && item.uploadState != UploadState.HELD) {
                store.update(item.copy(state = UploadState.PENDING.name, uploadId = null, partsJson = null, etagsJson = null, nextAttemptAtMs = 0))
                count += 1
            } else {
                logger.warn(TAG, "K3 reports $key missing but the file is gone (state ${item.state}).")
            }
        }
        return count
    }

    private fun manifestRetry(session: UploadSession, state: String?, error: String?) {
        if (error != null) {
            logger.warn(TAG, "Manifest for ${session.sessionId} failed: $error")
        }
        val attempts = session.manifestAttempts + 1
        store.upsertSession(
            session.copy(
                manifestState = state ?: session.manifestState,
                manifestAttempts = attempts,
                nextManifestAtMs = clock.nowMs() + backoffMs(attempts),
            ),
        )
    }

    private fun verified(item: UploadItem, file: File) {
        if (file.isFile && !file.delete()) {
            logger.warn(TAG, "Verified ${item.key} but could not delete ${file.name}.")
        }
        finish(item, UploadState.VERIFIED, null)
        logger.info(TAG, "Verified ${item.key}; local file deleted.")
    }

    private fun restart(item: UploadItem, reason: String) {
        logger.warn(TAG, "Restarting ${item.key}: $reason")
        val attempts = item.attempts + 1
        store.update(
            item.copy(
                state = UploadState.PENDING.name,
                uploadId = null,
                partsJson = null,
                etagsJson = null,
                attempts = attempts,
                nextAttemptAtMs = clock.nowMs() + backoffMs(attempts),
                lastError = reason,
                updatedAtMs = clock.nowMs(),
            ),
        )
    }

    private fun retryLater(item: UploadItem, reason: String) {
        logger.warn(TAG, "Retrying ${item.key} later: $reason")
        val attempts = item.attempts + 1
        store.update(
            item.copy(
                attempts = attempts,
                nextAttemptAtMs = clock.nowMs() + backoffMs(attempts),
                lastError = reason,
                updatedAtMs = clock.nowMs(),
            ),
        )
    }

    private fun finish(item: UploadItem, state: UploadState, error: String?) {
        if (error != null) {
            logger.warn(TAG, "${item.key} -> $state: $error")
        }
        store.update(item.copy(state = state.name, lastError = error, updatedAtMs = clock.nowMs()))
    }

    private fun backoffMs(attempts: Int): Long = min(maxBackoffMs, baseBackoffMs shl min(attempts - 1, 16))

    private fun ingest(session: UploadSession, path: String): String = session.ingestUrl.trimEnd('/') + path

    private fun Response.jsonBody(): JSONObject {
        val text = body?.string().orEmpty()
        return if (text.isBlank()) JSONObject() else JSONObject(text)
    }

    /** Streams `[offset, offset + length)` of [file] without loading it into memory. */
    private class FileRangeBody(
        private val file: File,
        private val offset: Long,
        private val length: Long,
        private val mediaType: MediaType,
    ) : RequestBody() {
        override fun contentType(): MediaType = mediaType

        override fun contentLength(): Long = length

        override fun writeTo(sink: BufferedSink) {
            RandomAccessFile(file, "r").use { input ->
                input.seek(offset)
                val buffer = ByteArray(COPY_BUFFER_BYTES)
                var remaining = length
                while (remaining > 0) {
                    val read = input.read(buffer, 0, min(buffer.size.toLong(), remaining).toInt())
                    if (read < 0) {
                        throw IOException("${file.name} shrank during upload.")
                    }
                    sink.write(buffer, 0, read)
                    remaining -= read
                }
            }
        }
    }

    companion object {
        /** C2 says "16 MB parts"; read as MiB. A 6 s segment at 8 Mbps is ~6 MB, so one part. */
        const val DEFAULT_PART_SIZE_BYTES = 16L * 1024 * 1024
        const val CONTENT_TYPE_TS = "video/mp2t"
        private const val COPY_BUFFER_BYTES = 64 * 1024
        private val JSON_MEDIA_TYPE = "application/json".toMediaType()
        private const val TAG = "CourtUploader"
    }
}
