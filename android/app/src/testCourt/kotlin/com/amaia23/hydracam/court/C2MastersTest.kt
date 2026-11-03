package com.amaia23.hydracam.court

import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.SocketPolicy
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

/** 1.4 `masters.upload`, 1.6 `not-requested`, R10 throttle and keepDays against a fake C2 store. */
class C2MastersTest {
    @get:Rule
    val temp = TemporaryFolder()

    private val server = MockWebServer()
    private val http = OkHttpClient.Builder().callTimeout(5, TimeUnit.SECONDS).build()
    private val clock = FakeClock()
    private val store = InMemoryUploadQueueStore()
    private val alerts = mutableListOf<String>()
    private val masterGrant = testGrant("s1", listOf(C1.TIER_MASTER), 4_000_000_000L)

    @Before
    fun setUp() {
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun startSession(tiers: List<String> = listOf(C1.TIER_PROXY)) {
        val grant = testGrant("s1", tiers, 4_000_000_000L)
        val body = recordStartBody(grant = grant, ingestUrl = server.url("/").toString())
        store.upsertSession(UploadSession.from(RecordStart.fromJson(body), "A", clock.now))
    }

    private val allowed = AtomicBoolean(true)

    private fun uploader(
        throttle: UploadThrottle = UploadThrottle(maxKbps = 0),
        partSizeBytes: Long = C2Uploader.DEFAULT_PART_SIZE_BYTES,
        mastersAllowed: () -> Boolean = allowed::get,
    ) = C2Uploader(
        http,
        store,
        clock,
        partSizeBytes = partSizeBytes,
        throttle = throttle,
        onAlert = { alerts += it },
        mastersAllowed = mastersAllowed,
    )

    private fun parts(count: Int): JSONObject {
        val parts = JSONArray()
        for (n in 1..count) {
            parts.put(JSONObject().put("n", n).put("url", server.url("/part/$n").toString()))
        }
        return JSONObject().put("uploadId", "u1").put("parts", parts)
    }

    private fun segment(tier: String, seq: Long, size: Int = 25): SegmentRecord {
        val file = File(temp.root, "$tier-$seq.ts")
        file.writeBytes(ByteArray(size) { (it + seq).toByte() })
        return SegmentRecord(
            "s1", "A", tier, seq, file, file.length(), "sha-$tier-$seq",
            BASE_MS + seq * 6_000, 6_000, 180, 0, -1,
        )
    }

    private fun item(tier: String, seq: Long): UploadItem = store.item(UploadItem.keyOf("s1", tier, seq))!!

    private fun request(fromServerMs: Long? = null, toServerMs: Long? = null, grant: String = masterGrant) =
        MastersUpload("s1", fromServerMs, toServerMs, grant, server.url("/m/").toString())

    private fun json(code: Int, body: JSONObject) =
        MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json").setBody(body.toString())

    private fun take(): RecordedRequest = server.takeRequest(3, TimeUnit.SECONDS)!!

    private fun enqueueMasters(upload: C2Uploader, count: Int) =
        (0 until count).map { segment(C1.TIER_MASTER, it.toLong()).also(upload::enqueue) }

    private fun expectProtocolError(block: () -> Unit) {
        try {
            block()
            fail("Expected C1ProtocolException")
        } catch (expected: C1ProtocolException) {
            // expected
        }
    }

    @Test
    fun nothingHeldReturnsZeroAndStoresNothing() {
        startSession()
        val upload = uploader()

        assertEquals(0, upload.requestMasters("cmd-1", request()))

        assertNull(store.masterRequest("cmd-1"))
        assertFalse(upload.runOnce())
        assertEquals(0, server.requestCount)
    }

    @Test
    fun rangeListsOverlappingHeldMastersThenUploadsWithTheCommandGrant() {
        startSession()
        val upload = uploader()
        enqueueMasters(upload, 3)

        // seq 0 overlaps the range start, seq 1 is inside, seq 2 starts at the exclusive end.
        assertEquals(2, upload.requestMasters("cmd-1", request(BASE_MS + 5_000, BASE_MS + 12_000)))

        server.enqueue(json(200, JSONObject().put("state", "partial")))
        assertTrue(upload.runOnce())
        val manifest = take()
        assertEquals("/m/v2/sessions/s1/manifest", manifest.path)
        assertEquals("Bearer $masterGrant", manifest.getHeader("Authorization"))
        val body = JSONObject(manifest.body.readUtf8())
        assertEquals("A", body.getString("slot"))
        assertEquals("master", body.getString("tier"))
        val segments = body.getJSONArray("segments")
        assertEquals(listOf(0L, 1L), (0 until segments.length()).map { segments.getJSONObject(it).getLong("seq") })
        assertEquals("sha-master-1", segments.getJSONObject(1).getString("sha256"))
        assertEquals(MasterRequest.STATE_SENT, store.masterRequest("cmd-1")!!.state)
        assertEquals(UploadState.PENDING, item(C1.TIER_MASTER, 0).uploadState)
        assertEquals(UploadState.PENDING, item(C1.TIER_MASTER, 1).uploadState)
        assertEquals(UploadState.HELD, item(C1.TIER_MASTER, 2).uploadState)

        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce())
        val init = take()
        assertEquals("/m/v2/uploads", init.path)
        assertEquals("Bearer $masterGrant", init.getHeader("Authorization"))
        assertEquals(UploadState.VERIFIED, item(C1.TIER_MASTER, 0).uploadState)
        assertTrue(alerts.isEmpty())
    }

