package com.amaia23.hydracam.phonecore

import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.SocketPolicy
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
import java.util.concurrent.atomic.AtomicBoolean

class C2UploaderTest {
    @get:Rule
    val temp = TemporaryFolder()

    private val server = MockWebServer()
    private val clock = FakePhoneClock()
    private val store = InMemoryUploadQueueStore()
    private val alerts = mutableListOf<String>()
    private val allowed = AtomicBoolean(true)
    private val logger = RecordingPhoneLogger()
    private val http = OkHttpClient.Builder()
        .callTimeout(5, TimeUnit.SECONDS)
        .retryOnConnectionFailure(false)
        .build()
    private lateinit var grant: String

    @Before
    fun startServer() {
        server.start()
    }

    @After
    fun stopServer() {
        server.shutdown()
    }

    private fun startSession(
        tiers: List<String> = listOf(C1.TIER_PROXY, C1.TIER_MASTER),
        expSeconds: Long = 4_000_000_000L,
    ) {
        grant = testGrant("s1", tiers, expSeconds)
        val body = testRecordStartBody(grant = grant, ingestUrl = server.url("/").toString())
        store.upsertSession(UploadSession.from(RecordStart.fromJson(body), "A", clock.now))
    }

    private fun uploader(
        throttle: UploadThrottle = UploadThrottle(maxKbps = 0),
        partSizeBytes: Long = C2Uploader.DEFAULT_PART_SIZE_BYTES,
        mastersAllowed: () -> Boolean = allowed::get,
    ) = C2Uploader(
        http = http,
        store = store,
        clock = clock,
        logger = logger,
        partSizeBytes = partSizeBytes,
        throttle = throttle,
        onAlert = { alerts += it },
        mastersAllowed = mastersAllowed,
    )

    private fun segment(tier: String, seq: Long, size: Int = 25): SegmentRecord {
        val file = File(temp.root, "$tier-$seq.ts")
        file.writeBytes(ByteArray(size) { (it + seq).toByte() })
        return SegmentRecord(
            "s1",
            "A",
            tier,
            seq,
            file,
            file.length(),
            "sha-$tier-$seq",
            BASE_MS + seq * 6_000,
            6_000,
            180,
            0,
            -1,
        )
    }

    private fun item(tier: String, seq: Long): UploadItem = store.item(UploadItem.keyOf("s1", tier, seq))!!

    private fun json(code: Int, body: JSONObject) =
        MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json").setBody(body.toString())

