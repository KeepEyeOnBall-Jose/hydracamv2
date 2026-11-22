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
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class FileUploadQueueStoreTest {
    @get:Rule
    val temp = TemporaryFolder()

    private val server = MockWebServer()
    private val clock = FakePhoneClock()
    private val logger = RecordingPhoneLogger()
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

    private fun queueFile(relativePath: String = "queue.json"): File = File(temp.root, relativePath)

    private fun sampleSession(
        sessionId: String = "s1",
        slot: String = "A",
        stoppedAtMs: Long = 0L,
        manifestState: String? = null,
        nextManifestAtMs: Long = 0L,
        grantExpMs: Long = Long.MAX_VALUE,
    ): UploadSession = UploadSession(
        sessionId = sessionId,
        slot = slot,
        uploadGrant = testGrant(sessionId, listOf(C1.TIER_PROXY, C1.TIER_MASTER), 4_000_000_000L),
        ingestUrl = "https://k3.example",
        grantExpMs = grantExpMs,
        tiersCsv = "${C1.TIER_PROXY},${C1.TIER_MASTER}",
        stoppedAtMs = stoppedAtMs,
        lastSeqProxy = 2L,
        lastSeqMaster = 1L,
        manifestState = manifestState,
        manifestAttempts = if (manifestState == null) 0 else 1,
        nextManifestAtMs = nextManifestAtMs,
        createdAtMs = 100L,
        masterGrant = "master-grant-$sessionId",
        masterIngestUrl = "https://master.k3.example",
        masterGrantExpMs = 5_000L,
    )

    private fun sampleItem(
        tier: String,
        seq: Long,
        state: UploadState = UploadState.PENDING,
        priority: Long = 0L,
        nextAtMs: Long = 0L,
        createdAtMs: Long = 10L,
        updatedAtMs: Long = 10L,
        sessionId: String = "s1",
        lastError: String? = null,
    ): UploadItem = UploadItem(
        key = UploadItem.keyOf(sessionId, tier, seq),
        sessionId = sessionId,
        slot = "A",
        tier = tier,
        seq = seq,
        filePath = File(temp.root, "$sessionId-$tier-$seq.ts").absolutePath,
        bytes = 100L + seq,
        sha256 = "sha-$sessionId-$tier-$seq",
        mediaStartServerMs = seq * 6_000L,
        durationMs = 6_000L,
        state = state.name,
        uploadId = if (state == UploadState.UPLOADING) "up-$seq" else null,
        partsJson = if (state == UploadState.UPLOADING) """[{"n":1,"url":"https://k3.example/p/1"}]""" else null,
        etagsJson = if (state == UploadState.UPLOADING) """{"1":"etag-1"}""" else null,
        verifyRestarts = 1,
        priority = priority,
        attempts = 2,
        nextAttemptAtMs = nextAtMs,
        lastError = lastError,
        createdAtMs = createdAtMs,
        updatedAtMs = updatedAtMs,
    )

    private fun sampleMasterRequest(
        id: String,
        sessionId: String = "s1",
        state: String = MasterRequest.STATE_PENDING,
        nextAtMs: Long = 0L,
        createdAtMs: Long = 10L,
        lastError: String? = null,
    ): MasterRequest = MasterRequest(
        id = id,
        sessionId = sessionId,
        slot = "A",
        uploadGrant = "master-req-grant-$id",
        ingestUrl = "https://k3.example",
        grantExpMs = Long.MAX_VALUE,
        seqsJson = "[0,1]",
        state = state,
        attempts = 1,
        nextAttemptAtMs = nextAtMs,
        lastError = lastError,
        createdAtMs = createdAtMs,
    )

    private fun writeSegmentFile(name: String, size: Int = 32): File = File(temp.root, name).apply {
        writeBytes(ByteArray(size) { index -> ((index * 5) and 0xFF).toByte() })
    }

    private fun jsonResponse(code: Int, body: JSONObject) =
        MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json").setBody(body.toString())

    private fun initCreated(uploadId: String) = jsonResponse(
        HttpStatus.CREATED,
        JSONObject()
            .put("uploadId", uploadId)
            .put("parts", JSONArray().put(JSONObject().put("n", 1).put("url", server.url("/part/1").toString()))),
    )

    private fun assertNoTempFiles(dir: File) {
        val temps = dir.listFiles().orEmpty().filter { it.name.endsWith(".tmp") }
        assertTrue("Expected no leftover .tmp files, found: ${temps.map { it.name }}", temps.isEmpty())
    }

    @Test
    fun crudParityWithInMemoryStoreForSessionsItemsMasterRequestsAndSeqs() {
        val file = queueFile()
        val fileStore = FileUploadQueueStore(file, logger)
        val memoryStore = InMemoryUploadQueueStore()
        val stores: List<UploadQueueStore> = listOf(fileStore, memoryStore)

        val s1 = sampleSession("s1", "A")
        val s2 = sampleSession("s2", "B").copy(
            uploadGrant = "",
            tiersCsv = "",
            masterGrant = null,
            masterIngestUrl = null,
        )
        stores.forEach { store ->
            assertEmptyReadsAreNull(store)
            seedParityRecords(store, s1, s2)
        }

        assertEquals(memoryStore.sessions(), fileStore.sessions())
        assertEquals(memoryStore.session("s1"), fileStore.session("s1"))
        assertEquals(memoryStore.session("s2"), fileStore.session("s2"))
        assertEquals(memoryStore.items("s1"), fileStore.items("s1"))
        assertEquals(memoryStore.item("s1/proxy/2"), fileStore.item("s1/proxy/2"))
        assertEquals(memoryStore.nextWakeAtMs(), fileStore.nextWakeAtMs())
        assertEquals(memoryStore.nextWakeAtMs(includeMasters = false), fileStore.nextWakeAtMs(includeMasters = false))
        assertEquals(memoryStore.nextDue(100L), fileStore.nextDue(100L))
        assertEquals(memoryStore.nextDue(100L, includeMasters = false), fileStore.nextDue(100L, includeMasters = false))
        assertEquals(memoryStore.dueMasterRequest(30L), fileStore.dueMasterRequest(30L))
        assertEquals(memoryStore.masterRequest("r-sent"), fileStore.masterRequest("r-sent"))
        assertEquals(memoryStore.activeCount(), fileStore.activeCount())
        assertEquals(memoryStore.activeBytes(), fileStore.activeBytes())
        assertEquals(memoryStore.lastSeq("s1", C1.TIER_PROXY), fileStore.lastSeq("s1", C1.TIER_PROXY))
        assertEquals(memoryStore.lastSeq("s1", C1.TIER_MASTER), fileStore.lastSeq("s1", C1.TIER_MASTER))
        assertNoTempFiles(temp.root)
    }

    private fun assertEmptyReadsAreNull(store: UploadQueueStore) {
        assertNull(store.nextWakeAtMs())
        assertNull(store.session("missing"))
        assertNull(store.item("missing"))
        assertNull(store.masterRequest("missing"))
        assertNull(store.dueMasterRequest(100L))
    }

    private fun seedParityRecords(store: UploadQueueStore, s1: UploadSession, s2: UploadSession) {
        store.upsertSession(s1)
        store.upsertSession(s2)

        store.enqueue(sampleItem(C1.TIER_PROXY, 2, UploadState.UPLOADING, nextAtMs = 80L, createdAtMs = 40L))
        // Re-enqueue of existing key must be a no-op.
        store.enqueue(sampleItem(C1.TIER_PROXY, 2, UploadState.PENDING, nextAtMs = 1L, createdAtMs = 1L))
        store.enqueue(sampleItem(C1.TIER_MASTER, 0, UploadState.PENDING, priority = 10L, nextAtMs = 50L))
        store.enqueue(sampleItem(C1.TIER_MASTER, 1, UploadState.PENDING, priority = 900L, nextAtMs = 70L))
        store.enqueue(sampleItem(C1.TIER_MASTER, 2, UploadState.HELD))
        store.enqueue(sampleItem(C1.TIER_PROXY, 0, UploadState.VERIFIED, nextAtMs = 1L))
        store.enqueue(sampleItem(C1.TIER_PROXY, 9, UploadState.PENDING, sessionId = "s2", nextAtMs = 90L))

        store.update(
            sampleItem(C1.TIER_MASTER, 0, UploadState.PENDING, priority = 10L, nextAtMs = 50L, lastError = "retry"),
        )
        store.upsertMasterRequest(sampleMasterRequest("r-sent", state = MasterRequest.STATE_SENT, nextAtMs = 2L))
        store.upsertMasterRequest(sampleMasterRequest("r-late", nextAtMs = 60L, createdAtMs = 2L))
        store.upsertMasterRequest(sampleMasterRequest("r-due-new", nextAtMs = 30L, createdAtMs = 20L))
        store.upsertMasterRequest(sampleMasterRequest("r-due-old", nextAtMs = 30L, createdAtMs = 5L))
        store.commitSeq("s1", C1.TIER_PROXY, 4L)
    }

    @Test
    fun persistsSessionsItemsMasterRequestsAndSeqsAcrossReinstantiation() {
        val file = queueFile("persisted.json")
        val store1 = FileUploadQueueStore(file, logger)
        val s1 = sampleSession("s1", "A", stoppedAtMs = 500L, manifestState = UploadSession.MANIFEST_PARTIAL)
        val item1 = sampleItem(C1.TIER_PROXY, 0, UploadState.UPLOADING, nextAtMs = 200L, lastError = "net")
        val item2 = sampleItem(C1.TIER_MASTER, 1, UploadState.HELD, lastError = "")
        val req1 = sampleMasterRequest(
            "cmd-1",
            state = MasterRequest.STATE_PENDING,
            nextAtMs = 150L,
            lastError = "wait",
        )

        store1.upsertSession(s1)
        store1.enqueue(item1)
        store1.enqueue(item2)
        store1.update(item1.copy(attempts = 3))
        store1.upsertMasterRequest(req1)
        store1.commitSeq("s1", C1.TIER_PROXY, 7L)
        store1.commitSeq("s1", C1.TIER_MASTER, 3L)

        val store2 = FileUploadQueueStore(file, logger)
        assertEquals(listOf(s1), store2.sessions())
        assertEquals(s1, store2.session("s1"))
        assertEquals(listOf(item2, item1.copy(attempts = 3)), store2.items("s1"))
        assertEquals(item1.copy(attempts = 3), store2.item("s1/proxy/0"))
        assertEquals(req1, store2.masterRequest("cmd-1"))
        assertEquals(req1, store2.dueMasterRequest(150L))
        assertEquals(150L, store2.nextWakeAtMs())
        assertEquals(1, store2.activeCount())
        assertEquals(100L, store2.activeBytes())
        assertEquals(7L, store2.lastSeq("s1", C1.TIER_PROXY))
        assertEquals(3L, store2.lastSeq("s1", C1.TIER_MASTER))
        assertNoTempFiles(temp.root)
    }

    @Test
    fun survivesRestartMidUploadWithPhoneCoreLiveSessionUploader() {
        val file = queueFile("live_uploader_queue.json")
        val grant = testGrant("live-persist", listOf(C1.TIER_PROXY), 4_000_000_000L)
        val baseUrl = server.url("/").toString()
        val segFile = writeSegmentFile("proxy-0.ts", size = 48)

        val uploader1 = PhoneCoreLiveSessionUploader(
            http = http,
            store = FileUploadQueueStore(file, logger),
            clock = clock,
            logger = logger,
        )
        uploader1.startSession("live-persist", "A", grant, baseUrl, clock.now)
        uploader1.enqueueSegment(
            sessionId = "live-persist",
            slot = "A",
            tier = C1.TIER_PROXY,
            seq = 0L,
            file = segFile,
            sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            mediaStartServerMs = clock.now,
            durationMs = 6_000L,
        )
        uploader1.markRecordingStopped("live-persist", stoppedAtMs = clock.now + 500L)

        val expectedSnapBeforeRestart = uploader1.snapshot("live-persist")!!
        assertTrue(uploader1.hasPendingWork())

        // Simulate process restart: new FileUploadQueueStore & PhoneCoreLiveSessionUploader over same file.
        val uploader2 = PhoneCoreLiveSessionUploader(
            http = http,
            store = FileUploadQueueStore(file, logger),
            clock = clock,
            logger = logger,
        )
        assertEquals(expectedSnapBeforeRestart, uploader2.snapshot("live-persist"))
        assertTrue(uploader2.hasPendingWork())

        server.enqueue(initCreated("u-live-0"))
        server.enqueue(MockResponse().setResponseCode(HttpStatus.OK).setHeader("ETag", "etag-1"))
        server.enqueue(jsonResponse(HttpStatus.OK, JSONObject()))
        assertTrue(uploader2.drainOnce())

        clock.now += 2_000L
        server.enqueue(jsonResponse(HttpStatus.OK, JSONObject().put("state", "verified")))
        assertTrue(uploader2.drainOnce())
        server.enqueue(jsonResponse(HttpStatus.OK, JSONObject().put("state", UploadSession.MANIFEST_COMPLETE)))
        assertTrue(uploader2.drainOnce())

        val uploader3 = PhoneCoreLiveSessionUploader(
            http = http,
            store = FileUploadQueueStore(file, logger),
            clock = clock,
            logger = logger,
        )
        val completed = uploader3.snapshot("live-persist")!!
        assertTrue(completed.isComplete)
        assertEquals(1, completed.verifiedSegments)
        assertEquals(0, completed.activeSegments)
        assertFalse(uploader3.hasPendingWork())
        assertNoTempFiles(temp.root)
    }

    @Test
    fun createsMissingParentDirectoryOnFlushAndCleansLeftoverTempFile() {
        val nestedDir = File(temp.root, "nested/sub/dir")
        val file = File(nestedDir, "queue.json")
        val store = FileUploadQueueStore(file, logger)
        assertFalse(nestedDir.exists())
        assertTrue(store.sessions().isEmpty())

        store.upsertSession(sampleSession("s-nested"))
        assertTrue(nestedDir.isDirectory)
        assertTrue(file.isFile)
        assertNoTempFiles(nestedDir)

        val leftoverTmp = File(nestedDir, "${file.name}.tmp")
        leftoverTmp.writeText("stale temp")
        val reloaded = FileUploadQueueStore(file, logger)
        assertFalse(leftoverTmp.exists())
        assertEquals(1, reloaded.sessions().size)
    }

    @Test
    fun recoversFromCorruptOrInvalidJsonAndPreservesBackupFile() {
        val file = queueFile("corrupt.json")
        val truncated = """{"version":1,"sessions":["""
        file.writeText(truncated)

        val recovered1 = FileUploadQueueStore(file, logger)
        assertTrue(recovered1.sessions().isEmpty())
        assertEquals(0, recovered1.activeCount())
        assertNull(recovered1.nextWakeAtMs())
        assertFalse(file.exists())
        val backup1 = File(temp.root, "corrupt.json.corrupt")
        assertTrue(backup1.isFile)
        assertEquals(truncated, backup1.readText())
        assertTrue(logger.warnings.isNotEmpty())

        // Second and third corruptions preserve distinct backups without overwriting earlier ones.
        val badVersion = """{"version":99,"sessions":[],"items":[],"masterRequests":[],"seqs":[]}"""
        file.writeText(badVersion)
        val recovered2 = FileUploadQueueStore(file, logger)
        assertTrue(recovered2.sessions().isEmpty())
        val backup2 = File(temp.root, "corrupt.json.corrupt.1")
        assertTrue(backup2.isFile)
        assertEquals(badVersion, backup2.readText())
        assertEquals(truncated, backup1.readText())

        file.writeText("""{"version":1,"sessions":[123]}""")
        val recovered3 = FileUploadQueueStore(file, logger)
        assertTrue(recovered3.sessions().isEmpty())
        assertTrue(File(temp.root, "corrupt.json.corrupt.2").isFile)

        // Subsequent writes persist cleanly and reload cleanly.
        recovered3.upsertSession(sampleSession("s-clean"))
        assertEquals(listOf("s-clean"), FileUploadQueueStore(file, logger).sessions().map { it.sessionId })
        assertNoTempFiles(temp.root)
    }

    @Test
    fun recoversFromBlankMalformedSchemaAndHandlesFlushIoFailure() {
        val blankFile = queueFile("blank.json")
        blankFile.writeText("   ")
        assertTrue(FileUploadQueueStore(blankFile, logger).sessions().isEmpty())
        assertTrue(File(temp.root, "blank.json.corrupt").isFile)

        val sessionPrefix =
            """"sessionId":"s","slot":"A","uploadGrant":"g","ingestUrl":"https://k""""
        val badPayloads = listOf(
            """{"version":1,"sessions":"not-array"}""",
            """{"version":1,"sessions":[{}]}""",
            """{"version":1,"sessions":[{"sessionId":123}]}""",
            """{"version":1,"sessions":[{$sessionPrefix,"grantExpMs":"bad"}]}""",
            """{"version":1,"sessions":[{$sessionPrefix,"grantExpMs":1,"tiersCsv":"",""" +
                """"stoppedAtMs":0,"lastSeqProxy":-1,"lastSeqMaster":-1,"manifestState":123}]}""",
            """{"version":1,"sessions":[{$sessionPrefix,"grantExpMs":1,"tiersCsv":"",""" +
                """"stoppedAtMs":0,"lastSeqProxy":-1,"lastSeqMaster":-1,"manifestState":null,""" +
                """"manifestAttempts":999999999999}]}""",
        )
        badPayloads.forEachIndexed { index, payload ->
            val badFile = queueFile("bad_$index.json")
            badFile.writeText(payload)
            assertTrue(FileUploadQueueStore(badFile, logger).sessions().isEmpty())
            assertTrue(File(temp.root, "bad_$index.json.corrupt").isFile)
        }

        // Minimal version-only envelope with omitted arrays decodes cleanly as empty.
        val minimalFile = queueFile("minimal.json")
        minimalFile.writeText("""{"version":1}""")
        assertTrue(FileUploadQueueStore(minimalFile, logger).sessions().isEmpty())

        // Unwritable parent path logs warning without crashing callers.
        val blocker = queueFile("blocker_file")
        blocker.writeText("not a directory")
        val blockedStore = FileUploadQueueStore(File(blocker, "queue.json"), logger)
        blockedStore.upsertSession(sampleSession("s-blocked"))
        assertNotNull(blockedStore.session("s-blocked"))
        assertTrue(logger.warnings.isNotEmpty())
    }

    @Test
    fun purgeFinishedBeforeRemovesOldTerminalRecordsAndPersistsCleanly() {
        val file = queueFile("purge.json")
        val store = FileUploadQueueStore(file, logger)
        val cutoff = 1_000L
        seedCompletedPurgeSessions(store)
        seedRetainedPurgeSessions(store, cutoff)

        val removed = store.purgeFinishedBefore(cutoff)
        assertEquals(7, removed)
        assertEquals(0, store.purgeFinishedBefore(cutoff))

        val reloaded = FileUploadQueueStore(file, logger)
        assertNull(reloaded.session("s-done"))
        assertNull(reloaded.session("s-partial-final"))
        assertEquals(-1L, reloaded.lastSeq("s-done", C1.TIER_PROXY))
        assertTrue(reloaded.items("s-done").isEmpty())
        assertNull(reloaded.masterRequest("mr-done"))

        assertNotNull(reloaded.session("s-partial-retry"))
        assertNotNull(reloaded.session("s-unstopped"))
        assertNotNull(reloaded.session("s-recent-stop"))
        assertNotNull(reloaded.session("s-req-keep"))
        assertNotNull(reloaded.session("s-keep"))
        assertEquals(4L, reloaded.lastSeq("s-keep", C1.TIER_PROXY))
        assertNull(reloaded.item("s-keep/proxy/0"))
        assertNotNull(reloaded.item("s-keep/proxy/1"))
        assertNotNull(reloaded.item("s-keep/proxy/2"))
        assertNotNull(reloaded.item("s-keep/master/0"))
        assertNotNull(reloaded.masterRequest("mr-pending"))
        assertNoTempFiles(temp.root)
    }

    private fun seedCompletedPurgeSessions(store: FileUploadQueueStore) {
        store.upsertSession(
            sampleSession("s-done", stoppedAtMs = 500L, manifestState = UploadSession.MANIFEST_COMPLETE),
        )
        store.commitSeq("s-done", C1.TIER_PROXY, 2L)
        store.enqueue(sampleItem(C1.TIER_PROXY, 0, UploadState.VERIFIED, updatedAtMs = 800L, sessionId = "s-done"))
        store.enqueue(sampleItem(C1.TIER_PROXY, 1, UploadState.FAILED, updatedAtMs = 900L, sessionId = "s-done"))
        store.enqueue(
            sampleItem(
                C1.TIER_PROXY,
                2,
                UploadState.CONFLICT,
                createdAtMs = 700L,
                updatedAtMs = 0L,
                sessionId = "s-done",
            ),
        )
        store.upsertMasterRequest(
            sampleMasterRequest("mr-done", sessionId = "s-done", state = MasterRequest.STATE_SENT, createdAtMs = 400L),
        )
        store.upsertSession(
            sampleSession(
                "s-partial-final",
                stoppedAtMs = 500L,
                manifestState = UploadSession.MANIFEST_PARTIAL,
                nextManifestAtMs = Long.MAX_VALUE,
            ),
        )
    }

    private fun seedRetainedPurgeSessions(store: FileUploadQueueStore, cutoff: Long) {
        store.upsertSession(
            sampleSession(
                "s-partial-retry",
                stoppedAtMs = 500L,
                manifestState = UploadSession.MANIFEST_PARTIAL,
                nextManifestAtMs = 2_000L,
            ),
        )
        store.upsertSession(
            sampleSession("s-unstopped", stoppedAtMs = 0L, manifestState = UploadSession.MANIFEST_COMPLETE),
        )
        store.upsertSession(
            sampleSession("s-recent-stop", stoppedAtMs = cutoff, manifestState = UploadSession.MANIFEST_COMPLETE),
        )
        store.upsertSession(
            sampleSession("s-req-keep", stoppedAtMs = 500L, manifestState = UploadSession.MANIFEST_COMPLETE),
        )
        store.upsertMasterRequest(
            sampleMasterRequest(
                "mr-req-keep",
                sessionId = "s-req-keep",
                state = MasterRequest.STATE_PENDING,
                createdAtMs = 100L,
            ),
        )
        store.upsertSession(
            sampleSession("s-keep", stoppedAtMs = 500L, manifestState = UploadSession.MANIFEST_COMPLETE),
        )
        store.commitSeq("s-keep", C1.TIER_PROXY, 4L)
        store.enqueue(sampleItem(C1.TIER_PROXY, 0, UploadState.VERIFIED, updatedAtMs = 500L, sessionId = "s-keep"))
        store.enqueue(sampleItem(C1.TIER_PROXY, 1, UploadState.VERIFIED, updatedAtMs = 1_000L, sessionId = "s-keep"))
        store.enqueue(sampleItem(C1.TIER_PROXY, 2, UploadState.PENDING, updatedAtMs = 100L, sessionId = "s-keep"))
        store.enqueue(sampleItem(C1.TIER_MASTER, 0, UploadState.HELD, updatedAtMs = 100L, sessionId = "s-keep"))
        store.upsertMasterRequest(
            sampleMasterRequest(
                "mr-pending",
                sessionId = "s-keep",
                state = MasterRequest.STATE_PENDING,
                createdAtMs = 100L,
            ),
        )
    }

    @Test
    fun concurrentMutationsProduceConsistentPersistedState() {
        val file = queueFile("concurrent.json")
        val store = FileUploadQueueStore(file, logger)
        store.upsertSession(sampleSession("s-conc"))
        val threads = 4
        val perThread = 15
        val pool = Executors.newFixedThreadPool(threads)
        val latch = CountDownLatch(threads)
        try {
            repeat(threads) { threadIndex ->
                pool.execute {
                    try {
                        repeat(perThread) { offset ->
                            val seq = (threadIndex * perThread + offset).toLong()
                            val item = sampleItem(C1.TIER_PROXY, seq, UploadState.PENDING, sessionId = "s-conc")
                            store.enqueue(item)
                            store.update(item.copy(attempts = 1))
                            store.items("s-conc")
                            store.nextDue(10_000L)
                        }
                    } finally {
                        latch.countDown()
                    }
                }
            }
            assertTrue(latch.await(10, TimeUnit.SECONDS))
        } finally {
            pool.shutdownNow()
        }

        val reloaded = FileUploadQueueStore(file, logger)
        assertEquals(threads * perThread, reloaded.items("s-conc").size)
        assertEquals(threads * perThread, reloaded.activeCount())
        assertNoTempFiles(temp.root)
    }
}