    @Test
    fun repeatedCommandIdIsIdempotent() {
        startSession()
        val upload = uploader()
        enqueueMasters(upload, 2)

        assertEquals(2, upload.requestMasters("cmd-1", request()))
        assertEquals(2, upload.requestMasters("cmd-1", request()))

        server.enqueue(json(200, JSONObject()))
        assertTrue(upload.runOnce())
        take()
        assertEquals(2, upload.requestMasters("cmd-1", request()))
        assertEquals(MasterRequest.STATE_SENT, store.masterRequest("cmd-1")!!.state)
    }

    @Test
    fun verifiedAndConflictedMastersAreNotListed() {
        startSession()
        val upload = uploader()
        enqueueMasters(upload, 3)
        store.update(item(C1.TIER_MASTER, 0).copy(state = UploadState.VERIFIED.name))
        store.update(item(C1.TIER_MASTER, 1).copy(state = UploadState.CONFLICT.name))

        assertEquals(1, upload.requestMasters("cmd-1", request()))
    }

    @Test
    fun grantThatCannotCoverTheRequestIsRejected() {
        startSession()
        val upload = uploader()
        enqueueMasters(upload, 1)

        expectProtocolError {
            upload.requestMasters("cmd-1", request(grant = testGrant("s1", listOf(C1.TIER_PROXY), 4_000_000_000L)))
        }
        expectProtocolError {
            upload.requestMasters("cmd-2", request(grant = testGrant("s2", listOf(C1.TIER_MASTER), 4_000_000_000L)))
        }
        expectProtocolError {
            upload.requestMasters(
                "cmd-3",
                request(grant = testGrant("s1", listOf(C1.TIER_MASTER), clock.now / 1_000 - 1)),
            )
        }
        assertNull(store.masterRequest("cmd-1"))
    }

    @Test
    fun emptyMasterManifestIsNeverSent() {
        startSession()
        val upload = uploader()
        val records = enqueueMasters(upload, 1)
        assertEquals(1, upload.requestMasters("cmd-1", request()))
        records.single().file.delete()

        assertTrue(upload.runOnce())

        assertEquals(0, server.requestCount)
        assertEquals(MasterRequest.STATE_GONE, store.masterRequest("cmd-1")!!.state)
        assertEquals(1, alerts.size)
        assertFalse(upload.runOnce())
    }

