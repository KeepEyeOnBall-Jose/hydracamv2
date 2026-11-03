package com.amaia23.hydracam.court

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
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.TimeUnit

/** H7 against a fake C2 store (MockWebServer). */
class C2UploaderTest {
    @get:Rule
    val temp = TemporaryFolder()

    private val server = MockWebServer()
    private val http = OkHttpClient.Builder().callTimeout(5, TimeUnit.SECONDS).build()
    private val clock = FakeClock()
    private val store = InMemoryUploadQueueStore()
    private lateinit var grant: String

    @Before
    fun setUp() {
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun startSession(
        tiers: List<String> = listOf(C1.TIER_PROXY, C1.TIER_MASTER),
        expSeconds: Long = 4_000_000_000L,
    ) {
        grant = testGrant("s1", tiers, expSeconds)
        val body = recordStartBody(grant = grant, ingestUrl = server.url("/").toString())
        store.upsertSession(UploadSession.from(RecordStart.fromJson(body), "A", clock.now))
    }

    private fun uploader(partSizeBytes: Long = C2Uploader.DEFAULT_PART_SIZE_BYTES) =
        C2Uploader(http, store, clock, partSizeBytes = partSizeBytes)

    private fun segment(tier: String, seq: Long, size: Int = 25): SegmentRecord {
        val file = File(temp.root, "$tier-$seq.ts")
        file.writeBytes(ByteArray(size) { (it + seq).toByte() })
        return SegmentRecord(
            "s1", "A", tier, seq, file, file.length(), "sha-$tier-$seq",
            1_700_000_000_000L + seq * 6_000, 6_000, 180, 0, -1,
        )
    }

    private fun item(tier: String, seq: Long): UploadItem = store.item(UploadItem.keyOf("s1", tier, seq))!!

    private fun json(code: Int, body: JSONObject) =
        MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json").setBody(body.toString())

    private fun initCreated(uploadId: String, partCount: Int) =
        json(
            201,
            JSONObject()
                .put("uploadId", uploadId)
                .put(
                    "parts",
                    JSONArray((1..partCount).map { JSONObject().put("n", it).put("url", server.url("/part/$it").toString()) }),
                ),
        )

    private fun partOk(etag: String) = MockResponse().setResponseCode(200).setHeader("ETag", etag)

    private fun take(): RecordedRequest = server.takeRequest(3, TimeUnit.SECONDS)!!

    @Test
    fun uploadsVerifiesThenDeletesTheFile() {
        startSession()
        val upload = uploader()
        val record = segment(C1.TIER_PROXY, 0)
        val bytes = record.file.readBytes()
        upload.enqueue(record)
        server.enqueue(initCreated("u1", 1))
        server.enqueue(partOk("\"e1\""))
        server.enqueue(json(200, JSONObject()))

        assertTrue(upload.runOnce())

        val init = take()
        assertEquals("POST", init.method)
        assertEquals("/v2/uploads", init.path)
        assertEquals("Bearer $grant", init.getHeader("Authorization"))
        val initBody = JSONObject(init.body.readUtf8())
        assertEquals("proxy", initBody.getString("tier"))
        assertEquals(0L, initBody.getLong("seq"))
        assertEquals("sha-proxy-0", initBody.getString("sha256"))
        assertEquals(25L, initBody.getLong("bytes"))
        assertEquals("video/mp2t", initBody.getString("contentType"))
        val put = take()
        assertEquals("PUT", put.method)
        assertEquals("/part/1", put.path)
        assertNull(put.getHeader("Authorization"))
        assertArrayEquals(bytes, put.body.readByteArray())
        val complete = take()
        assertEquals("/v2/uploads/u1/complete", complete.path)
        val completeParts = JSONObject(complete.body.readUtf8()).getJSONArray("parts")
        assertEquals("\"e1\"", completeParts.getJSONObject(0).getString("etag"))
        assertEquals(UploadState.VERIFYING, item(C1.TIER_PROXY, 0).uploadState)

        // The status poll waits statusPollMs.
        assertFalse(upload.runOnce())
        clock.now += 2_000
        server.enqueue(json(200, JSONObject().put("state", "verifying")))
        assertTrue(upload.runOnce())
        assertEquals("GET", take().method)
        assertEquals(UploadState.VERIFYING, item(C1.TIER_PROXY, 0).uploadState)
        assertTrue(record.file.isFile)

        clock.now += 2_000
        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce())
        assertEquals("/v2/uploads/u1", take().path)
        assertEquals(UploadState.VERIFIED, item(C1.TIER_PROXY, 0).uploadState)
        assertFalse(record.file.exists())
        assertFalse(upload.runOnce())
    }

