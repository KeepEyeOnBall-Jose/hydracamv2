package com.amaia23.hydracam.court

import okhttp3.Call
import okhttp3.EventListener
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.SocketPolicy
import okio.ByteString.Companion.encodeUtf8
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.Test
import java.io.File
import java.util.concurrent.TimeUnit

/** [C2Uploader] against every non-happy C2 answer: each one settles or retries the item, never loses the file. */
class C2UploaderEdgeTest : C2StoreTestBase() {
    // Every injected fault must reach the uploader, not be absorbed by an OkHttp retry.
    override val http: OkHttpClient = OkHttpClient.Builder()
        .callTimeout(5, TimeUnit.SECONDS)
        .retryOnConnectionFailure(false)
        .build()

    private fun proxy(seq: Long = 0) = item(C1.TIER_PROXY, seq)

    private fun body(code: Int, text: String) = MockResponse().setResponseCode(code).setBody(text)

    /** Runs init, one PUT and complete for proxy 0, then makes its status poll due. */
    private fun uploadToVerifying(upload: C2Uploader, record: SegmentRecord = segment(C1.TIER_PROXY, 0)) {
        upload.enqueue(record)
        server.enqueue(initCreated("u1", 1))
        server.enqueue(partOk("e1"))
        server.enqueue(json(200, JSONObject()))
        assertTrue(upload.runOnce())
        repeat(3) { take() }
        assertEquals(UploadState.VERIFYING, proxy().uploadState)
        clock.now += 2_000
    }

    /** Runs [block] with [dir] read-only, so deletes inside it fail. Skipped where permissions are not enforced. */
    private fun <T> readOnly(dir: File, block: () -> T): T {
        dir.setWritable(false)
        try {
            assumeFalse("permissions are not enforced (root)", dir.canWrite())
            return block()
        } finally {
            dir.setWritable(true)
        }
    }

    /** Unsigned JWT with exactly [payload]; for grants missing claims. */
    private fun rawGrant(payload: JSONObject): String {
        val header = JSONObject().put("alg", "none").toString().encodeUtf8().base64Url().trimEnd('=')
        return "$header.${payload.toString().encodeUtf8().base64Url().trimEnd('=')}.sig"
    }

    private fun mastersUpload(grant: String, ingestPath: String = "/m/") =
        MastersUpload("s1", null, null, grant, server.url(ingestPath).toString())

    @Test
    fun initAuthErrorsFailTheItemAndKeepTheFile() {
        startSession()
        val upload = uploader()
        val records = listOf(segment(C1.TIER_PROXY, 0), segment(C1.TIER_PROXY, 1)).onEach(upload::enqueue)
        server.enqueue(json(401, JSONObject()))
        server.enqueue(json(403, JSONObject()))

        assertTrue(upload.runOnce())
        assertTrue(upload.runOnce())

        assertEquals("grant_rejected_401", proxy(0).lastError)
        assertEquals("grant_rejected_403", proxy(1).lastError)
        assertTrue(listOf(proxy(0), proxy(1)).all { it.uploadState == UploadState.FAILED })
        assertTrue(records.all { it.file.isFile })
        assertFalse(upload.runOnce())
    }

    @Test
    fun initServerErrorRetriesWithBackoff() {
        startSession()
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        server.enqueue(json(503, JSONObject()))

        assertTrue(upload.runOnce())

        val retrying = proxy()
        assertEquals(UploadState.PENDING, retrying.uploadState)
        assertEquals("init_http_503", retrying.lastError)
        assertEquals(clock.now + 2_000, retrying.nextAttemptAtMs)
        assertFalse(upload.runOnce())
    }

    @Test
    fun malformedInitAnswersRetryAsBadResponse() {
        startSession()
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        val answers = listOf(body(201, ""), body(201, "not json"), json(201, JSONObject().put("uploadId", "u1")))

        answers.forEachIndexed { index, answer ->
            server.enqueue(answer)
            assertTrue(upload.runOnce())
            assertEquals("bad_response", proxy().lastError)
            assertEquals(index + 1, proxy().attempts)
            assertEquals(UploadState.PENDING, proxy().uploadState)
            clock.now += 60_000
        }
    }