    @Test
    fun rejectedMasterManifestAlertsWithoutRetry() {
        startSession()
        val upload = uploader()
        enqueueMasters(upload, 1)
        upload.requestMasters("cmd-1", request())
        server.enqueue(json(403, JSONObject().put("error", "grant lacks master")))

        assertTrue(upload.runOnce())

        val rejected = store.masterRequest("cmd-1")!!
        assertEquals(MasterRequest.STATE_REJECTED, rejected.state)
        assertEquals("master_manifest_http_403", rejected.lastError)
        assertTrue(alerts.single().contains("403"))
        assertEquals(UploadState.HELD, item(C1.TIER_MASTER, 0).uploadState)
        clock.now += 24 * 3_600_000L
        assertFalse(upload.runOnce())
        assertEquals(1, server.requestCount)
    }

    @Test
    fun masterManifestServerErrorRetriesWithBackoff() {
        startSession()
        val upload = uploader()
        enqueueMasters(upload, 1)
        upload.requestMasters("cmd-1", request())
        server.enqueue(MockResponse().setResponseCode(503))

        assertTrue(upload.runOnce())
        take()
        val waiting = store.masterRequest("cmd-1")!!
        assertEquals(MasterRequest.STATE_PENDING, waiting.state)
        assertEquals(clock.now + 2_000, waiting.nextAttemptAtMs)
        assertFalse(upload.runOnce())

        clock.now += 2_000
        server.enqueue(json(200, JSONObject()))
        assertTrue(upload.runOnce())
        take()
        assertEquals(MasterRequest.STATE_SENT, store.masterRequest("cmd-1")!!.state)
        assertTrue(alerts.isEmpty())
    }

    @Test
    fun expiredRequestGrantIsRejectedBeforeAnyRequest() {
        startSession()
        val upload = uploader()
        enqueueMasters(upload, 1)
        upload.requestMasters("cmd-1", request(grant = testGrant("s1", listOf(C1.TIER_MASTER), clock.now / 1_000 + 1)))
        clock.now += 2_000

        assertTrue(upload.runOnce())

        assertEquals(MasterRequest.STATE_REJECTED, store.masterRequest("cmd-1")!!.state)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun notRequestedInitKeepsTheMasterHeldWithoutAlert() {
        startSession(tiers = listOf(C1.TIER_PROXY, C1.TIER_MASTER))
        val upload = uploader()
        val record = segment(C1.TIER_MASTER, 0)
        upload.enqueue(record)
        server.enqueue(json(409, JSONObject().put("reason", "not-requested")))

        assertTrue(upload.runOnce())

        val held = item(C1.TIER_MASTER, 0)
        assertEquals(UploadState.HELD, held.uploadState)
        assertNull(held.lastError)
        assertTrue(record.file.isFile)
        assertTrue(alerts.isEmpty())
        clock.now += 24 * 3_600_000L
        assertFalse(upload.runOnce())
        assertEquals(1, server.requestCount)
    }

    @Test
    fun conflictRaisesAnAlert() {
        startSession()
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        server.enqueue(json(409, JSONObject().put("reason", "sha256 differs")))

        assertTrue(upload.runOnce())

        assertEquals(UploadState.CONFLICT, item(C1.TIER_PROXY, 0).uploadState)
        assertTrue(alerts.single().contains("sha256 differs"))
    }

    @Test
    fun mastersWaitWhileRecording() {
        startSession(tiers = listOf(C1.TIER_PROXY, C1.TIER_MASTER))
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_MASTER, 0))
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        server.enqueue(json(200, JSONObject().put("state", "verified")))