    @Test
    fun initAlreadyVerifiedSkipsTheUpload() {
        startSession()
        val upload = uploader()
        val record = segment(C1.TIER_PROXY, 0)
        upload.enqueue(record)
        server.enqueue(json(200, JSONObject().put("uploadId", "u0").put("state", "verified")))

        assertTrue(upload.runOnce())

        assertEquals(UploadState.VERIFIED, item(C1.TIER_PROXY, 0).uploadState)
        assertFalse(record.file.exists())
        assertEquals(1, server.requestCount)
    }

    @Test
    fun conflictKeepsTheFile() {
        startSession()
        val upload = uploader()
        val record = segment(C1.TIER_PROXY, 0)
        upload.enqueue(record)
        server.enqueue(json(409, JSONObject().put("reason", "sha256 differs")))

        assertTrue(upload.runOnce())

        val conflicted = item(C1.TIER_PROXY, 0)
        assertEquals(UploadState.CONFLICT, conflicted.uploadState)
        assertEquals("conflict: sha256 differs", conflicted.lastError)
        assertTrue(record.file.isFile)
        assertFalse(upload.runOnce())
    }

    @Test
    fun partWithoutEtagIsRetriedWithoutNewInit() {
        startSession()
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        server.enqueue(initCreated("u1", 1))
        server.enqueue(MockResponse().setResponseCode(200))

        assertTrue(upload.runOnce())

        val retrying = item(C1.TIER_PROXY, 0)
        assertEquals(UploadState.UPLOADING, retrying.uploadState)
        assertEquals("part_1_no_etag", retrying.lastError)
        assertEquals(1, retrying.attempts)
        assertEquals(clock.now + 2_000, retrying.nextAttemptAtMs)
        assertFalse(upload.runOnce())

        clock.now += 2_000
        server.enqueue(partOk("\"e1\""))
        server.enqueue(json(200, JSONObject()))
        assertTrue(upload.runOnce())

        assertEquals(UploadState.VERIFYING, item(C1.TIER_PROXY, 0).uploadState)
        assertEquals(listOf("/v2/uploads", "/part/1", "/part/1", "/v2/uploads/u1/complete"), (1..4).map { take().path })
    }

    @Test
    fun multipartResumesAfterTheLastAcceptedPart() {
        startSession()
        val upload = uploader(partSizeBytes = 10)
        val record = segment(C1.TIER_PROXY, 0, size = 25)
        val bytes = record.file.readBytes()
        upload.enqueue(record)
        server.enqueue(initCreated("u1", 3))
        server.enqueue(partOk("e1"))
        server.enqueue(MockResponse().setResponseCode(500))

        assertTrue(upload.runOnce())

        take()
        assertArrayEquals(bytes.copyOfRange(0, 10), take().body.readByteArray())
        take()
        assertEquals("part_2_http_500", item(C1.TIER_PROXY, 0).lastError)

        clock.now += 2_000
        server.enqueue(partOk("e2"))
        server.enqueue(partOk("e3"))
        server.enqueue(json(200, JSONObject()))
        assertTrue(upload.runOnce())

        val second = take()
        assertEquals("/part/2", second.path)
        assertArrayEquals(bytes.copyOfRange(10, 20), second.body.readByteArray())
        val third = take()
        assertEquals("/part/3", third.path)
        assertArrayEquals(bytes.copyOfRange(20, 25), third.body.readByteArray())
        val parts = JSONObject(take().body.readUtf8()).getJSONArray("parts")
        assertEquals(listOf("e1", "e2", "e3"), (0 until parts.length()).map { parts.getJSONObject(it).getString("etag") })
        assertEquals(UploadState.VERIFYING, item(C1.TIER_PROXY, 0).uploadState)
    }

    @Test
    fun expiredPartUrlRestartsWithFreshInit() {
        startSession()
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        server.enqueue(initCreated("u1", 1))
        server.enqueue(MockResponse().setResponseCode(403))

        assertTrue(upload.runOnce())

        val restarted = item(C1.TIER_PROXY, 0)
        assertEquals(UploadState.PENDING, restarted.uploadState)
        assertNull(restarted.uploadId)
        assertNull(restarted.partsJson)
        assertEquals("part_url_expired", restarted.lastError)
    }

