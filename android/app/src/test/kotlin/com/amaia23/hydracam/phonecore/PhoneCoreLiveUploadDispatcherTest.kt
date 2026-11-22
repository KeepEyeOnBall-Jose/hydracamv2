package com.amaia23.hydracam.phonecore

import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
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

class PhoneCoreLiveUploadDispatcherTest {
    @get:Rule
    val temp = TemporaryFolder()

    private val server = MockWebServer()
    private val clock = FakePhoneClock()
    private val logger = RecordingPhoneLogger()
    private val http = OkHttpClient.Builder()
        .callTimeout(5, TimeUnit.SECONDS)
        .retryOnConnectionFailure(false)
        .build()

    private lateinit var uploader: PhoneCoreLiveSessionUploader
    private lateinit var dispatcher: PhoneCoreLiveUploadDispatcher

    @Before
    fun setUp() {
        server.start()
        uploader = PhoneCoreLiveSessionUploader(
            http = http,
            clock = clock,
            logger = logger,
        )
        dispatcher = PhoneCoreLiveUploadDispatcher(uploader)
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun writeSegmentFile(name: String, size: Int = 32): File = File(temp.root, name).apply {
        writeBytes(ByteArray(size) { index -> ((index * 11) and 0xFF).toByte() })
    }

    private fun json(code: Int, body: JSONObject) =
        MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json").setBody(body.toString())

    private fun initCreated(uploadId: String) = json(
        HttpStatus.CREATED,
        JSONObject()
            .put("uploadId", uploadId)
            .put(
                "parts",
                JSONArray().put(
                    JSONObject().put("n", 1).put("url", server.url("/part/1").toString()),
                ),
            ),
    )

    private fun partOk(etag: String) = MockResponse().setResponseCode(HttpStatus.OK).setHeader("ETag", etag)

    @Test
    fun supportsKnownCommandsAndRejectsUnknownCommand() {
        val expectedCommands = listOf(
            "startSession",
            "enqueueSegment",
            "markRecordingStopped",
            "drainOnce",
            "getSnapshot",
            "hasPendingWork",
        )
        for (command in expectedCommands) {
            assertTrue("Expected $command to be supported", dispatcher.supports(command))
        }
        assertFalse(dispatcher.supports("nonExistentCommand"))

        try {
            dispatcher.dispatch("nonExistentCommand", emptyMap<String, Any?>())
            fail("Expected UnknownCommandException")
        } catch (expected: PhoneCoreLiveUploadDispatcher.UnknownCommandException) {
            assertTrue(expected.message.orEmpty().contains("nonExistentCommand"))
        }
    }

    @Test
    fun endToEndStartEnqueueStopDrainAndSnapshotWithMockWebServer() {
        val grant = testGrant("live-e2e", listOf(C1.TIER_PROXY), 4_000_000_000L)
        val baseUrl = server.url("/").toString()

        val emptyPending = dispatcher.dispatch("hasPendingWork")!!
        assertEquals(false, emptyPending["hasPendingWork"])
        assertNull(emptyPending["nextWakeAtMs"])
        assertEquals(0, emptyPending["pendingSessionCount"])
        assertEquals(0, emptyPending["pendingSegmentCount"])
        assertEquals(0L, emptyPending["pendingBytes"])
        assertEquals(emptyList<String>(), emptyPending["pendingSessionIds"])
        assertNull(dispatcher.dispatch("getSnapshot", mapOf("sessionId" to "live-e2e")))

        val started = dispatcher.dispatch(
            "startSession",
            mapOf(
                "sessionId" to "live-e2e",
                "slot" to "A",
                "uploadGrant" to grant,
                "ingestUrl" to baseUrl,
                "nowMs" to clock.now,
            ),
        )!!
        assertStartedSnapshot(started)

        val segmentFile = writeSegmentFile("proxy-0.ts", size = 40)
        val sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        val enqueued = dispatcher.dispatch(
            "enqueueSegment",
            mapOf(
                "sessionId" to "live-e2e",
                "slot" to "A",
                "tier" to C1.TIER_PROXY,
                "seq" to 0,
                "filePath" to segmentFile.absolutePath,
                "sha256" to sha256,
                "mediaStartServerMs" to clock.now,
                "durationMs" to 6_000,
                "nowMs" to clock.now,
            ),
        )!!
        assertEnqueuedSnapshot(enqueued, segmentFile, sha256)

        val pendingAfterEnqueue = dispatcher.dispatch("hasPendingWork", emptyMap<String, Any?>())!!
        assertEquals(true, pendingAfterEnqueue["hasPendingWork"])
        assertEquals(0L, pendingAfterEnqueue["nextWakeAtMs"])
        assertEquals(1, pendingAfterEnqueue["pendingSessionCount"])
        assertEquals(1, pendingAfterEnqueue["pendingSegmentCount"])
        assertEquals(40L, pendingAfterEnqueue["pendingBytes"])
        assertEquals(listOf("live-e2e"), pendingAfterEnqueue["pendingSessionIds"])

        val stopped = dispatcher.dispatch(
            "markRecordingStopped",
            mapOf(
                "sessionId" to "live-e2e",
                "stoppedAtMs" to (clock.now + 500L),
            ),
        )!!
        assertEquals(clock.now + 500L, stopped["stoppedAtMs"])
        assertEquals(0L, stopped["lastSeqProxy"])
        assertFalse(stopped["isComplete"] as Boolean)

        drainAndVerifyCompletion(segmentFile)
    }

    private fun assertStartedSnapshot(started: Map<String, Any?>) {
        assertEquals("live-e2e", started["sessionId"])
        assertEquals("A", started["slot"])
        assertEquals(listOf(C1.TIER_PROXY), started["grantedTiers"])
        assertEquals(0L, started["stoppedAtMs"])
        assertEquals(-1L, started["lastSeqProxy"])
        assertEquals(-1L, started["lastSeqMaster"])
        assertNull(started["manifestState"])
        assertEquals(0, started["totalSegments"])
        assertEquals(false, started["isComplete"])
        assertEquals(emptyList<Any>(), started["items"])
    }

    private fun assertEnqueuedSnapshot(enqueued: Map<String, Any?>, segmentFile: File, sha256: String) {
        assertEquals(1, enqueued["totalSegments"])
        assertEquals(1, enqueued["activeSegments"])
        assertEquals(0, enqueued["verifiedSegments"])
        assertEquals(40L, enqueued["pendingBytes"])
        assertEquals(0L, enqueued["lastSeqProxy"])
        assertEquals(-1L, enqueued["lastSeqMaster"])
        val items = itemsOf(enqueued)
        assertEquals(1, items.size)
        val item = items.first()
        assertEquals("live-e2e/proxy/0", item["key"])
        assertEquals("live-e2e", item["sessionId"])
        assertEquals("A", item["slot"])
        assertEquals(C1.TIER_PROXY, item["tier"])
        assertEquals(0L, item["seq"])
        assertEquals(segmentFile.absolutePath, item["filePath"])
        assertEquals(40L, item["bytes"])
        assertEquals(sha256, item["sha256"])
        assertEquals(clock.now, item["mediaStartServerMs"])
        assertEquals(6_000L, item["durationMs"])
        assertEquals(UploadState.PENDING.name, item["state"])
        assertNull(item["uploadId"])
        assertEquals(0, item["verifyRestarts"])
        assertEquals(0, item["attempts"])
        assertEquals(0L, item["nextAttemptAtMs"])
        assertNull(item["lastError"])
    }

    private fun drainAndVerifyCompletion(segmentFile: File) {
        // First drain: init -> PUT -> complete (1 step; next step waits 2_000ms for verify poll).
        server.enqueue(initCreated("u-e2e-0"))
        server.enqueue(partOk("etag-e2e-1"))
        server.enqueue(json(HttpStatus.OK, JSONObject()))

        val firstDrain = dispatcher.dispatch("drainOnce")!!
        assertEquals(1, firstDrain["stepsTaken"])
        assertEquals(true, firstDrain["didWork"])
        assertEquals(true, firstDrain["hasPendingWork"])
        assertEquals(clock.now + 2_000L, firstDrain["nextWakeAtMs"])

        val snapshotVerifying = dispatcher.dispatch("getSnapshot", mapOf("sessionId" to "live-e2e"))!!
        val verifyingItem = itemsOf(snapshotVerifying).first()
        assertEquals(UploadState.VERIFYING.name, verifyingItem["state"])
        assertEquals("u-e2e-0", verifyingItem["uploadId"])

        // Advance clock so status poll becomes due, then drain through verify + manifest completion.
        clock.now += 2_000L
        server.enqueue(json(HttpStatus.OK, JSONObject().put("state", "verified")))
        server.enqueue(json(HttpStatus.OK, JSONObject().put("state", UploadSession.MANIFEST_COMPLETE)))

        val secondDrain = dispatcher.dispatch("drainOnce", mapOf("maxSteps" to 8))!!
        assertEquals(2, secondDrain["stepsTaken"])
        assertEquals(true, secondDrain["didWork"])
        assertEquals(false, secondDrain["hasPendingWork"])
        assertNull(secondDrain["nextWakeAtMs"])
        assertEquals(0, secondDrain["pendingSessionCount"])
        assertEquals(0, secondDrain["pendingSegmentCount"])
        assertEquals(0L, secondDrain["pendingBytes"])
        assertEquals(emptyList<String>(), secondDrain["pendingSessionIds"])
        assertFalse(segmentFile.exists())

        val finalSnapshot = dispatcher.dispatch("getSnapshot", mapOf("sessionId" to "live-e2e"))!!
        assertEquals(UploadSession.MANIFEST_COMPLETE, finalSnapshot["manifestState"])
        assertEquals(true, finalSnapshot["isComplete"])
        assertEquals(1, finalSnapshot["totalSegments"])
        assertEquals(0, finalSnapshot["activeSegments"])
        assertEquals(1, finalSnapshot["verifiedSegments"])
        assertEquals(0, finalSnapshot["heldSegments"])
        assertEquals(0, finalSnapshot["failedSegments"])
        assertEquals(0, finalSnapshot["conflictSegments"])
        assertEquals(0L, finalSnapshot["pendingBytes"])
    }

    @Suppress("UNCHECKED_CAST")
    private fun itemsOf(snapshot: Map<String, Any?>): List<Map<String, Any?>> =
        snapshot["items"] as List<Map<String, Any?>>

    @Test
    fun drainOnceRespectsMaxStepsCapAndReportsZeroWhenIdle() {
        val idle = dispatcher.dispatch("drainOnce", mapOf("maxSteps" to 5))!!
        assertEquals(0, idle["stepsTaken"])
        assertEquals(false, idle["didWork"])
        assertEquals(false, idle["hasPendingWork"])
        assertNull(idle["nextWakeAtMs"])

        val grant = testGrant("live-cap", listOf(C1.TIER_PROXY), 4_000_000_000L)
        dispatcher.dispatch(
            "startSession",
            mapOf(
                "sessionId" to "live-cap",
                "slot" to "A",
                "uploadGrant" to grant,
                "ingestUrl" to server.url("/").toString(),
            ),
        )
        val f0 = writeSegmentFile("cap-0.ts")
        val f1 = writeSegmentFile("cap-1.ts")
        dispatcher.dispatch(
            "enqueueSegment",
            mapOf(
                "sessionId" to "live-cap",
                "slot" to "A",
                "tier" to C1.TIER_PROXY,
                "seq" to 0,
                "filePath" to f0.absolutePath,
                "sha256" to "sha-0",
                "mediaStartServerMs" to clock.now,
                "durationMs" to 6_000,
            ),
        )
        dispatcher.dispatch(
            "enqueueSegment",
            mapOf(
                "sessionId" to "live-cap",
                "slot" to "A",
                "tier" to C1.TIER_PROXY,
                "seq" to 1,
                "filePath" to f1.absolutePath,
                "sha256" to "sha-1",
                "mediaStartServerMs" to clock.now + 6_000L,
                "durationMs" to 6_000,
            ),
        )

        server.enqueue(json(HttpStatus.OK, JSONObject().put("uploadId", "u-0").put("state", "verified")))
        server.enqueue(json(HttpStatus.OK, JSONObject().put("uploadId", "u-1").put("state", "verified")))

        val capped = dispatcher.dispatch("drainOnce", mapOf("maxSteps" to 1))!!
        assertEquals(1, capped["stepsTaken"])
        assertEquals(true, capped["didWork"])
        assertEquals(true, capped["hasPendingWork"])
        assertNotNull(capped["nextWakeAtMs"])

        val rest = dispatcher.dispatch("drainOnce", mapOf("maxSteps" to 10L))!!
        assertEquals(1, rest["stepsTaken"])
        assertEquals(true, rest["didWork"])
        assertEquals(false, rest["hasPendingWork"])
        assertNull(rest["nextWakeAtMs"])
    }

    @Test
    fun markRecordingStoppedWithoutOptionalTimestampAndUnknownSession() {
        assertNull(dispatcher.dispatch("markRecordingStopped", mapOf("sessionId" to "unknown-session")))

        val grant = testGrant("live-opt-stop", listOf(C1.TIER_PROXY), 4_000_000_000L)
        dispatcher.dispatch(
            "startSession",
            mapOf(
                "sessionId" to "live-opt-stop",
                "slot" to "B",
                "uploadGrant" to grant,
                "ingestUrl" to server.url("/").toString(),
            ),
        )
        val stopped = dispatcher.dispatch("markRecordingStopped", mapOf("sessionId" to "live-opt-stop"))!!
        assertEquals(clock.now, stopped["stoppedAtMs"])
    }

    @Test
    fun validatesRequiredArgumentsAndBoundsCrisply() {
        val grant = testGrant("live-val", listOf(C1.TIER_PROXY), 4_000_000_000L)
        val baseUrl = server.url("/").toString()
        val file = writeSegmentFile("valid.ts")
        val missingFile = File(temp.root, "missing.ts")

        assertStartSessionValidation(grant, baseUrl)
        dispatcher.dispatch(
            "startSession",
            mapOf("sessionId" to "live-val", "slot" to "A", "uploadGrant" to grant, "ingestUrl" to baseUrl),
        )
        assertEnqueueValidation(file, missingFile)

        // markRecordingStopped validation
        expectInvalid("markRecordingStopped", mapOf("sessionId" to ""))
        expectInvalid("markRecordingStopped", mapOf("sessionId" to "../bad"))
        expectInvalid("markRecordingStopped", mapOf("sessionId" to "live-val", "stoppedAtMs" to 0))
        expectInvalid("markRecordingStopped", mapOf("sessionId" to "live-val", "stoppedAtMs" to "bad"))

        // drainOnce validation
        expectInvalid("drainOnce", mapOf("maxSteps" to 0))
        expectInvalid("drainOnce", mapOf("maxSteps" to 51))
        expectInvalid("drainOnce", mapOf("maxSteps" to "8"))
        expectInvalid("drainOnce", mapOf("maxSteps" to 2.5))

        // getSnapshot validation
        expectInvalid("getSnapshot", null)
        expectInvalid("getSnapshot", mapOf("sessionId" to " "))
        expectInvalid("getSnapshot", mapOf("sessionId" to "../bad"))
    }

    @Test
    fun coldRestartReloadsPersistedSessionsAndDrainsViaDispatcherWithoutStartSession() {
        val queueFile = File(temp.root, "dispatcher_cold_restart.json")
        val f0 = writeSegmentFile("disp-0.ts", size = 30)
        val f1 = writeSegmentFile("disp-1.ts", size = 50)
        seedStoppedDispatcherSession(queueFile, f0, f1)

        // Simulate full cold process restart with fresh FileUploadQueueStore + Uploader + Dispatcher.
        val dispatcher2 = newPersistentDispatcher(queueFile)
        val pendingOnBoot = dispatcher2.dispatch("hasPendingWork")!!
        assertEquals(true, pendingOnBoot["hasPendingWork"])
        assertEquals(0L, pendingOnBoot["nextWakeAtMs"])
        assertEquals(1, pendingOnBoot["pendingSessionCount"])
        assertEquals(2, pendingOnBoot["pendingSegmentCount"])
        assertEquals(80L, pendingOnBoot["pendingBytes"])
        assertEquals(listOf("live-cold-disp"), pendingOnBoot["pendingSessionIds"])

        // Drain seg 1 into VERIFYING without calling startSession again.
        server.enqueue(initCreated("u-disp-1"))
        server.enqueue(partOk("etag-d1"))
        server.enqueue(json(HttpStatus.OK, JSONObject()))
        val bootDrain = dispatcher2.dispatch("drainOnce", mapOf("maxSteps" to 16))!!
        assertEquals(1, bootDrain["stepsTaken"])
        assertEquals(true, bootDrain["didWork"])
        assertEquals(true, bootDrain["hasPendingWork"])
        assertEquals(clock.now + 2_000L, bootDrain["nextWakeAtMs"])
        assertEquals(1, bootDrain["pendingSessionCount"])
        assertEquals(2, bootDrain["pendingSegmentCount"])

        verifyAndCompleteRestoredDispatcherSession(dispatcher2, f0, f1)
    }

    @Test
    fun coldRestartWithExpiredGrantAndUnstoppedSessionSettlesCleanly() {
        val queueFile = File(temp.root, "dispatcher_cold_edge.json")
        val fExpired = writeSegmentFile("exp-0.ts", size = 20)
        val fUnstopped = writeSegmentFile("unst-0.ts", size = 35)
        seedExpiredAndUnstoppedSessions(queueFile, fExpired, fUnstopped)

        // Advance past shortGrant expiry, then cold-restart.
        clock.now += 20_000L
        val dispatcher2 = newPersistentDispatcher(queueFile)
        val pending = dispatcher2.dispatch("hasPendingWork")!!
        assertEquals(true, pending["hasPendingWork"])
        assertEquals(2, pending["pendingSessionCount"])
        assertEquals(2, pending["pendingSegmentCount"])
        assertEquals(55L, pending["pendingBytes"])
        assertEquals(listOf("live-expired", "live-unstopped"), pending["pendingSessionIds"])

        // Unstopped session uploads & verifies; expired session settles to FAILED without looping.
        server.enqueue(json(HttpStatus.OK, JSONObject().put("uploadId", "u-unst").put("state", "verified")))
        val drain = dispatcher2.dispatch("drainOnce", mapOf("maxSteps" to 16))!!
        assertEquals(2, drain["stepsTaken"])
        assertEquals(false, drain["hasPendingWork"])
        assertNull(drain["nextWakeAtMs"])
        assertEquals(0, drain["pendingSessionCount"])
        assertEquals(0, drain["pendingSegmentCount"])
        assertEquals(0L, drain["pendingBytes"])

        val expiredSnap = dispatcher2.dispatch("getSnapshot", mapOf("sessionId" to "live-expired"))!!
        assertEquals(1, expiredSnap["failedSegments"])
        assertEquals(false, expiredSnap["isComplete"])
        assertTrue(fExpired.exists())

        val unstoppedSnap = dispatcher2.dispatch("getSnapshot", mapOf("sessionId" to "live-unstopped"))!!
        assertEquals(1, unstoppedSnap["verifiedSegments"])
        assertEquals(false, unstoppedSnap["isComplete"])
        assertFalse(fUnstopped.exists())
    }

    private fun newPersistentDispatcher(queueFile: File) = PhoneCoreLiveUploadDispatcher(
        PhoneCoreLiveSessionUploader(
            http = http,
            store = FileUploadQueueStore(queueFile, logger),
            clock = clock,
            logger = logger,
        ),
    )

    private fun dispatchStartAndEnqueue(
        target: PhoneCoreLiveUploadDispatcher,
        sessionId: String,
        slot: String,
        grant: String,
        file: File,
    ) {
        target.dispatch(
            "startSession",
            mapOf(
                "sessionId" to sessionId,
                "slot" to slot,
                "uploadGrant" to grant,
                "ingestUrl" to server.url("/").toString(),
                "nowMs" to clock.now,
            ),
        )
        target.dispatch(
            "enqueueSegment",
            mapOf(
                "sessionId" to sessionId,
                "slot" to slot,
                "tier" to C1.TIER_PROXY,
                "seq" to 0,
                "filePath" to file.absolutePath,
                "sha256" to "sha-$sessionId-0",
                "mediaStartServerMs" to clock.now,
                "durationMs" to 2_000,
            ),
        )
    }

    private fun seedStoppedDispatcherSession(queueFile: File, f0: File, f1: File) {
        val grant = testGrant("live-cold-disp", listOf(C1.TIER_PROXY), 4_000_000_000L)
        val dispatcher1 = newPersistentDispatcher(queueFile)
        dispatchStartAndEnqueue(dispatcher1, "live-cold-disp", "A", grant, f0)
        dispatcher1.dispatch(
            "enqueueSegment",
            mapOf(
                "sessionId" to "live-cold-disp",
                "slot" to "A",
                "tier" to C1.TIER_PROXY,
                "seq" to 1,
                "filePath" to f1.absolutePath,
                "sha256" to "sha-cold-1",
                "mediaStartServerMs" to clock.now + 2_000L,
                "durationMs" to 2_000,
            ),
        )
        dispatcher1.dispatch(
            "markRecordingStopped",
            mapOf("sessionId" to "live-cold-disp", "stoppedAtMs" to (clock.now + 4_000L)),
        )

        server.enqueue(initCreated("u-disp-0"))
        server.enqueue(partOk("etag-d0"))
        server.enqueue(json(HttpStatus.OK, JSONObject()))
        val preCrashDrain = dispatcher1.dispatch("drainOnce", mapOf("maxSteps" to 1))!!
        assertEquals(1, preCrashDrain["stepsTaken"])
        assertEquals(true, preCrashDrain["hasPendingWork"])
    }

    private fun verifyAndCompleteRestoredDispatcherSession(
        dispatcher2: PhoneCoreLiveUploadDispatcher,
        f0: File,
        f1: File,
    ) {
        clock.now += 2_000L
        server.enqueue(json(HttpStatus.OK, JSONObject().put("state", "verified")))
        server.enqueue(json(HttpStatus.OK, JSONObject().put("state", "verified")))
        server.enqueue(json(HttpStatus.OK, JSONObject().put("state", UploadSession.MANIFEST_COMPLETE)))
        val finalDrain = dispatcher2.dispatch("drainOnce", mapOf("maxSteps" to 16))!!
        assertEquals(3, finalDrain["stepsTaken"])
        assertEquals(true, finalDrain["didWork"])
        assertEquals(false, finalDrain["hasPendingWork"])
        assertNull(finalDrain["nextWakeAtMs"])
        assertEquals(0, finalDrain["pendingSessionCount"])
        assertEquals(0, finalDrain["pendingSegmentCount"])
        assertEquals(0L, finalDrain["pendingBytes"])
        assertEquals(emptyList<String>(), finalDrain["pendingSessionIds"])

        val snapshot = dispatcher2.dispatch("getSnapshot", mapOf("sessionId" to "live-cold-disp"))!!
        assertEquals(true, snapshot["isComplete"])
        assertEquals(2, snapshot["verifiedSegments"])
        assertEquals(0, snapshot["activeSegments"])
        assertEquals(UploadSession.MANIFEST_COMPLETE, snapshot["manifestState"])
        assertFalse(f0.exists())
        assertFalse(f1.exists())
    }

    private fun seedExpiredAndUnstoppedSessions(queueFile: File, fExpired: File, fUnstopped: File) {
        val shortGrant = testGrant("live-expired", listOf(C1.TIER_PROXY), (clock.now / 1_000L) + 10L)
        val longGrant = testGrant("live-unstopped", listOf(C1.TIER_PROXY), 4_000_000_000L)
        val dispatcher1 = newPersistentDispatcher(queueFile)
        dispatchStartAndEnqueue(dispatcher1, "live-expired", "A", shortGrant, fExpired)
        dispatchStartAndEnqueue(dispatcher1, "live-unstopped", "B", longGrant, fUnstopped)
    }

    private fun assertStartSessionValidation(grant: String, baseUrl: String) {
        fun startArgs(overrides: Map<String, Any?> = emptyMap(), omit: String? = null): Map<String, Any?> {
            val base = mutableMapOf<String, Any?>(
                "sessionId" to "live-val",
                "slot" to "A",
                "uploadGrant" to grant,
                "ingestUrl" to baseUrl,
            )
            base.putAll(overrides)
            if (omit != null) {
                base.remove(omit)
            }
            return base
        }

        expectInvalid("startSession", null)
        expectInvalid("startSession", startArgs(omit = "sessionId"))
        expectInvalid("startSession", startArgs(mapOf("sessionId" to " ")))
        expectInvalid("startSession", startArgs(mapOf("sessionId" to 123)))
        expectInvalid("startSession", startArgs(mapOf("sessionId" to "../bad")))
        expectInvalid("startSession", startArgs(mapOf("slot" to "")))
        expectInvalid("startSession", startArgs(mapOf("uploadGrant" to "")))
        expectInvalid("startSession", startArgs(mapOf("ingestUrl" to "http://example.com")))
        expectInvalid("startSession", startArgs(mapOf("nowMs" to -1)))
        expectInvalid("startSession", startArgs(mapOf("nowMs" to "bad")))
    }

    private fun assertEnqueueValidation(file: File, missingFile: File) {
        fun enqueueArgs(overrides: Map<String, Any?> = emptyMap()): Map<String, Any?> {
            val base = mutableMapOf<String, Any?>(
                "sessionId" to "live-val",
                "slot" to "A",
                "tier" to C1.TIER_PROXY,
                "seq" to 0,
                "filePath" to file.absolutePath,
                "sha256" to "abc",
                "mediaStartServerMs" to 1_700_000_000_000L,
                "durationMs" to 6_000,
            )
            base.putAll(overrides)
            return base
        }

        expectInvalid("enqueueSegment", enqueueArgs(mapOf("sessionId" to "unknown-sid")))
        expectInvalid("enqueueSegment", enqueueArgs(mapOf("sessionId" to "../bad")))
        expectInvalid("enqueueSegment", enqueueArgs(mapOf("slot" to " ")))
        expectInvalid("enqueueSegment", enqueueArgs(mapOf("tier" to "invalid")))
        expectInvalid("enqueueSegment", enqueueArgs(mapOf("seq" to null)))
        expectInvalid("enqueueSegment", enqueueArgs(mapOf("seq" to -1)))
        expectInvalid("enqueueSegment", enqueueArgs(mapOf("seq" to 1.5)))
        expectInvalid("enqueueSegment", enqueueArgs(mapOf("filePath" to missingFile.absolutePath)))
        expectInvalid("enqueueSegment", enqueueArgs(mapOf("filePath" to temp.root.absolutePath)))
        expectInvalid("enqueueSegment", enqueueArgs(mapOf("sha256" to "")))
        expectInvalid("enqueueSegment", enqueueArgs(mapOf("mediaStartServerMs" to "now")))
        expectInvalid("enqueueSegment", enqueueArgs(mapOf("durationMs" to -5)))
        expectInvalid("enqueueSegment", enqueueArgs(mapOf("nowMs" to -1)))
    }

    private fun expectInvalid(command: String, arguments: Map<String, Any?>?) {
        try {
            dispatcher.dispatch(command, arguments)
            fail("Expected IllegalArgumentException for $command")
        } catch (expected: IllegalArgumentException) {
            assertTrue(expected.message.orEmpty().isNotBlank())
        }
    }
}