        assertTrue(upload.runOnce(includeMasters = false))
        assertEquals(UploadState.VERIFIED, item(C1.TIER_PROXY, 0).uploadState)
        assertFalse(upload.runOnce(includeMasters = false))
        assertEquals(null, store.nextWakeAtMs(includeMasters = false))

        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce(includeMasters = true))
        assertEquals(UploadState.VERIFIED, item(C1.TIER_MASTER, 0).uploadState)
    }

    @Test
    fun sessionManifestDoesNotWaitForRequestedMasters() {
        startSession()
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        enqueueMasters(upload, 1)
        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce())
        take()
        upload.requestMasters("cmd-1", request())
        server.enqueue(json(200, JSONObject()))
        assertTrue(upload.runOnce())
        take()
        assertEquals(UploadState.PENDING, item(C1.TIER_MASTER, 0).uploadState)
        upload.onSessionStopped("s1", lastSeqProxy = 0, lastSeqMaster = 0)

        server.enqueue(json(200, JSONObject().put("state", "complete")))
        assertTrue(upload.runOnce(includeMasters = false))

        val manifest = take()
        assertEquals("/v2/sessions/s1/manifest", manifest.path)
        val segments = JSONObject(manifest.body.readUtf8()).getJSONArray("segments")
        assertEquals(1, segments.length())
        assertEquals("proxy", segments.getJSONObject(0).getString("tier"))
        assertEquals(UploadState.PENDING, item(C1.TIER_MASTER, 0).uploadState)
    }

    @Test
    fun pruneDeletesOnlyIdleMastersOlderThanKeepDays() {
        startSession()
        val upload = uploader()
        val old = segment(C1.TIER_MASTER, 0).also(upload::enqueue)
        val proxy = segment(C1.TIER_PROXY, 0).also(upload::enqueue)
        clock.now += 6 * DAY_MS
        val young = segment(C1.TIER_MASTER, 1).also(upload::enqueue)
        clock.now += 2 * DAY_MS

        assertEquals(1, upload.pruneMasters(keepDays = 7))

        assertFalse(old.file.exists())
        val pruned = item(C1.TIER_MASTER, 0)
        assertEquals(UploadState.FAILED, pruned.uploadState)
        assertEquals(C2Uploader.KEEP_DAYS_EXPIRED, pruned.lastError)
        assertTrue(young.file.isFile)
        assertTrue(proxy.file.isFile)
        assertEquals(0, upload.pruneMasters(keepDays = 7))
    }

    @Test
    fun partBytesGoThroughTheThrottle() {
        startSession()
        var nowNs = 0L
        var sleptNs = 0L
        val throttle = UploadThrottle(maxKbps = 1_000, nanoClock = { nowNs }, sleeper = {
            nowNs += it
            sleptNs += it
        })
        val upload = uploader(throttle)
        val size = 4 * 64 * 1024
        upload.enqueue(segment(C1.TIER_PROXY, 0, size = size))
        server.enqueue(
            json(
                201,
                JSONObject().put("uploadId", "u1")
                    .put(
                        "parts",
                        JSONArray().put(JSONObject().put("n", 1).put("url", server.url("/part/1").toString())),
                    ),
            ),
        )
        server.enqueue(MockResponse().setResponseCode(200).setHeader("ETag", "e1"))
        server.enqueue(json(200, JSONObject()))

        assertTrue(upload.runOnce())

        // The first 64 KiB chunk goes at once; the other three wait for their slots.
        assertEquals(throttle.expectedNanos(3 * 64 * 1024L), sleptNs)
        assertEquals(UploadState.VERIFYING, item(C1.TIER_PROXY, 0).uploadState)
    }

    @Test
    fun recordingPreemptsAMasterPartInFlightThenItResumes() {
        startSession(tiers = listOf(C1.TIER_PROXY, C1.TIER_MASTER))
        lateinit var upload: C2Uploader
        var nowNs = 0L
        // The second 64 KiB chunk waits for its slot: a record.start lands mid-part.
        val throttle = UploadThrottle(maxKbps = 1_000, nanoClock = { nowNs }) {
            nowNs += it
            if (allowed.getAndSet(false)) {
                upload.preemptMasters()
            }
        }
        upload = uploader(throttle)
        upload.enqueue(segment(C1.TIER_MASTER, 0, size = 4 * 64 * 1024))
        var inits = 0
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when (request.path) {
                "/v2/uploads" ->
                    if (++inits == 1) json(201, parts(1)) else json(200, JSONObject().put("state", "verified"))
                "/part/1" -> MockResponse().setResponseCode(200).setHeader("ETag", "e1")
                else -> json(200, JSONObject())
            }
        }

        assertTrue(upload.runOnce())

        val paused = item(C1.TIER_MASTER, 0)
        assertEquals(UploadState.UPLOADING, paused.uploadState)
        assertEquals(0, paused.attempts)
        assertNull(paused.lastError)
        assertEquals("{}", paused.etagsJson)

        // While recording the proxy goes next and the master waits.
        throttle.maxKbps = 0
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        assertTrue(upload.runOnce())
        assertEquals(UploadState.VERIFIED, item(C1.TIER_PROXY, 0).uploadState)
        assertFalse(upload.runOnce())

        // Idle again: the same uploadId resumes from its stored part list, with no second init.
        allowed.set(true)
        assertTrue(upload.runOnce())
        val resumed = item(C1.TIER_MASTER, 0)
        assertEquals(UploadState.VERIFYING, resumed.uploadState)
        assertEquals("u1", resumed.uploadId)
        assertEquals("e1", JSONObject(resumed.etagsJson!!).getString("1"))
        assertEquals(2, inits)
    }

    @Test
    fun masterPausesBetweenPartsWhenRecordingStarts() {
        startSession(tiers = listOf(C1.TIER_PROXY, C1.TIER_MASTER))
        val upload = uploader(partSizeBytes = 10)
        upload.enqueue(segment(C1.TIER_MASTER, 0, size = 25))
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = if (request.path == "/v2/uploads") {
                json(201, parts(3))
            } else {
                // record.start lands while part 1 is answered.
                allowed.set(false)
                MockResponse().setResponseCode(200).setHeader("ETag", "e1")
            }
        }

        assertTrue(upload.runOnce())

        val paused = item(C1.TIER_MASTER, 0)
        assertEquals(UploadState.UPLOADING, paused.uploadState)
        assertEquals("e1", JSONObject(paused.etagsJson!!).getString("1"))
        assertEquals(0, paused.attempts)
        assertEquals(2, server.requestCount)
    }

    @Test
    fun gateIsRecheckedWhenAMasterPartIsRegistered() {
        startSession(tiers = listOf(C1.TIER_PROXY, C1.TIER_MASTER))
        // Open for the pick and the per-part check, closed by the time the PUT is registered.
        var checks = 0
        val upload = uploader(mastersAllowed = { ++checks <= 2 })
        upload.enqueue(segment(C1.TIER_MASTER, 0))
        server.enqueue(json(201, parts(1)))

        assertTrue(upload.runOnce())

        assertEquals(1, server.requestCount)
        assertEquals(0, item(C1.TIER_MASTER, 0).attempts)
        assertEquals(UploadState.UPLOADING, item(C1.TIER_MASTER, 0).uploadState)
    }

    @Test
    fun droppedPartIsAFailureUnlessMastersArePaused() {
        startSession(tiers = listOf(C1.TIER_PROXY, C1.TIER_MASTER))
        val upload = uploader()
        upload.enqueue(segment(C1.TIER_MASTER, 0))
        server.enqueue(json(201, parts(1)))
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START))

        assertTrue(upload.runOnce())
        assertEquals(1, item(C1.TIER_MASTER, 0).attempts)

        // While recording a proxy drop still counts: only masters are paused.
        allowed.set(false)
        upload.enqueue(segment(C1.TIER_PROXY, 0))
        server.enqueue(json(201, parts(1)))
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START))

        assertTrue(upload.runOnce())
        val proxy = item(C1.TIER_PROXY, 0)
        assertEquals(1, proxy.attempts)
        assertTrue(proxy.lastError != null)
    }

    private companion object {
        const val BASE_MS = 1_700_000_000_000L
        const val DAY_MS = 24 * 3_600_000L
    }
}
