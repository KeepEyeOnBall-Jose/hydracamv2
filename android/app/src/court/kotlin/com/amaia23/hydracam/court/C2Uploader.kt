package com.amaia23.hydracam.court

import okhttp3.Call
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
 * - Masters stream (1.11): with the record.start grant listing masters, they upload during and
 *   after recording, but only while no proxy is due (checked again before every master part). A
 *   `masters.upload` is then a queue jump: its masters go to the front of the master queue.
 * - Resumable: uploadId, presigned parts and per-part ETags are persisted after every step.
 * - Part bytes go through [throttle] (`upload.policy.maxKbps`; masters also `masterMaxKbps`).
 * - Masters move only while [mastersAllowed]; [preemptMasters] cancels a master part in flight
 *   once the gate closes.
 * - The local file is deleted only when K3 reports `verified`; nothing else deletes a segment.
 * - After `recording.stopped`, once every granted proxy of the session is settled, the manifest is
 *   sent and any `missing` segment still on disk is re-queued (a master still uploading counts).
 */
class C2Uploader(
    private val http: OkHttpClient,
    private val store: UploadQueueStore,
    private val clock: CourtClock = CourtClock.SYSTEM,
    private val logger: CourtLogger = NoopCourtLogger,
    private val partSizeBytes: Long = DEFAULT_PART_SIZE_BYTES,
    private val statusPollMs: Long = 2_000,
    private val baseBackoffMs: Long = 2_000,
    private val maxBackoffMs: Long = 300_000L,
    private val throttle: UploadThrottle = UploadThrottle(maxKbps = 0),
    /** Problems K2 should see in `state.lastError` (conflicts, rejected master manifests). */
    private val onAlert: (String) -> Unit = {},
    /** Live gate: false while a session is armed or recording, so proxies stay prompt (K4). */
    private val mastersAllowed: () -> Boolean = { true },
) {
    private val callLock = Any()
    private var masterCall: Call? = null

    /**
     * Advances one step: a due master manifest, else one proxy, else a session manifest, else one
     * master. Returns true when it did any work (call again). [includeMasters] false keeps master
     * bytes off the uplink (masters held, or recording without `stream`).
     */
    fun runOnce(includeMasters: Boolean = mastersAllowed()): Boolean {
        val now = clock.nowMs()
        val request = store.dueMasterRequest(now)
        val proxy = if (request == null) store.nextDue(now, includeMasters = false) else null
        return when {
            request != null -> {
                sendMasterManifest(request, now)
                true
            }
            proxy != null -> {
                step(proxy, now)
                true
            }
            sendDueManifest(now) -> true
            else -> includeMasters && stepMaster(now)
        }
    }

    private fun stepMaster(now: Long): Boolean {
        val master = store.nextDue(now, includeMasters = true) ?: return false
        step(master, now)
        return true
    }

    /**
     * Cancels the master part in flight, if any, once the gate closes, so a new recording's proxies
     * do not wait behind up to [partSizeBytes] on a slow uplink. A streaming master (gate still open)
     * keeps its part on the wire. Resumable: the ETags of finished parts are kept.
     */
    fun preemptMasters() {
        if (!mastersAllowed()) {
            synchronized(callLock) { masterCall }?.cancel()
        }
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
        val grantExpMs = claims?.expMs?.takeIf { it > 0 } ?: Long.MAX_VALUE
        masterGrantProblem(claims, request.sessionId, grantExpMs, now)?.let { throw C1ProtocolException(it) }
        store.masterRequest(commandId)?.let { return JSONArray(it.seqsJson).length() }
        val held = store.items(request.sessionId).filter {
            it.tier == C1.TIER_MASTER && it.isHeldOnPhone() && request.covers(it.mediaStartServerMs, it.durationMs)
        }
        val slot = held.firstOrNull()?.slot
        if (slot != null && claims?.slot != null && claims.slot != slot) {
            throw C1ProtocolException("uploadGrant is for slot ${claims.slot}, not $slot.")
        }
        if (slot == null) {
            logger.info(TAG, "masters.upload for ${request.sessionId}: no masters held in range.")
        } else {
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
        }
        return held.size
    }

    /** Why a grant with [claims] cannot cover a `masters.upload` for [sessionId], or null when it can. */
    private fun masterGrantProblem(
        claims: UploadGrantClaims?,
        sessionId: String,
        grantExpMs: Long,
        now: Long,
    ): String? = when {
        claims != null && claims.tiers.isNotEmpty() && C1.TIER_MASTER !in claims.tiers ->
            "uploadGrant does not list master."
        claims?.sessionId != null && claims.sessionId != sessionId -> "uploadGrant is for another session."
        now >= grantExpMs -> "uploadGrant expired."
        else -> null
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
        val grant = readyGrant(item, now) ?: return
        val file = File(item.filePath)
        try {
            when (item.uploadState) {
                UploadState.PENDING -> initUpload(item, grant, file)
                UploadState.UPLOADING -> uploadParts(item, grant, file)
                UploadState.VERIFYING -> pollStatus(item, grant, file)
                else -> Unit
            }
        } catch (error: IOException) {
            if (item.tier == C1.TIER_MASTER && !mastersAllowed()) {
                // Preempted, not failed: the stored item keeps its parts and its attempt count.
                logger.info(TAG, "${item.key} paused: masters held or recording.")
            } else {
                retryLater(stored(item), error.message ?: error.javaClass.simpleName)
            }
        } catch (ignored: JSONException) {
            retryLater(stored(item), "bad_response")
        }
    }

    /** The stored row of [item]: init may have moved it to UPLOADING (uploadId, parts) before the failure. */
    private fun stored(item: UploadItem): UploadItem = store.item(item.key) ?: item

    /** The grant [item] uploads under now, or null after settling an item that cannot upload. */
    private fun readyGrant(item: UploadItem, now: Long): Grant? {
        val session = store.session(item.sessionId)
        val grants = session?.let { grantsFor(item.tier, it) }.orEmpty()
        val grant = grants.firstOrNull { now < it.expMs }
        val problem: Pair<UploadState, String?>? = when {
            session == null -> UploadState.FAILED to "no_grant"
            grants.isEmpty() -> UploadState.HELD to null
            grant == null -> UploadState.FAILED to "grant_expired"
            item.uploadState != UploadState.VERIFYING && !File(item.filePath).isFile ->
                UploadState.FAILED to "file_missing"
            else -> null
        }
        problem?.let { (state, error) -> finish(item, state, error) }
        return if (problem == null) grant else null
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
        val request = postJson(grant.url("/v2/uploads"), grant.token, body)
        http.newCall(request).execute().use { response ->
            val json = response.jsonBody()
            when (response.code) {
                HttpStatus.CREATED -> {
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
                HttpStatus.OK -> verified(item.copy(uploadId = json.optStringOrNull("uploadId")), file)
                HttpStatus.CONFLICT -> initConflict(item, json.optStringOrNull("reason"))
                HttpStatus.UNAUTHORIZED, HttpStatus.FORBIDDEN ->
                    finish(item, UploadState.FAILED, "grant_rejected_${response.code}")
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
            if (!etags.has(number.toString())) {
                current = uploadPart(current, file, number, part.getString("url"), etags) ?: return
            }
        }
        complete(current, grant, parts, etags)
    }

    /** PUTs part [number]; returns the item with its ETag recorded, or null once the item is settled for now. */
    private fun uploadPart(item: UploadItem, file: File, number: Int, url: String, etags: JSONObject): UploadItem? {
        val master = item.tier == C1.TIER_MASTER
        val pause = if (master) masterPause() else null
        val offset = (number - 1) * partSizeBytes
        val length = min(partSizeBytes, file.length() - offset)
        when {
            pause != null -> logger.info(TAG, "${item.key} paused after part ${number - 1}: $pause.")
            length <= 0 -> retryLater(item, "part_${number}_out_of_range")
            else -> return putPart(item, partCall(file, url, offset, length, master), number, etags)
        }
        return null
    }

    /** Why a master may not PUT its next part now, or null. 1.11: it also waits while any proxy is due. */
    private fun masterPause(): String? = when {
        !mastersAllowed() -> "masters held or recording"
        store.nextDue(clock.nowMs(), includeMasters = false) != null -> "a proxy is due"
        else -> null
    }

    private fun putPart(item: UploadItem, call: Call, number: Int, etags: JSONObject): UploadItem? =
        executePart(item, call).use { response ->
            val etag = response.header("ETag")
            when {
                response.isSuccessful && etag != null -> {
                    etags.put(number.toString(), etag)
                    item.copy(etagsJson = etags.toString(), updatedAtMs = clock.nowMs()).also { store.update(it) }
                }
                response.isSuccessful -> {
                    retryLater(item, "part_${number}_no_etag")
                    null
                }
                response.code == HttpStatus.FORBIDDEN -> {
                    // Presigned URL expired: start over with a fresh init.
                    restart(item, "part_url_expired")
                    null
                }
                else -> {
                    retryLater(item, "part_${number}_http_${response.code}")
                    null
                }
            }
        }

    private fun partCall(file: File, url: String, offset: Long, length: Long, master: Boolean): Call {
        val request = Request.Builder()
            .url(url)
            .put(FileRangeBody(file, offset, length, CONTENT_TYPE_TS.toMediaType(), throttle, master))
            .build()
        return http.newCall(request).apply {
            // A low maxKbps stretches a part beyond the client's call timeout.
            val expectedNs = throttle.expectedNanos(length, master)
            timeout().timeout(PART_TIMEOUT_BASE_NS + 2 * expectedNs, TimeUnit.NANOSECONDS)
        }
    }

    /** Registers a master part for [preemptMasters]; re-checks the gate to close the race with it. */
    private fun executePart(item: UploadItem, call: Call): Response {
        if (item.tier != C1.TIER_MASTER) {
            return call.execute()
        }
        synchronized(callLock) { masterCall = call }
        try {
            if (!mastersAllowed()) {
                call.cancel()
            }
            return call.execute()
        } finally {
            synchronized(callLock) { masterCall = null }
        }
    }

    private fun complete(item: UploadItem, grant: Grant, parts: JSONArray, etags: JSONObject) {
        val partList = JSONArray()
        for (index in 0 until parts.length()) {
            val number = parts.getJSONObject(index).getInt("n")
            partList.put(JSONObject().put("n", number).put("etag", etags.getString(number.toString())))
        }
        val request = postJson(
            grant.url("/v2/uploads/${item.uploadId}/complete"),
            grant.token,
            JSONObject().put("parts", partList),
        )
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
                response.code == HttpStatus.NOT_FOUND -> restart(item, "upload_unknown")
                // K3 R5b: 409 {state: failed, reason}; the key is re-declared with a new multipart.
                response.code == HttpStatus.CONFLICT ->
                    verifyFailed(item, runCatching { response.jsonBody().optStringOrNull("reason") }.getOrNull())
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
            if (response.code == HttpStatus.NOT_FOUND) {
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
                "failed" -> verifyFailed(item, json.optStringOrNull("reason"))
                else -> store.update(
                    item.copy(nextAttemptAtMs = clock.nowMs() + statusPollMs, updatedAtMs = clock.nowMs()),
                )
            }
        }
    }

    private fun sendDueManifest(now: Long): Boolean {
        val (session, items) = store.sessions().asSequence()
            .filter { manifestDue(it, now) }
            .map { it to store.items(it.sessionId) }
            // Only granted proxies hold it back: 1.11 streamed masters may still be uploading, and
            // requested masters upload under their own manifest.
            .firstOrNull { (session, items) ->
                items.none { it.uploadState.active && it.tier == C1.TIER_PROXY && it.tier in session.tiers }
            }
            ?: return false
        sendManifest(session, items)
        return true
    }

    /** Stopped, not yet complete, past its retry time, and still under its grant. */
    private fun manifestDue(session: UploadSession, now: Long): Boolean = session.stoppedAtMs > 0 &&
        session.manifestState != UploadSession.MANIFEST_COMPLETE &&
        session.nextManifestAtMs <= now &&
        now < session.grantExpMs

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
            .put(
                "lastSeq",
                JSONObject().put(C1.TIER_PROXY, session.lastSeqProxy).put(C1.TIER_MASTER, session.lastSeqMaster),
            )
            .put("segments", segments)
        val request = postJson(manifestUrl(session.ingestUrl, session.sessionId), session.uploadGrant, body)
        try {
            http.newCall(request).execute().use { response ->
                if (response.isSuccessful) {
                    onManifestAnswer(session, response.jsonBody())
                } else {
                    manifestRetry(session, null, "manifest_http_${response.code}")
                }
            }
        } catch (error: IOException) {
            manifestRetry(session, null, error.message ?: "manifest_io")
        } catch (ignored: JSONException) {
            manifestRetry(session, null, "manifest_bad_response")
        }
    }

    private fun onManifestAnswer(session: UploadSession, json: JSONObject) {
        if (json.optStringOrNull("state") == UploadSession.MANIFEST_COMPLETE) {
            logger.info(TAG, "Manifest complete for ${session.sessionId}.")
            store.upsertSession(
                session.copy(
                    manifestState = UploadSession.MANIFEST_COMPLETE,
                    manifestAttempts = session.manifestAttempts + 1,
                ),
            )
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
        } else {
            manifestRetry(session, UploadSession.MANIFEST_PARTIAL, null)
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
        val call = postJson(manifestUrl(request.ingestUrl, request.sessionId), request.uploadGrant, body)
        try {
            http.newCall(call).execute().use { response ->
                when {
                    response.isSuccessful -> acceptMasters(request, held)
                    HttpStatus.isPermanentClientError(response.code) ->
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
            // 1.11 queue jump: the latest request goes to the front of the master queue.
            val jumped = item.copy(priority = now, updatedAtMs = now)
            if (item.uploadState == UploadState.HELD || item.uploadState == UploadState.FAILED) {
                store.update(jumped.restarted().copy(attempts = 0, nextAttemptAtMs = 0, lastError = null))
                queued += 1
            } else {
                store.update(jumped)
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
            // A CONFLICT would only fail again, so it stays put. A capped verify failure that K3 still
            // wants gets a fresh restart budget; manifest backoff and the grant bound the loop. An
            // active item (a streamed master still uploading) is already on its way: no restart.
            if (item.uploadState.active) {
                count += 1
            } else if (item.canRefill()) {
                store.update(item.restarted().copy(nextAttemptAtMs = 0, verifyRestarts = 0))
                count += 1
            } else {
                logger.warn(TAG, "K3 reports $key missing; not re-queued (state ${item.state}).")
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
            item.restarted().copy(
                attempts = attempts,
                nextAttemptAtMs = clock.nowMs() + backoffMs(attempts),
                lastError = reason,
                updatedAtMs = clock.nowMs(),
            ),
        )
    }

    /**
     * K3 rejected the bytes (C1 v1.7: size-mismatch | sha256-mismatch | upload-expired). Restarts
     * with backoff up to [MAX_VERIFY_RESTARTS] times, then FAILED with the file kept and an alert.
     */
    private fun verifyFailed(item: UploadItem, reason: String?) {
        val error = "verify_failed: ${reason ?: "unknown"}"
        if (item.verifyRestarts >= MAX_VERIFY_RESTARTS) {
            finish(item, UploadState.FAILED, "$error (gave up after $MAX_VERIFY_RESTARTS restarts)")
            onAlert("${item.key} $error")
            return
        }
        restart(item.copy(verifyRestarts = item.verifyRestarts + 1), error)
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

    private fun backoffMs(attempts: Int): Long =
        min(maxBackoffMs, baseBackoffMs shl min(attempts - 1, MAX_BACKOFF_SHIFT))

    /** Back to PENDING with no multipart, so the next attempt re-declares the key. */
    private fun UploadItem.restarted(): UploadItem =
        copy(state = UploadState.PENDING.name, uploadId = null, partsJson = null, etagsJson = null)

    private fun postJson(url: String, bearer: String, body: JSONObject): Request = Request.Builder()
        .url(url)
        .header("Authorization", "Bearer $bearer")
        .post(body.toString().toRequestBody(JSON_MEDIA_TYPE))
        .build()

    /** On the phone, not refused by K3 (different bytes, or verification failed past the cap). */
    private fun UploadItem.isHeldOnPhone(): Boolean = uploadState != UploadState.VERIFIED &&
        uploadState != UploadState.CONFLICT &&
        !(uploadState == UploadState.FAILED && verifyRestarts >= MAX_VERIFY_RESTARTS) &&
        File(filePath).isFile

    /** Can answer a K3 `missing` entry: on the phone, granted, and K3 has not refused these bytes. */
    private fun UploadItem.canRefill(): Boolean = uploadState != UploadState.VERIFIED &&
        uploadState != UploadState.CONFLICT &&
        uploadState != UploadState.HELD &&
        File(filePath).isFile

    private class Grant(val token: String, val ingestUrl: String, val expMs: Long) {
        fun url(path: String): String = ingestUrl(ingestUrl, path)
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
        private val master: Boolean,
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
                    throttle.acquire(read, master)
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
        private const val PART_TIMEOUT_BASE_NS = 120_000_000_000L
        private const val COPY_BUFFER_BYTES = 64 * 1024
        private const val MAX_BACKOFF_SHIFT = 16
        const val MAX_VERIFY_RESTARTS = 3
        private val JSON_MEDIA_TYPE = "application/json".toMediaType()
        private const val TAG = "CourtUploader"
    }
}

private fun ingestUrl(base: String, path: String): String = base.trimEnd('/') + path

private fun manifestUrl(base: String, sessionId: String): String = ingestUrl(base, "/v2/sessions/$sessionId/manifest")