    @Test
    fun completeNotFoundRestartsWithAFreshInit() {
        startSession()
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        server.enqueue(initCreated("u1", 1))
        server.enqueue(partOk("e1"))
        server.enqueue(json(404, JSONObject()))

        assertTrue(upload.runOnce())

        val restarted = proxy()
        assertEquals(UploadState.PENDING, restarted.uploadState)
        assertNull(restarted.uploadId)
        assertNull(restarted.etagsJson)
        assertEquals("upload_unknown", restarted.lastError)
    }

    @Test
    fun completeServerErrorRetriesTheCompleteOnly() {
        startSession()
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        server.enqueue(initCreated("u1", 1))
        server.enqueue(partOk("e1"))
        server.enqueue(json(500, JSONObject()))
        assertTrue(upload.runOnce())
        assertEquals("complete_http_500", proxy().lastError)
        assertEquals(UploadState.UPLOADING, proxy().uploadState)

        clock.now += 2_000
        server.enqueue(json(200, JSONObject()))
        assertTrue(upload.runOnce())

        // No part is PUT twice: the retry sends only the complete, with the stored ETag.
        val paths = (1..4).map { take().path }
        assertEquals(listOf("/v2/uploads", "/part/1", "/v2/uploads/u1/complete", "/v2/uploads/u1/complete"), paths)
        assertEquals(UploadState.VERIFYING, proxy().uploadState)
    }

    @Test
    fun statusErrorsRetryOrRestart() {
        startSession()
        val upload = uploader()
        uploadToVerifying(upload)

        server.enqueue(json(503, JSONObject()))
        assertTrue(upload.runOnce())
        assertEquals(UploadState.VERIFYING, proxy().uploadState)
        assertEquals("status_http_503", proxy().lastError)

        clock.now += 60_000
        server.enqueue(json(404, JSONObject()))
        assertTrue(upload.runOnce())
        assertEquals(UploadState.PENDING, proxy().uploadState)
        assertEquals("upload_unknown", proxy().lastError)
    }

    @Test
    fun failedVerificationRestartsAndKeepsTheFile() {
        startSession()
        val upload = uploader()
        val record = segment(C1.TIER_PROXY, 0)
        uploadToVerifying(upload, record)

        server.enqueue(json(200, JSONObject().put("state", "failed").put("reason", "sha256 mismatch")))
        assertTrue(upload.runOnce())
        assertEquals("verify_failed: sha256 mismatch", proxy().lastError)
        assertEquals(UploadState.PENDING, proxy().uploadState)
        assertTrue(record.file.isFile)

        clock.now += 60_000
        server.enqueue(initCreated("u2", 1))
        server.enqueue(partOk("e1"))
        server.enqueue(json(200, JSONObject()))
        assertTrue(upload.runOnce())
        clock.now += 2_000
        server.enqueue(json(200, JSONObject().put("state", "failed")))
        assertTrue(upload.runOnce())
        assertEquals("verify_failed: unknown", proxy().lastError)
        assertTrue(record.file.isFile)
    }

    @Test
    fun verifyingItemWhoseFileVanishedStillVerifies() {
        startSession()
        val upload = uploader()
        val record = segment(C1.TIER_PROXY, 0)
        uploadToVerifying(upload, record)
        assertTrue(record.file.delete())

        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce())