    @Test
    fun ungrantedMasterIsHeld() {
        startSession(tiers = listOf(C1.TIER_PROXY))
        val upload = uploader()
        val record = segment(C1.TIER_MASTER, 0)
        upload.enqueue(record)

        assertEquals(UploadState.HELD, item(C1.TIER_MASTER, 0).uploadState)
        assertFalse(upload.runOnce())
        assertEquals(0, server.requestCount)
        assertTrue(record.file.isFile)
    }

    @Test
    fun expiredGrantFailsWithoutRequests() {
        startSession(expSeconds = clock.now / 1_000 - 1)
        val upload = uploader()
        val record = segment(C1.TIER_PROXY, 0)
        upload.enqueue(record)

        assertTrue(upload.runOnce())

        val failed = item(C1.TIER_PROXY, 0)
        assertEquals(UploadState.FAILED, failed.uploadState)
        assertEquals("grant_expired", failed.lastError)
        assertEquals(0, server.requestCount)
        assertTrue(record.file.isFile)
    }

    @Test
    fun manifestListsGrantedTiersButReportsBothLastSeqs() {
        startSession(tiers = listOf(C1.TIER_PROXY))
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        upload.enqueue(segment(C1.TIER_MASTER, 0))
        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce())
        take()
        // Not stopped yet: no manifest.
        assertFalse(upload.runOnce())

        upload.onSessionStopped("s1", lastSeqProxy = 0, lastSeqMaster = 0)
        server.enqueue(json(200, JSONObject().put("state", "complete")))
        assertTrue(upload.runOnce())

        val manifest = take()
        assertEquals("/v2/sessions/s1/manifest", manifest.path)
        assertEquals("Bearer $grant", manifest.getHeader("Authorization"))
        val body = JSONObject(manifest.body.readUtf8())
        assertEquals("A", body.getString("slot"))
        assertEquals(0L, body.getJSONObject("lastSeq").getLong("proxy"))
        assertEquals(0L, body.getJSONObject("lastSeq").getLong("master"))
        val segments = body.getJSONArray("segments")
        assertEquals(1, segments.length())
        assertEquals("proxy", segments.getJSONObject(0).getString("tier"))
        assertEquals("sha-proxy-0", segments.getJSONObject(0).getString("sha256"))
        assertEquals(UploadSession.MANIFEST_COMPLETE, store.session("s1")!!.manifestState)
        assertFalse(upload.runOnce())
    }

    @Test
    fun partialManifestRequeuesMissingSegmentsThenCompletes() {
        startSession()
        val upload = uploader()
        val record = segment(C1.TIER_PROXY, 0)
        upload.enqueue(record)
        server.enqueue(json(409, JSONObject()))
        assertTrue(upload.runOnce())
        upload.onSessionStopped("s1", lastSeqProxy = 0, lastSeqMaster = -1)

        val missing = JSONArray().put(JSONObject().put("tier", "proxy").put("seq", 0))
        server.enqueue(json(200, JSONObject().put("state", "partial").put("missing", missing)))
        assertTrue(upload.runOnce())

        assertEquals(UploadState.PENDING, item(C1.TIER_PROXY, 0).uploadState)
        assertEquals(UploadSession.MANIFEST_PARTIAL, store.session("s1")!!.manifestState)

        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce())
        assertEquals(UploadState.VERIFIED, item(C1.TIER_PROXY, 0).uploadState)
        // The manifest re-send waits for its backoff.
        assertFalse(upload.runOnce())

        clock.now += 2_000
        server.enqueue(json(200, JSONObject().put("state", "complete")))
        assertTrue(upload.runOnce())
        assertEquals(UploadSession.MANIFEST_COMPLETE, store.session("s1")!!.manifestState)
        assertEquals(4, server.requestCount)
    }

    @Test
    fun partialManifestWithNothingToRequeueStops() {
        startSession()
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce())
        upload.onSessionStopped("s1", lastSeqProxy = 0, lastSeqMaster = -1)

        val missing = JSONArray().put(JSONObject().put("tier", "proxy").put("seq", 0))
        server.enqueue(json(200, JSONObject().put("state", "partial").put("missing", missing)))
        assertTrue(upload.runOnce())

        val session = store.session("s1")!!
        assertEquals(UploadSession.MANIFEST_PARTIAL, session.manifestState)
        assertEquals(Long.MAX_VALUE, session.nextManifestAtMs)
        clock.now += 24 * 3_600_000L
        assertFalse(upload.runOnce())
        assertEquals(2, server.requestCount)
    }
}
