package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class UploadQueueStoreTest {
    private val store = InMemoryUploadQueueStore()

    private fun item(
        tier: String,
        seq: Long,
        state: UploadState = UploadState.PENDING,
        priority: Long = 0L,
        nextAtMs: Long = 0L,
        createdAtMs: Long = 0L,
        sessionId: String = "s1",
    ) = UploadItem(
        key = UploadItem.keyOf(sessionId, tier, seq),
        sessionId = sessionId,
        slot = "A",
        tier = tier,
        seq = seq,
        filePath = "/tmp/$sessionId-$tier-$seq.ts",
        bytes = 100 + seq,
        sha256 = "sha-$seq",
        mediaStartServerMs = seq * 6_000,
        durationMs = 6_000,
        state = state.name,
        priority = priority,
        nextAttemptAtMs = nextAtMs,
        createdAtMs = createdAtMs,
    )

    private fun masterRequest(
        id: String,
        state: String = MasterRequest.STATE_PENDING,
        nextAtMs: Long = 0L,
        createdAtMs: Long = 0L,
    ) = MasterRequest(
        id = id,
        sessionId = "s1",
        slot = "A",
        uploadGrant = "secret-master-request-grant",
        ingestUrl = "https://k3.example",
        grantExpMs = Long.MAX_VALUE,
        seqsJson = "[0]",
        state = state,
        nextAttemptAtMs = nextAtMs,
        createdAtMs = createdAtMs,
    )

    @Test
    fun itemAndSessionFromFactoriesAndToStringRedactSecrets() {
        val segment = SegmentRecord("s1", "A", C1.TIER_MASTER, 3, File("/x/master-3.ts"), 9, "h", 7, 6_000, 180, 0, -1)
        val fromSeg = UploadItem.from(segment, nowMs = 42)
        assertEquals("s1/master/3", fromSeg.key)
        assertEquals("/x/master-3.ts", fromSeg.filePath)
        assertEquals(42L, fromSeg.createdAtMs)
        assertEquals(UploadState.PENDING, fromSeg.uploadState)

        val fallbackSession = UploadSession.from(
            RecordStart.fromJson(testRecordStartBody(grant = "not-a-jwt")),
            slot = "A",
            nowMs = 5,
        )
        assertEquals(Long.MAX_VALUE, fallbackSession.grantExpMs)
        assertEquals(listOf(C1.TIER_PROXY), fallbackSession.tiers)

        val fullGrant = testGrant("s1", listOf(C1.TIER_PROXY, C1.TIER_MASTER), 2_000)
        val fullSession = UploadSession.from(
            RecordStart.fromJson(testRecordStartBody(grant = fullGrant)),
            slot = "A",
            nowMs = 5,
        ).copy(masterGrant = "secret-master-grant")
        assertEquals(2_000_000L, fullSession.grantExpMs)
        assertEquals(listOf(C1.TIER_PROXY, C1.TIER_MASTER), fullSession.tiers)
        assertEquals(
            UploadSessionGrant(
                uploadGrant = fullGrant,
                ingestUrl = "https://k3.example",
                grantExpMs = 2_000_000L,
                grantedTiers = listOf(C1.TIER_PROXY, C1.TIER_MASTER),
                masterGrant = "secret-master-grant",
                masterIngestUrl = null,
                masterGrantExpMs = 0,
            ),
            fullSession.toGrant(),
        )

        val rendered = listOf(
            fullSession.toString(),
            masterRequest("r1").toString(),
            item(C1.TIER_PROXY, 0).toString(),
        )
        assertTrue(rendered.none { "secret" in it || fullGrant in it })
        assertTrue(rendered[0].startsWith("UploadSession(s1"))
        assertTrue(rendered[1].startsWith("MasterRequest(r1"))
        assertEquals("UploadItem(s1/proxy/0, state=PENDING, attempts=0, lastError=null)", rendered[2])
    }

    @Test
    fun storeTracksSessionsItemsMasterRequestsAndSeqs() {
        val s1 = UploadSession.from(RecordStart.fromJson(testRecordStartBody("s1")), "A", 10)
        val s2 = UploadSession.from(RecordStart.fromJson(testRecordStartBody("s2")), "B", 20)
        store.upsertSession(s1)
        store.upsertSession(s2)
        assertEquals(s1, store.session("s1"))
        assertEquals(listOf(s1, s2), store.sessions())

        store.enqueue(item(C1.TIER_PROXY, 2, state = UploadState.UPLOADING))
        store.enqueue(item(C1.TIER_PROXY, 2, state = UploadState.PENDING))
        store.enqueue(item(C1.TIER_MASTER, 1, state = UploadState.HELD))
        store.enqueue(item(C1.TIER_PROXY, 0, state = UploadState.PENDING))
        store.enqueue(item(C1.TIER_PROXY, 9, state = UploadState.PENDING, sessionId = "s2"))

        assertEquals(UploadState.UPLOADING, store.item("s1/proxy/2")!!.uploadState)
        assertEquals(
            listOf("s1/master/1", "s1/proxy/0", "s1/proxy/2"),
            store.items("s1").map { it.key },
        )

        store.upsertMasterRequest(masterRequest("r-sent", state = MasterRequest.STATE_SENT, createdAtMs = 1))
        store.upsertMasterRequest(masterRequest("r-late", nextAtMs = 50, createdAtMs = 2))
        store.upsertMasterRequest(masterRequest("r-early", nextAtMs = 10, createdAtMs = 20))
        store.upsertMasterRequest(masterRequest("r-oldest", nextAtMs = 10, createdAtMs = 5))
        assertEquals("r-oldest", store.dueMasterRequest(nowMs = 10)!!.id)
        assertEquals("r-oldest", store.masterRequest("r-oldest")!!.id)

        assertEquals(-1L, store.lastSeq("s1", C1.TIER_PROXY))
        store.commitSeq("s1", C1.TIER_PROXY, 4)
        assertEquals(4L, store.lastSeq("s1", C1.TIER_PROXY))
        assertEquals(-1L, store.lastSeq("s1", C1.TIER_MASTER))
    }

    @Test
    fun nextDueNextWakeAndActiveTotalsRespectPriorityAndState() {
        assertNull(store.nextWakeAtMs())
        store.enqueue(item(C1.TIER_PROXY, 0, state = UploadState.VERIFIED, nextAtMs = 1))
        store.enqueue(item(C1.TIER_MASTER, 0, state = UploadState.PENDING, createdAtMs = 10, nextAtMs = 50))
        store.enqueue(
            item(C1.TIER_MASTER, 1, state = UploadState.PENDING, priority = 500, nextAtMs = 60, createdAtMs = 20),
        )
        store.enqueue(
            item(C1.TIER_MASTER, 2, state = UploadState.PENDING, priority = 900, nextAtMs = 70, createdAtMs = 30),
        )
        store.enqueue(item(C1.TIER_PROXY, 1, state = UploadState.UPLOADING, createdAtMs = 40, nextAtMs = 80))

        assertEquals(50L, store.nextWakeAtMs())
        assertEquals(80L, store.nextWakeAtMs(includeMasters = false))

        store.upsertMasterRequest(masterRequest("r1", state = MasterRequest.STATE_SENT, nextAtMs = 2))
        store.upsertMasterRequest(masterRequest("r2", state = MasterRequest.STATE_PENDING, nextAtMs = 30))
        assertEquals(30L, store.nextWakeAtMs())
        assertEquals(30L, store.nextWakeAtMs(includeMasters = false))

        assertEquals("s1/proxy/1", store.nextDue(nowMs = 100)!!.key)
        store.update(store.item("s1/proxy/1")!!.copy(state = UploadState.VERIFIED.name))
        assertNull(store.nextDue(nowMs = 100, includeMasters = false))

        val drainedMasters = generateSequence { store.nextDue(nowMs = 100) }
            .map { next -> next.also { store.update(it.copy(state = UploadState.VERIFIED.name)) }.seq }
            .toList()
        assertEquals(listOf(2L, 1L, 0L), drainedMasters)

        store.enqueue(item(C1.TIER_PROXY, 2, state = UploadState.PENDING))
        store.enqueue(item(C1.TIER_PROXY, 3, state = UploadState.VERIFYING))
        store.enqueue(item(C1.TIER_MASTER, 3, state = UploadState.HELD))
        assertEquals(2, store.activeCount())
        assertEquals(205L, store.activeBytes())
    }
}
