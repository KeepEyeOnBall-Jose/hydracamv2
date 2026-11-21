package com.amaia23.hydracam.phonecore

import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class PhoneCoreLiveSessionUploaderTest {
    @get:Rule
    val temp = TemporaryFolder()

    private val server = MockWebServer()
    private val clock = FakePhoneClock()
    private val logger = RecordingPhoneLogger()
    private val alerts = mutableListOf<String>()
    private val mastersAllowed = AtomicBoolean(true)
    private val http = OkHttpClient.Builder()
        .callTimeout(5, TimeUnit.SECONDS)
        .retryOnConnectionFailure(false)
        .build()

    @Before
    fun setUp() {
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun newUploader(partSizeBytes: Long = C2Uploader.DEFAULT_PART_SIZE_BYTES) = PhoneCoreLiveSessionUploader(
        http = http,
        clock = clock,
        logger = logger,
        partSizeBytes = partSizeBytes,
        onAlert = { alerts += it },
        mastersAllowed = mastersAllowed::get,
    )

    private fun writeSegmentFile(name: String, size: Int = 32): File = File(temp.root, name).apply {
        writeBytes(ByteArray(size) { index -> ((index * 7) and 0xFF).toByte() })
    }

    private fun json(code: Int, body: JSONObject) =
        MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json").setBody(body.toString())

    private fun initCreated(uploadId: String, partCount: Int = 1) = json(
        HttpStatus.CREATED,
        JSONObject()
            .put("uploadId", uploadId)
            .put(
                "parts",
                JSONArray(
                    (1..partCount).map {
                        JSONObject().put("n", it).put("url", server.url("/part/$it").toString())
                    },
                ),
            ),
    )

    private fun partOk(etag: String) = MockResponse().setResponseCode(HttpStatus.OK).setHeader("ETag", etag)

    private fun take(): RecordedRequest = server.takeRequest(3, TimeUnit.SECONDS)!!

    @Test
    fun initPutCompleteAndVerifyDeletesLocalFile() {
        val uploader = newUploader()
        val grant = testGrant("live-1", listOf(C1.TIER_PROXY), 4_000_000_000L)
        val session = uploader.startSession("live-1", "A", grant, server.url("/").toString(), clock.now)
        assertEquals(listOf(C1.TIER_PROXY), session.tiers)
        assertFalse(uploader.hasPendingWork())
        assertNull(uploader.nextWakeAtMs())

        val initial = uploader.snapshot("live-1")!!
        assertEquals("A", initial.slot)
        assertEquals(0, initial.totalSegments)
        assertEquals(-1L, initial.lastSeqProxy)
        assertFalse(initial.isComplete)

        val file = writeSegmentFile("proxy-0.ts", size = 48)
        val bytes = file.readBytes()
        val queued = uploader.enqueueSegment(
            sessionId = "live-1",
            slot = "A",
            tier = C1.TIER_PROXY,
            seq = 0,
            file = file,
            sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            mediaStartServerMs = clock.now,
            durationMs = 6_000,
        )
        assertEquals(UploadState.PENDING, queued.uploadState)
        assertTrue(uploader.hasPendingWork())
        assertEquals(48L, uploader.snapshot("live-1")!!.pendingBytes)

        server.enqueue(initCreated("u-live-0"))
        server.enqueue(partOk("etag-1"))
        server.enqueue(json(HttpStatus.OK, JSONObject()))
        assertTrue(uploader.drainOnce())

        val initReq = take()
        assertEquals("/v2/uploads", initReq.path)
        assertEquals("Bearer $grant", initReq.getHeader("Authorization"))
        assertEquals(C2Uploader.CONTENT_TYPE_TS, JSONObject(initReq.body.readUtf8()).getString("contentType"))
        assertArrayEquals(bytes, take().body.readByteArray())
        val completeReq = take()
        assertEquals("/v2/uploads/u-live-0/complete", completeReq.path)
        val parts = JSONObject(completeReq.body.readUtf8()).getJSONArray("parts")
        assertEquals("etag-1", parts.getJSONObject(0).getString("etag"))

        assertFalse(uploader.drainOnce())
        assertEquals(clock.now + 2_000L, uploader.nextWakeAtMs())

        clock.now += 2_000L
        server.enqueue(json(HttpStatus.OK, JSONObject().put("state", "verified")))
        assertTrue(uploader.drainOnce())
        assertEquals("/v2/uploads/u-live-0", take().path)
        assertFalse(file.exists())

        val verified = uploader.snapshot("live-1")!!
        assertEquals(1, verified.verifiedSegments)
        assertEquals(0, verified.activeSegments)
        assertEquals(0L, verified.pendingBytes)
        assertFalse(uploader.hasPendingWork())
    }

    @Test
    fun markRecordingStoppedWaitsForGrantedProxiesThenCompletesManifest() {
        val uploader = newUploader()
        val grant = testGrant("live-stop", listOf(C1.TIER_PROXY), 4_000_000_000L)
        uploader.startSession("live-stop", "A", grant, server.url("/").toString(), clock.now)

        val file = writeSegmentFile("proxy-stop.ts", size = 24)
        uploader.enqueueSegment("live-stop", "A", C1.TIER_PROXY, 0, file, "sha-stop", clock.now, 6_000)

        // Move proxy to VERIFYING, then mark stopped: manifest must wait for proxy verification.
        server.enqueue(initCreated("u-stop-0"))
        server.enqueue(partOk("etag-stop"))
        server.enqueue(json(HttpStatus.OK, JSONObject()))
        assertTrue(uploader.drainOnce())
        repeat(3) { take() }

        val stopped = uploader.markRecordingStopped("live-stop", stoppedAtMs = clock.now + 500)!!
        assertEquals(clock.now + 500, stopped.stoppedAtMs)
        assertEquals(0L, stopped.lastSeqProxy)
        assertEquals(-1L, stopped.lastSeqMaster)
        assertEquals(clock.now + 2_000L, uploader.nextWakeAtMs())
        assertFalse(uploader.drainOnce())

        clock.now += 2_000L
        server.enqueue(json(HttpStatus.OK, JSONObject().put("state", "verified")))
        assertTrue(uploader.drainOnce())
        assertEquals("/v2/uploads/u-stop-0", take().path)
        assertTrue(uploader.hasPendingWork())
        assertEquals(0L, uploader.nextWakeAtMs())

        server.enqueue(json(HttpStatus.OK, JSONObject().put("state", UploadSession.MANIFEST_COMPLETE)))
        assertTrue(uploader.drainOnce())
        val manifestReq = take()
        assertEquals("/v2/sessions/live-stop/manifest", manifestReq.path)
        assertEquals("Bearer $grant", manifestReq.getHeader("Authorization"))
        val manifestBody = JSONObject(manifestReq.body.readUtf8())
        assertEquals("A", manifestBody.getString("slot"))
        assertEquals(0L, manifestBody.getJSONObject("lastSeq").getLong(C1.TIER_PROXY))
        assertEquals(-1L, manifestBody.getJSONObject("lastSeq").getLong(C1.TIER_MASTER))
        assertEquals(1, manifestBody.getJSONArray("segments").length())

        val completeSnap = uploader.snapshot("live-stop")!!
        assertEquals(UploadSession.MANIFEST_COMPLETE, completeSnap.manifestState)
        assertTrue(completeSnap.isComplete)
        assertFalse(uploader.hasPendingWork())
        assertNull(uploader.nextWakeAtMs())
        assertFalse(uploader.drainOnce())
    }

    @Test
    fun heldMastersIdempotentEnqueueAndGrantRefreshWorkWithoutRoom() {
        val uploader = newUploader()
        val proxyOnlyGrant = testGrant("live-2", listOf(C1.TIER_PROXY), 4_000_000_000L)
        uploader.startSession("live-2", "B", proxyOnlyGrant, server.url("/").toString(), clock.now)

        val proxyFile = writeSegmentFile("p0.ts")
        val masterFile = writeSegmentFile("m0.ts")
        uploader.enqueueSegment("live-2", "B", C1.TIER_PROXY, 1, proxyFile, "sha-p1", clock.now, 6_000)
        // Re-enqueuing an earlier seq must be idempotent and must not lower lastSeq.
        uploader.enqueueSegment("live-2", "B", C1.TIER_PROXY, 1, proxyFile, "sha-p1", clock.now, 6_000)
        val masterItem = uploader.enqueueSegment(
            sessionId = "live-2",
            slot = "B",
            tier = C1.TIER_MASTER,
            seq = 0,
            file = masterFile,
            sha256 = "sha-m0",
            mediaStartServerMs = clock.now,
            durationMs = 6_000,
        )
        assertEquals(UploadState.HELD, masterItem.uploadState)

        val snap = uploader.snapshot("live-2")!!
        assertEquals(2, snap.totalSegments)
        assertEquals(1, snap.activeSegments)
        assertEquals(1, snap.heldSegments)
        assertEquals(1L, snap.lastSeqProxy)
        assertEquals(0L, snap.lastSeqMaster)

        // Refreshing the session grant keeps existing stop metadata intact.
        uploader.markRecordingStopped("live-2", clock.now + 100)
        val refreshedGrant = testGrant("live-2", listOf(C1.TIER_PROXY), 4_000_003_600L)
        val refreshed = uploader.startSession(
            sessionId = "live-2",
            slot = "B",
            uploadGrant = refreshedGrant,
            ingestUrl = server.url("/").toString(),
            nowMs = clock.now + 200,
        )
        assertEquals(clock.now + 100, refreshed.stoppedAtMs)
        assertEquals(1L, refreshed.lastSeqProxy)
        assertEquals(0L, refreshed.lastSeqMaster)

        // Shortcut 200 verified + manifest complete; held master stays on disk and does not block completion.
        server.enqueue(json(HttpStatus.OK, JSONObject().put("uploadId", "u-p1").put("state", "verified")))
        assertTrue(uploader.drainOnce())
        server.enqueue(json(HttpStatus.OK, JSONObject().put("state", UploadSession.MANIFEST_COMPLETE)))
        assertTrue(uploader.drainOnce())

        val done = uploader.snapshot("live-2")!!
        assertTrue(done.isComplete)
        assertEquals(1, done.verifiedSegments)
        assertEquals(1, done.heldSegments)
        assertTrue(masterFile.isFile)
        assertFalse(uploader.hasPendingWork())
    }

    @Test
    fun mastersGateConflictFailedAndManifestCompletionWhileMasterActive() {
        mastersAllowed.set(false)
        val uploader = newUploader()
        val dualGrant = testGrant("live-3", listOf(C1.TIER_PROXY, C1.TIER_MASTER), 1_700_001_000L)
        uploader.startSession("live-3", "A", dualGrant, server.url("/").toString(), clock.now)

        val proxyConflict = writeSegmentFile("pc.ts")
        val proxyFailed = writeSegmentFile("pf.ts")
        val masterStream = writeSegmentFile("ms.ts")
        uploader.enqueueSegment("live-3", "A", C1.TIER_PROXY, 0, proxyConflict, "sha-c", clock.now, 6_000)
        uploader.enqueueSegment("live-3", "A", C1.TIER_PROXY, 1, proxyFailed, "sha-f", clock.now, 6_000)
        uploader.enqueueSegment("live-3", "A", C1.TIER_MASTER, 0, masterStream, "sha-m", clock.now, 6_000)

        server.enqueue(json(HttpStatus.CONFLICT, JSONObject().put("reason", "sha256 differs")))
        assertTrue(uploader.drainOnce())
        server.enqueue(json(HttpStatus.UNAUTHORIZED, JSONObject()))
        assertTrue(uploader.drainOnce())
        assertEquals(1, alerts.size)

        // With mastersAllowed=false, only the master remains active so default pending work is false.
        assertFalse(uploader.hasPendingWork())
        assertTrue(uploader.hasPendingWork(includeMasters = true))
        uploader.preemptMasters()

        // Stopping triggers manifest even while master is still active; isComplete stays false until master settles.
        uploader.markRecordingStopped("live-3", clock.now + 10)
        assertTrue(uploader.hasPendingWork())
        server.enqueue(json(HttpStatus.OK, JSONObject().put("state", UploadSession.MANIFEST_COMPLETE)))
        assertTrue(uploader.drainOnce())
        assertFalse(uploader.snapshot("live-3")!!.isComplete)
        assertFalse(uploader.hasPendingWork())

        // Enabling masters allows the queued master to upload and verify.
        mastersAllowed.set(true)
        assertTrue(uploader.hasPendingWork())
        server.enqueue(json(HttpStatus.OK, JSONObject().put("uploadId", "u-m0").put("state", "verified")))
        assertTrue(uploader.drainOnce())

        val finalSnap = uploader.snapshot("live-3")!!
        assertEquals(1, finalSnap.conflictSegments)
        assertEquals(1, finalSnap.failedSegments)
        assertEquals(1, finalSnap.verifiedSegments)
        assertEquals(0, finalSnap.activeSegments)
        assertEquals(UploadSession.MANIFEST_COMPLETE, finalSnap.manifestState)
        assertTrue(finalSnap.isComplete)
        assertFalse(uploader.hasPendingWork())
    }

    @Test
    fun partialManifestSettlementExpiredGrantAndInvalidArgsAreHandledCleanly() {
        val uploader = newUploader()
        assertNull(uploader.snapshot("unknown"))
        assertNull(uploader.markRecordingStopped("unknown", clock.now))

        val shortGrant = testGrant("live-exp", listOf(C1.TIER_PROXY), (clock.now / 1_000) + 10)
        uploader.startSession("live-exp", "A", shortGrant, server.url("/").toString(), clock.now)
        uploader.markRecordingStopped("live-exp", clock.now + 1)
        assertTrue(uploader.hasPendingWork())
        server.enqueue(json(HttpStatus.OK, JSONObject().put("state", UploadSession.MANIFEST_PARTIAL)))
        assertTrue(uploader.drainOnce())
        assertFalse(uploader.hasPendingWork())

        val expGrant = testGrant("live-exp2", listOf(C1.TIER_PROXY), (clock.now / 1_000) + 5)
        uploader.startSession("live-exp2", "A", expGrant, server.url("/").toString(), clock.now)
        uploader.markRecordingStopped("live-exp2", clock.now + 1)
        assertTrue(uploader.hasPendingWork())
        clock.now += 10_000
        assertFalse(uploader.hasPendingWork())

        val file = writeSegmentFile("valid.ts")
        val missing = File(temp.root, "does-not-exist.ts")
        expectIllegalArg { uploader.startSession("../bad", "A", shortGrant, server.url("/").toString()) }
        expectIllegalArg { uploader.startSession("ok", " ", shortGrant, server.url("/").toString()) }
        expectIllegalArg { uploader.startSession("ok", "A", " ", server.url("/").toString()) }
        expectIllegalArg { uploader.startSession("ok", "A", shortGrant, "http://example.com") }
        expectIllegalArg { uploader.markRecordingStopped("live-exp", stoppedAtMs = 0) }
        expectIllegalArg { uploader.enqueueSegment("../bad", "A", C1.TIER_PROXY, 0, file, "sha", 0, 100) }
        expectIllegalArg { uploader.enqueueSegment("live-exp", "", C1.TIER_PROXY, 0, file, "sha", 0, 100) }
        expectIllegalArg { uploader.enqueueSegment("live-exp", "A", "invalid", 0, file, "sha", 0, 100) }
        expectIllegalArg { uploader.enqueueSegment("live-exp", "A", C1.TIER_PROXY, -1, file, "sha", 0, 100) }
        expectIllegalArg { uploader.enqueueSegment("live-exp", "A", C1.TIER_PROXY, 0, missing, "sha", 0, 100) }
        expectIllegalArg { uploader.enqueueSegment("live-exp", "A", C1.TIER_PROXY, 0, file, " ", 0, 100) }
        expectIllegalArg { uploader.enqueueSegment("live-exp", "A", C1.TIER_PROXY, 0, file, "sha", 0, -1) }
        assertNotNull(uploader.snapshot("live-exp"))
    }

    private fun expectIllegalArg(block: () -> Unit) {
        try {
            block()
            fail("Expected IllegalArgumentException")
        } catch (expected: IllegalArgumentException) {
            assertTrue(expected.message.orEmpty().isNotBlank())
        }
    }
}