    private fun initCreated(uploadId: String, partCount: Int) = json(
        201,
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

    private fun partOk(etag: String) = MockResponse().setResponseCode(200).setHeader("ETag", etag)

    private fun take(): RecordedRequest = server.takeRequest(3, TimeUnit.SECONDS)!!

    @Test
    fun multipartUploadResumesVerifiesAndDeletesFile() {
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
        assertEquals(UploadState.UPLOADING, item(C1.TIER_PROXY, 0).uploadState)
        assertEquals("part_2_http_500", item(C1.TIER_PROXY, 0).lastError)

        clock.now += 2_000
        server.enqueue(partOk("e2"))
        server.enqueue(partOk("e3"))
        server.enqueue(json(200, JSONObject()))
        assertTrue(upload.runOnce())
        assertArrayEquals(bytes.copyOfRange(10, 20), take().body.readByteArray())
        assertArrayEquals(bytes.copyOfRange(20, 25), take().body.readByteArray())
        val completeParts = JSONObject(take().body.readUtf8()).getJSONArray("parts")
        assertEquals(listOf("e1", "e2", "e3"), (0..2).map { completeParts.getJSONObject(it).getString("etag") })
        assertEquals(UploadState.VERIFYING, item(C1.TIER_PROXY, 0).uploadState)

        assertFalse(upload.runOnce())
        clock.now += 2_000
        server.enqueue(json(200, JSONObject().put("state", "verifying")))
        assertTrue(upload.runOnce())
        take()
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
    fun initShortcutsConflictsAuthErrorsAndExpiredPartUrlsBehaveCorrectly() {
        startSession()
        val upload = uploader()

        // 200 already verified deletes local file.
        val verifiedSeg = segment(C1.TIER_PROXY, 0).also(upload::enqueue)
        server.enqueue(json(200, JSONObject().put("uploadId", "u0").put("state", "verified")))
        assertTrue(upload.runOnce())
        assertEquals(UploadState.VERIFIED, item(C1.TIER_PROXY, 0).uploadState)
        assertFalse(verifiedSeg.file.exists())

        // 409 conflict keeps file and alerts; master not-requested stays HELD without alert.
        val conflictSeg = segment(C1.TIER_PROXY, 1).also(upload::enqueue)
        server.enqueue(json(409, JSONObject().put("reason", "sha256 differs")))
        assertTrue(upload.runOnce())
        assertEquals(UploadState.CONFLICT, item(C1.TIER_PROXY, 1).uploadState)
        assertTrue(conflictSeg.file.isFile)
        assertEquals(1, alerts.size)

        val masterSeg = segment(C1.TIER_MASTER, 0).also(upload::enqueue)
        server.enqueue(json(409, JSONObject().put("reason", C2Uploader.REASON_NOT_REQUESTED)))
        assertTrue(upload.runOnce())
        assertEquals(UploadState.HELD, item(C1.TIER_MASTER, 0).uploadState)
        assertTrue(masterSeg.file.isFile)
        assertEquals(1, alerts.size)

        // 403 on PUT restarts with fresh init; 401 on init fails item permanently.
        upload.enqueue(segment(C1.TIER_PROXY, 2))
        server.enqueue(initCreated("u2", 1))
        server.enqueue(MockResponse().setResponseCode(403))
        assertTrue(upload.runOnce())
        val restarted = item(C1.TIER_PROXY, 2)
        assertEquals(UploadState.PENDING, restarted.uploadState)
        assertNull(restarted.uploadId)
        assertEquals("part_url_expired", restarted.lastError)

        clock.now += 60_000
        server.enqueue(json(401, JSONObject()))
        assertTrue(upload.runOnce())
        assertEquals(UploadState.FAILED, item(C1.TIER_PROXY, 2).uploadState)
        assertEquals("grant_rejected_401", item(C1.TIER_PROXY, 2).lastError)
    }

    @Test
    fun verifyRestartCapAndManifestRefillRespectContract() {
        startSession(tiers = listOf(C1.TIER_PROXY))
        val upload = uploader()
        val record = segment(C1.TIER_PROXY, 0).also(upload::enqueue)

        repeat(C2Uploader.MAX_VERIFY_RESTARTS + 1) { round ->
            server.enqueue(initCreated("u$round", 1))
            server.enqueue(partOk("e1"))
            server.enqueue(json(409, JSONObject().put("state", "failed").put("reason", "sha256-mismatch")))
            assertTrue(upload.runOnce())
            clock.now += 3_600_000
        }
        val capped = item(C1.TIER_PROXY, 0)
        assertEquals(UploadState.FAILED, capped.uploadState)
        assertEquals(C2Uploader.MAX_VERIFY_RESTARTS, capped.verifyRestarts)
        assertTrue(record.file.isFile)

        upload.onSessionStopped("s1", lastSeqProxy = 0, lastSeqMaster = -1)
        val missing = JSONArray().put(JSONObject().put("tier", "proxy").put("seq", 0))
        server.enqueue(json(200, JSONObject().put("state", "partial").put("missing", missing)))
        assertTrue(upload.runOnce())
        assertEquals(UploadState.PENDING, item(C1.TIER_PROXY, 0).uploadState)
        assertEquals(UploadSession.MANIFEST_PARTIAL, store.session("s1")!!.manifestState)

        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce())
        assertEquals(UploadState.VERIFIED, item(C1.TIER_PROXY, 0).uploadState)
        clock.now += 2_000
        server.enqueue(json(200, JSONObject().put("state", "complete")))
        assertTrue(upload.runOnce())
        assertEquals(UploadSession.MANIFEST_COMPLETE, store.session("s1")!!.manifestState)
    }

    @Test
    fun mastersUploadManifestPreemptionAndThrottleWorkOnJvm() {
        startSession(tiers = listOf(C1.TIER_PROXY))
        val masterGrant = testGrant("s1", listOf(C1.TIER_MASTER), 4_000_000_000L)
        lateinit var upload: C2Uploader
        var nowNs = 0L
        var sleptNs = 0L
        val throttle = UploadThrottle(maxKbps = 1_000, nanoClock = { nowNs }) {
            nowNs += it
            sleptNs += it
            if (allowed.getAndSet(false)) {
                upload.preemptMasters()
            }
        }
        upload = uploader(throttle)
        upload.enqueue(segment(C1.TIER_MASTER, 0, size = 4 * 64 * 1024))
        upload.enqueue(segment(C1.TIER_MASTER, 1, size = 25))
        assertEquals(
            1,
            upload.requestMasters(
                "cmd-1",
                MastersUpload("s1", BASE_MS, BASE_MS + 6_000, masterGrant, server.url("/m/").toString()),
            ),
        )

        server.enqueue(json(200, JSONObject().put("state", "partial")))
        assertTrue(upload.runOnce())
        assertEquals("/m/v2/sessions/s1/manifest", take().path)
        assertEquals(MasterRequest.STATE_SENT, store.masterRequest("cmd-1")!!.state)
        assertEquals(UploadState.PENDING, item(C1.TIER_MASTER, 0).uploadState)
        assertEquals(UploadState.HELD, item(C1.TIER_MASTER, 1).uploadState)

        // Network drop when proxies/masters are allowed increments attempts.
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST))
        assertTrue(upload.runOnce())
        assertEquals(1, item(C1.TIER_PROXY, 0).attempts)
        clock.now += 2_000
        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce())
        assertEquals(UploadState.VERIFIED, item(C1.TIER_PROXY, 0).uploadState)

        allowed.set(true)
        var inits = 0
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when (request.path) {
                "/m/v2/uploads" ->
                    if (++inits == 1) initCreated("u1", 1) else json(200, JSONObject().put("state", "verified"))
                "/part/1" -> partOk("e1")
                else -> json(200, JSONObject())
            }
        }

        // Preempted mid-part while recording starts: state stays UPLOADING with 0 attempts.
        assertTrue(upload.runOnce())
        assertEquals(UploadState.UPLOADING, item(C1.TIER_MASTER, 0).uploadState)
        assertEquals(0, item(C1.TIER_MASTER, 0).attempts)
        assertTrue(sleptNs > 0)

        // Idle again: resumes and verifies.
        allowed.set(true)
        throttle.maxKbps = 0
        assertTrue(upload.runOnce())
        assertEquals(UploadState.VERIFYING, item(C1.TIER_MASTER, 0).uploadState)
    }

    private companion object {
        const val BASE_MS = 1_700_000_000_000L
    }
}