        assertEquals(UploadState.VERIFIED, proxy().uploadState)
    }

    @Test
    fun pendingItemWhoseFileVanishedFailsWithoutRequests() {
        startSession()
        val upload = uploader()
        val record = segment(C1.TIER_PROXY, 0)
        upload.enqueue(record)
        assertTrue(record.file.delete())

        assertTrue(upload.runOnce())

        assertEquals(UploadState.FAILED, proxy().uploadState)
        assertEquals("file_missing", proxy().lastError)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun itemWithoutASessionFailsAndUnknownStopsAreIgnored() {
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        upload.onSessionStopped("s1", lastSeqProxy = 0, lastSeqMaster = -1)
        upload.preemptMasters()

        assertTrue(upload.runOnce())

        assertNull(store.session("s1"))
        assertEquals(UploadState.FAILED, proxy().uploadState)
        assertEquals("no_grant", proxy().lastError)
    }

    @Test
    fun masterQueuedBeforeAProxyOnlySessionIsHeld() {
        val upload = uploader()
        val record = segment(C1.TIER_MASTER, 0)
        upload.enqueue(record)
        startSession(tiers = listOf(C1.TIER_PROXY))

        assertTrue(upload.runOnce())

        assertEquals(UploadState.HELD, item(C1.TIER_MASTER, 0).uploadState)
        assertNull(item(C1.TIER_MASTER, 0).lastError)
        assertTrue(record.file.isFile)
    }

    @Test
    fun undeletableVerifiedFileIsReportedAndStillVerified() {
        startSession()
        val upload = uploader()
        val dir = temp.newFolder("ro")
        val record = segment(C1.TIER_PROXY, 0, dir = dir)
        upload.enqueue(record)
        server.enqueue(json(200, JSONObject().put("state", "verified")))

        readOnly(dir) { assertTrue(upload.runOnce()) }

        assertEquals(UploadState.VERIFIED, proxy().uploadState)
        assertTrue(record.file.isFile)
        assertTrue(logger.warnings.any { it.contains("could not delete") })
    }

    @Test
    fun fileTruncatedDuringAPartRetriesThenReportsTheRangeGone() {
        startSession()
        val record = segment(C1.TIER_PROXY, 0)
        val truncating = http.newBuilder().eventListener(
            object : EventListener() {
                override fun requestBodyStart(call: Call) {
                    if (call.request().method == "PUT") {
                        record.file.writeBytes(ByteArray(0))
                    }
                }
            },
        ).build()
        val upload = C2Uploader(truncating, store, clock, logger = logger)
        upload.enqueue(record)
        server.enqueue(initCreated("u1", 1))

        assertTrue(upload.runOnce())
        assertEquals("proxy-0.ts shrank during upload.", proxy().lastError)
        assertEquals(UploadState.UPLOADING, proxy().uploadState)

        clock.now += 60_000
        assertTrue(upload.runOnce())
        assertEquals("part_1_out_of_range", proxy().lastError)
        assertEquals(2, proxy().attempts)
    }

    @Test
    fun connectionDropOnTheFirstPutResumesWithoutANewInit() {
        startSession()
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        server.enqueue(initCreated("u1", 1))
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_DURING_REQUEST_BODY))

        assertTrue(upload.runOnce())

        val dropped = proxy()
        assertEquals(UploadState.UPLOADING, dropped.uploadState)
        assertEquals("u1", dropped.uploadId)
        assertEquals(1, dropped.attempts)

        clock.now += 2_000
        server.enqueue(partOk("e1"))
        server.enqueue(json(200, JSONObject()))
        assertTrue(upload.runOnce())
        assertEquals(UploadState.VERIFYING, proxy().uploadState)
        assertEquals(1, (1..server.requestCount).count { take().path == "/v2/uploads" })
    }

    @Test
    fun masterNetworkErrorWhileAllowedRetries() {
        startSession()
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_MASTER, 0))
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST))

        assertTrue(upload.runOnce())

        val master = item(C1.TIER_MASTER, 0)
        assertEquals(UploadState.PENDING, master.uploadState)
        assertEquals(1, master.attempts)
        assertTrue(master.lastError != null)
    }

    @Test
    fun manifestFailuresBackOffUntilAnAnswerSettlesIt() {
        startSession()
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce())
        upload.onSessionStopped("s1", lastSeqProxy = 0, lastSeqMaster = -1)
        val failures = listOf(
            json(500, JSONObject()),
            MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST),
            body(200, "not json"),
        )

        failures.forEachIndexed { index, failure ->
            server.enqueue(failure)
            assertTrue(upload.runOnce())
            val session = store.session("s1")!!
            assertNull(session.manifestState)
            assertEquals(index + 1, session.manifestAttempts)
            assertFalse(upload.runOnce())
            clock.now = session.nextManifestAtMs
        }
        assertTrue(logger.warnings.any { it.endsWith("manifest_http_500") })
        assertTrue(logger.warnings.any { it.endsWith("manifest_bad_response") })

        // A partial answer without a `missing` list has nothing to re-queue: stop.
        server.enqueue(json(200, JSONObject().put("state", "partial")))
        assertTrue(upload.runOnce())
        assertEquals(UploadSession.MANIFEST_PARTIAL, store.session("s1")!!.manifestState)
        assertEquals(Long.MAX_VALUE, store.session("s1")!!.nextManifestAtMs)
    }

    @Test
    fun manifestIsNotSentOnceTheGrantExpired() {
        startSession(expSeconds = (clock.now + 10_000) / 1_000)
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce())
        upload.onSessionStopped("s1", lastSeqProxy = 0, lastSeqMaster = -1)

        clock.now += 20_000

        assertFalse(upload.runOnce())
        assertEquals(1, server.requestCount)
    }

    @Test
    fun manifestListsFailedSegmentsOnlyWhileTheirFileExists() {
        startSession()
        val upload = uploader()
        val records = (0L..2L).map { segment(C1.TIER_PROXY, it).also(upload::enqueue) }
        server.enqueue(json(200, JSONObject().put("state", "verified")))
        server.enqueue(json(401, JSONObject()))
        assertTrue(upload.runOnce())
        assertTrue(upload.runOnce())
        assertTrue(records[2].file.delete())
        assertTrue(upload.runOnce())
        assertEquals("file_missing", proxy(2).lastError)
        upload.onSessionStopped("s1", lastSeqProxy = 2, lastSeqMaster = -1)

        server.enqueue(json(200, JSONObject().put("state", "complete")))
        assertTrue(upload.runOnce())

        take()
        take()
        val segments = JSONObject(take().body.readUtf8()).getJSONArray("segments")
        assertEquals(listOf(0L, 1L), (0 until segments.length()).map { segments.getJSONObject(it).getLong("seq") })
    }

    @Test
    fun partialManifestSkipsUnknownGoneAndHeldSegments() {
        startSession(tiers = listOf(C1.TIER_PROXY))
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        upload.enqueue(segment(C1.TIER_MASTER, 0))
        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce())
        upload.onSessionStopped("s1", lastSeqProxy = 0, lastSeqMaster = 0)
        val missing = JSONArray()
            .put(JSONObject().put("tier", "proxy").put("seq", 0))
            .put(JSONObject().put("tier", "proxy").put("seq", 7))
            .put(JSONObject().put("tier", "master").put("seq", 0))

        server.enqueue(json(200, JSONObject().put("state", "partial").put("missing", missing)))
        assertTrue(upload.runOnce())

        assertEquals(Long.MAX_VALUE, store.session("s1")!!.nextManifestAtMs)
        assertEquals(UploadState.HELD, item(C1.TIER_MASTER, 0).uploadState)
        assertEquals(2, logger.warnings.count { it.contains("missing but the file is gone") })
    }

    @Test
    fun masterGrantWithoutItsOwnIngestUrlUsesTheSessionUrl() {
        startSession(tiers = listOf(C1.TIER_PROXY))
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_MASTER, 0))
        val masterGrant = testGrant("s1", listOf(C1.TIER_MASTER), 4_000_000_000L)
        val session = store.session("s1")!!
        store.upsertSession(session.copy(masterGrant = masterGrant, masterGrantExpMs = Long.MAX_VALUE))
        store.update(item(C1.TIER_MASTER, 0).copy(state = UploadState.PENDING.name))
        server.enqueue(json(200, JSONObject().put("state", "verified")))

        assertTrue(upload.runOnce())

        val init = take()
        assertEquals("/v2/uploads", init.path)
        assertEquals("Bearer $masterGrant", init.getHeader("Authorization"))
        assertEquals(UploadState.VERIFIED, item(C1.TIER_MASTER, 0).uploadState)
    }

    @Test
    fun grantsWithoutClaimsNeverExpireLocally() {
        startSession(tiers = listOf(C1.TIER_PROXY))
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_MASTER, 0))
        val bare = rawGrant(JSONObject().put("aud", "court-ingest").put("exp", 0))

        assertEquals(1, upload.requestMasters("cmd-1", mastersUpload("not-a-jwt")))
        assertEquals(1, upload.requestMasters("cmd-2", mastersUpload(bare)))

        assertEquals(Long.MAX_VALUE, store.masterRequest("cmd-1")!!.grantExpMs)
        assertEquals(Long.MAX_VALUE, store.masterRequest("cmd-2")!!.grantExpMs)
    }

    @Test
    fun grantForAnotherSlotIsRejected() {
        startSession(tiers = listOf(C1.TIER_PROXY))
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_MASTER, 0))
        val otherSlot = rawGrant(JSONObject().put("sid", "s1").put("slot", "B").put("tiers", JSONArray().put("master")))

        val error = assertThrows(C1ProtocolException::class.java) {
            upload.requestMasters("cmd-1", mastersUpload(otherSlot))
        }

        assertEquals("uploadGrant is for slot B, not A.", error.message)
        assertNull(store.masterRequest("cmd-1"))
    }

    @Test
    fun laterMastersUploadWithAShorterGrantKeepsTheLongerOne() {
        startSession(tiers = listOf(C1.TIER_PROXY))
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_MASTER, 0))
        val longGrant = testGrant("s1", listOf(C1.TIER_MASTER), 4_000_000_000L)
        val shortGrant = testGrant("s1", listOf(C1.TIER_MASTER), 3_000_000_000L)
        upload.requestMasters("cmd-1", mastersUpload(longGrant))
        server.enqueue(json(200, JSONObject()))
        assertTrue(upload.runOnce())

        upload.requestMasters("cmd-2", mastersUpload(shortGrant))
        server.enqueue(json(200, JSONObject()))
        assertTrue(upload.runOnce())

        assertEquals(longGrant, store.session("s1")!!.masterGrant)
        assertEquals(MasterRequest.STATE_SENT, store.masterRequest("cmd-2")!!.state)
        // The master was already PENDING under cmd-1; cmd-2 does not reset it.
        assertTrue(logger.infos.any { it.endsWith("accepted; queued 0 master(s).") })
    }

    @Test
    fun mastersUploadForASessionWithoutARecordStartRowCreatesOne() {
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_MASTER, 0))
        val masterGrant = testGrant("s1", listOf(C1.TIER_MASTER), 4_000_000_000L)

        assertEquals(1, upload.requestMasters("cmd-1", mastersUpload(masterGrant)))
        server.enqueue(json(200, JSONObject()))
        assertTrue(upload.runOnce())
        assertEquals("/m/v2/sessions/s1/manifest", take().path)

        val session = store.session("s1")!!
        assertEquals(masterGrant, session.masterGrant)
        assertTrue(session.tiers.isEmpty())
        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce())
        assertEquals("/m/v2/uploads", take().path)
        assertEquals(UploadState.VERIFIED, item(C1.TIER_MASTER, 0).uploadState)
    }

    @Test
    fun pruneKeepsUndeletableMastersAndSkipsGoneOnes() {
        startSession(tiers = listOf(C1.TIER_PROXY))
        val upload = uploader()
        val dir = temp.newFolder("ro")
        upload.enqueue(segment(C1.TIER_MASTER, 0, dir = dir))
        val gone = segment(C1.TIER_MASTER, 1).also(upload::enqueue)
        assertTrue(gone.file.delete())
        clock.now += 3 * 24 * 3_600_000L

        val pruned = readOnly(dir) { upload.pruneMasters(keepDays = 1) }

        assertEquals(0, pruned)
        assertEquals(listOf("Could not delete expired master s1/master/0."), logger.warnings)
        assertEquals(UploadState.HELD, item(C1.TIER_MASTER, 0).uploadState)
        assertEquals(UploadState.HELD, item(C1.TIER_MASTER, 1).uploadState)
    }
}
