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
import java.util.concurrent.TimeUnit
import kotlin.math.min

/**
 * H7: C2 v2 uploader. One [runOnce] call advances one due item by one step (or sends one manifest).
 *
 * - Proxy before master; a tier no grant lists is [UploadState.HELD] and stays on disk.
 * - Masters on request (1.4): [requestMasters] stores a `masters.upload`; its master-tier manifest
 *   is sent first, then the listed masters upload with that command's grant.
 * - Resumable: uploadId, presigned parts and per-part ETags are persisted after every step.
 * - Part bytes go through [throttle] (`upload.policy.maxKbps`).
 * - The local file is deleted only when K3 reports `verified`.
 * - After `recording.stopped`, once every granted item of the session is settled, the manifest is
 *   sent and any `missing` segment still on disk is re-queued.
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
    private val throttle: UploadThrottle = UploadThrottle(maxKbps = 0),
    /** Problems K2 should see in `state.lastError` (conflicts, rejected master manifests). */
    private val onAlert: (String) -> Unit = {},
) {
    /**
     * Advances one step: a due master manifest, else one item, else a session manifest. Returns
     * true when it did any work (call again). [includeMasters] false keeps master bytes off the
     * uplink (while recording, so proxies stay prompt).
     */
    fun runOnce(includeMasters: Boolean = true): Boolean {
        val now = clock.nowMs()
        val request = store.dueMasterRequest(now)
        if (request != null) {
            sendMasterManifest(request, now)
            return true
        }
        val item = store.nextDue(now, includeMasters)
        if (item != null) {
            step(item, now)
            return true
        }
        return sendDueManifest(now)
    }

    /**
     * Stores a `masters.upload` (1.4) and returns how many held masters it covers; 0 means the
     * caller nacks `gone` and nothing is stored. Idempotent per [commandId].
     *
     * @throws C1ProtocolException when the grant cannot cover this request.
     */
    fun requestMasters(commandId: String, request: MastersUpload): Int {
        val now = clock.nowMs()
        val claims = UploadGrantClaims.decode(request.uploadGrant)
        if (claims != null && claims.tiers.isNotEmpty() && C1.TIER_MASTER !in claims.tiers) {
            throw C1ProtocolException("uploadGrant does not list master.")
        }
        if (claims?.sessionId != null && claims.sessionId != request.sessionId) {
            throw C1ProtocolException("uploadGrant is for another session.")
        }
        val grantExpMs = claims?.expMs?.takeIf { it > 0 } ?: Long.MAX_VALUE
        if (now >= grantExpMs) {
            throw C1ProtocolException("uploadGrant expired.")
        }
        store.masterRequest(commandId)?.let { return JSONArray(it.seqsJson).length() }
        val held = store.items(request.sessionId).filter {
            it.tier == C1.TIER_MASTER && it.isHeldOnPhone() && request.covers(it.mediaStartServerMs, it.durationMs)
        }
        if (held.isEmpty()) {
            logger.info(TAG, "masters.upload for ${request.sessionId}: no masters held in range.")
            return 0
        }
        val slot = held.first().slot
        if (claims?.slot != null && claims.slot != slot) {
            throw C1ProtocolException("uploadGrant is for slot ${claims.slot}, not $slot.")
        }
        store.upsertMasterRequest(
            MasterRequest(
                id = commandId,
                sessionId = request.sessionId,
                slot = slot,
                uploadGrant = request.uploadGrant,
                ingestUrl = request.ingestUrl,
                grantExpMs = grantExpMs,
                seqsJson = JSONArray(held.map { it.seq }).toString(),
                createdAtMs = now,
            ),
        )
        logger.info(TAG, "masters.upload for ${request.sessionId}: ${held.size} master(s) to list.")
        return held.size
    }

    /** keepDays: deletes HELD or FAILED masters older than [keepDays]. Returns how many were deleted. */
    fun pruneMasters(keepDays: Int): Int {
        val cutoff = clock.nowMs() - keepDays * DAY_MS
        var pruned = 0
        for (item in store.idleMastersBefore(cutoff)) {
            val file = File(item.filePath)
            if (!file.isFile) {
                continue
            }
            if (!file.delete()) {
                logger.warn(TAG, "Could not delete expired master ${item.key}.")
                continue
            }
            finish(item, UploadState.FAILED, KEEP_DAYS_EXPIRED)
            pruned += 1
        }
        if (pruned > 0) {
            logger.info(TAG, "Deleted $pruned master(s) older than $keepDays day(s).")
        }
        return pruned
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
        val grants = grantsFor(item.tier, session)
        if (grants.isEmpty()) {
            finish(item, UploadState.HELD, null)
            return
        }
        val grant = grants.firstOrNull { now < it.expMs }
        if (grant == null) {
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
                UploadState.PENDING -> initUpload(item, grant, file)
                UploadState.UPLOADING -> uploadParts(item, grant, file)
                UploadState.VERIFYING -> pollStatus(item, grant, file)
                else -> Unit
            }
        } catch (error: IOException) {
            retryLater(item, error.message ?: error.javaClass.simpleName)
        } catch (error: JSONException) {
            retryLater(item, "bad_response")
        }
    }

    /** Grants that may upload [tier], preferred first: a `masters.upload` grant, then `record.start`'s. */
    private fun grantsFor(tier: String, session: UploadSession): List<Grant> {
        val grants = mutableListOf<Grant>()
        val masterGrant = session.masterGrant
        if (tier == C1.TIER_MASTER && masterGrant != null) {
            grants += Grant(masterGrant, session.masterIngestUrl ?: session.ingestUrl, session.masterGrantExpMs)
        }
        if (tier in session.tiers) {
            grants += Grant(session.uploadGrant, session.ingestUrl, session.grantExpMs)
        }
        return grants
    }

    private fun initUpload(item: UploadItem, grant: Grant, file: File) {
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
            .url(grant.url("/v2/uploads"))
            .header("Authorization", "Bearer ${grant.token}")
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
                    uploadParts(started, grant, file)
                }
                200 -> verified(item.copy(uploadId = json.optStringOrNull("uploadId")), file)
                409 -> initConflict(item, json.optStringOrNull("reason"))
                401, 403 -> finish(item, UploadState.FAILED, "grant_rejected_${response.code}")
                else -> retryLater(item, "init_http_${response.code}")
            }
        }
    }

    /** 1.6: `not-requested` is not an error: no request lists this master, so keep it held. */
    private fun initConflict(item: UploadItem, reason: String?) {
        if (reason == REASON_NOT_REQUESTED) {
            logger.info(TAG, "${item.key} not requested by K3; kept on the phone.")
            finish(item, UploadState.HELD, null)
            return
        }
        val error = "conflict: ${reason ?: "different bytes"}"
        finish(item, UploadState.CONFLICT, error)
        onAlert("${item.key} $error")
    }

    private fun uploadParts(item: UploadItem, grant: Grant, file: File) {
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
                .put(FileRangeBody(file, offset, length, CONTENT_TYPE_TS.toMediaType(), throttle))
                .build()
            val call = http.newCall(request)
            // A low maxKbps stretches a part beyond the client's call timeout.
            call.timeout().timeout(PART_TIMEOUT_BASE_NS + 2 * throttle.expectedNanos(length), TimeUnit.NANOSECONDS)
            call.execute().use { response ->
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
        complete(current, grant, parts, etags)
    }

    private fun complete(item: UploadItem, grant: Grant, parts: JSONArray, etags: JSONObject) {
        val partList = JSONArray()
        for (index in 0 until parts.length()) {
            val number = parts.getJSONObject(index).getInt("n")
            partList.put(JSONObject().put("n", number).put("etag", etags.getString(number.toString())))
        }
        val request = Request.Builder()
            .url(grant.url("/v2/uploads/${item.uploadId}/complete"))
            .header("Authorization", "Bearer ${grant.token}")
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

    private fun pollStatus(item: UploadItem, grant: Grant, file: File) {
        val request = Request.Builder()
            .url(grant.url("/v2/uploads/${item.uploadId}"))
            .header("Authorization", "Bearer ${grant.token}")
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
            // Requested masters upload under their own manifest; they never delay this one.
            if (items.any { it.uploadState.active && it.tier in session.tiers }) {
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
            .url(session.ingestUrl.trimEnd('/') + "/v2/sessions/${session.sessionId}/manifest")
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

    /** 1.4 master-tier manifest. Never sent empty (400); a 4xx is a bug: alert, no retry (1.6). */
    private fun sendMasterManifest(request: MasterRequest, now: Long) {
        if (now >= request.grantExpMs) {
            settleRequest(request, MasterRequest.STATE_REJECTED, "grant_expired")
            return
        }
        val seqs = JSONArray(request.seqsJson)
        val held = (0 until seqs.length())
            .mapNotNull { store.item(UploadItem.keyOf(request.sessionId, C1.TIER_MASTER, seqs.getLong(it))) }
            .filter { it.isHeldOnPhone() }
        if (held.isEmpty()) {
            settleRequest(request, MasterRequest.STATE_GONE, "masters_gone_before_manifest")
            return
        }
        val segments = JSONArray()
        held.forEach { segments.put(JSONObject().put("seq", it.seq).put("sha256", it.sha256)) }
        val body = JSONObject().put("slot", request.slot).put("tier", C1.TIER_MASTER).put("segments", segments)
        val call = Request.Builder()
            .url(request.ingestUrl.trimEnd('/') + "/v2/sessions/${request.sessionId}/manifest")
            .header("Authorization", "Bearer ${request.uploadGrant}")
            .post(body.toString().toRequestBody(JSON_MEDIA_TYPE))
            .build()
        try {
            http.newCall(call).execute().use { response ->
                when {
                    response.isSuccessful -> acceptMasters(request, held)
                    response.code in 400..499 && response.code != 408 && response.code != 429 ->
                        settleRequest(request, MasterRequest.STATE_REJECTED, "master_manifest_http_${response.code}")
                    else -> retryRequest(request, "master_manifest_http_${response.code}")
                }
            }
        } catch (error: IOException) {
            retryRequest(request, error.message ?: "master_manifest_io")
        }
    }

    private fun acceptMasters(request: MasterRequest, held: List<UploadItem>) {
        val now = clock.nowMs()
        val session = store.session(request.sessionId)
            ?: UploadSession(
                sessionId = request.sessionId,
                slot = request.slot,
                uploadGrant = "",
                ingestUrl = request.ingestUrl,
                grantExpMs = 0,
                tiersCsv = "",
                createdAtMs = now,
            )
        // Keep whichever master grant lasts longer; both list this session's masters.
        if (session.masterGrant == null || request.grantExpMs >= session.masterGrantExpMs) {
            store.upsertSession(
                session.copy(
                    masterGrant = request.uploadGrant,
                    masterIngestUrl = request.ingestUrl,
                    masterGrantExpMs = request.grantExpMs,
                ),
            )
        }
        var queued = 0
        for (item in held) {
            if (item.uploadState == UploadState.HELD || item.uploadState == UploadState.FAILED) {
                store.update(
                    item.copy(
                        state = UploadState.PENDING.name,
                        uploadId = null,
                        partsJson = null,
                        etagsJson = null,
                        attempts = 0,
                        nextAttemptAtMs = 0,
                        lastError = null,
                        updatedAtMs = now,
                    ),
                )
                queued += 1
            }
        }
        store.upsertMasterRequest(
            request.copy(state = MasterRequest.STATE_SENT, attempts = request.attempts + 1, lastError = null),
        )
        logger.info(TAG, "Master manifest for ${request.sessionId} accepted; queued $queued master(s).")
    }

    private fun settleRequest(request: MasterRequest, state: String, error: String) {
        store.upsertMasterRequest(request.copy(state = state, attempts = request.attempts + 1, lastError = error))
        logger.warn(TAG, "masters.upload ${request.id} for ${request.sessionId} -> $state: $error")
        onAlert("masters.upload ${request.sessionId}: $error")
    }

    private fun retryRequest(request: MasterRequest, error: String) {
        logger.warn(TAG, "Master manifest for ${request.sessionId} failed: $error")
        val attempts = request.attempts + 1
        store.upsertMasterRequest(
            request.copy(attempts = attempts, nextAttemptAtMs = clock.nowMs() + backoffMs(attempts), lastError = error),
        )
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

    /** On the phone and not yet accepted by K3 under different bytes. */
    private fun UploadItem.isHeldOnPhone(): Boolean =
        uploadState != UploadState.VERIFIED && uploadState != UploadState.CONFLICT && File(filePath).isFile

    private class Grant(val token: String, val ingestUrl: String, val expMs: Long) {
        fun url(path: String): String = ingestUrl.trimEnd('/') + path
    }

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
        private val throttle: UploadThrottle,
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
                    throttle.acquire(read)
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
        const val REASON_NOT_REQUESTED = "not-requested"
        const val KEEP_DAYS_EXPIRED = "keep_days_expired"
        private const val DAY_MS = 24 * 60 * 60 * 1000L
        private const val PART_TIMEOUT_BASE_NS = 120_000_000_000L
        private const val COPY_BUFFER_BYTES = 64 * 1024
        private val JSON_MEDIA_TYPE = "application/json".toMediaType()
        private const val TAG = "CourtUploader"
    }
}
