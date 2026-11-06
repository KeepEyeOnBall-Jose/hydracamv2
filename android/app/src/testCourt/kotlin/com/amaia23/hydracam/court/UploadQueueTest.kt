package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class UploadQueueTest {
    private val store = InMemoryUploadQueueStore()

    private fun item(tier: String, seq: Long, state: UploadState, nextAtMs: Long = 0, createdAtMs: Long = 0) =
        UploadItem(
            key = UploadItem.keyOf("s1", tier, seq),
            sessionId = "s1",
            slot = "A",
            tier = tier,
            seq = seq,
            filePath = "/tmp/$tier-$seq.ts",
            bytes = 100 + seq,
            sha256 = "sha",
            mediaStartServerMs = 0,
            durationMs = 6_000,
            state = state.name,
            nextAttemptAtMs = nextAtMs,
            createdAtMs = createdAtMs,
        )

    private fun request(id: String, state: String, nextAtMs: Long) = MasterRequest(
        id = id,
        sessionId = "s1",
        slot = "A",
        uploadGrant = "secret-grant",
        ingestUrl = "https://k3.example",
        grantExpMs = Long.MAX_VALUE,
        seqsJson = "[]",
        state = state,
        nextAttemptAtMs = nextAtMs,
    )

    private fun sessionFrom(grant: String) =
        UploadSession.from(RecordStart.fromJson(recordStartBody(grant = grant)), "A", 5)

    @Test
    fun unknownStoredStateReadsAsPending() {
        assertEquals(UploadState.PENDING, UploadState.parse("bogus"))
        assertEquals(UploadState.HELD, UploadState.parse("HELD"))
        assertFalse(UploadState.CONFLICT.active)
    }

    @Test
    fun grantsWithoutUsableClaimsFallBackToProxyOnlyAndNoLocalExpiry() {
        val unreadable = sessionFrom("not-a-jwt")
        assertEquals(Long.MAX_VALUE, unreadable.grantExpMs)
        assertEquals(listOf(C1.TIER_PROXY), unreadable.tiers)

        val noTiersNoExp = sessionFrom(testGrant("s1", emptyList(), 0))
        assertEquals(Long.MAX_VALUE, noTiersNoExp.grantExpMs)
        assertEquals(listOf(C1.TIER_PROXY), noTiersNoExp.tiers)

        val full = sessionFrom(testGrant("s1", listOf(C1.TIER_PROXY, C1.TIER_MASTER), 2_000))
        assertEquals(2_000_000L, full.grantExpMs)
        assertEquals(listOf(C1.TIER_PROXY, C1.TIER_MASTER), full.tiers)
        assertEquals(5L, full.createdAtMs)
    }

    @Test
    fun toStringNeverIncludesGrants() {
        val session = sessionFrom(testGrant("s1", listOf(C1.TIER_PROXY), 2_000))
            .copy(masterGrant = "secret-master-grant")
        val rendered = listOf(session.toString(), request("r1", MasterRequest.STATE_PENDING, 0).toString())

        assertTrue(rendered.none { it.contains("secret") || it.contains(session.uploadGrant) })
        assertTrue(rendered[0].startsWith("UploadSession(s1"))
        assertTrue(rendered[1].startsWith("MasterRequest(r1"))
        assertEquals(
            "UploadItem(s1/proxy/0, state=PENDING, attempts=0, lastError=null)",
            item(C1.TIER_PROXY, 0, UploadState.PENDING).toString(),
        )
    }

    @Test
    fun itemFromSegmentCopiesTheSidecarFields() {
        val record = SegmentRecord("s1", "A", C1.TIER_MASTER, 3, File("/x/master-3.ts"), 9, "h", 7, 6_000, 180, 0, -1)

        val item = UploadItem.from(record, nowMs = 42)

        assertEquals("s1/master/3", item.key)
        assertEquals("/x/master-3.ts", item.filePath)
        assertEquals(42L, item.createdAtMs)
        assertEquals(UploadState.PENDING, item.uploadState)
    }

    @Test
    fun nextWakeIsTheEarliestActiveItemOrPendingRequest() {
        assertNull(store.nextWakeAtMs())
        store.enqueue(item(C1.TIER_PROXY, 0, UploadState.VERIFIED, nextAtMs = 1))
        store.enqueue(item(C1.TIER_MASTER, 0, UploadState.PENDING, nextAtMs = 50))
        store.enqueue(item(C1.TIER_PROXY, 1, UploadState.UPLOADING, nextAtMs = 80))
        assertEquals(50L, store.nextWakeAtMs())
        assertEquals(80L, store.nextWakeAtMs(includeMasters = false))

        store.upsertMasterRequest(request("r1", MasterRequest.STATE_SENT, 2))
        store.upsertMasterRequest(request("r2", MasterRequest.STATE_PENDING, 30))
        assertEquals(30L, store.nextWakeAtMs())
        assertEquals(30L, store.nextWakeAtMs(includeMasters = false))
    }

    @Test
    fun requestedMastersJumpTheMasterQueueButNeverAProxy() {
        // C1 1.11: proxy first; among masters the latest `masters.upload` (highest priority), then oldest.
        store.enqueue(item(C1.TIER_MASTER, 0, UploadState.PENDING, createdAtMs = 10))
        store.enqueue(item(C1.TIER_MASTER, 1, UploadState.PENDING, createdAtMs = 20).copy(priority = 500))
        store.enqueue(item(C1.TIER_MASTER, 2, UploadState.PENDING, createdAtMs = 30).copy(priority = 900))
        store.enqueue(item(C1.TIER_PROXY, 0, UploadState.PENDING, createdAtMs = 40))

        assertEquals(UploadItem.keyOf("s1", C1.TIER_PROXY, 0), store.nextDue(nowMs = 0)!!.key)
        store.update(store.item(UploadItem.keyOf("s1", C1.TIER_PROXY, 0))!!.copy(state = UploadState.VERIFIED.name))
        assertEquals(listOf(2L, 1L, 0L), drainMasters())
        assertNull(store.nextDue(nowMs = 0, includeMasters = false))
    }

    private fun drainMasters(): List<Long> = generateSequence { store.nextDue(nowMs = 0) }
        .map { next -> next.also { store.update(it.copy(state = UploadState.VERIFIED.name)) }.seq }
        .toList()

    @Test
    fun activeTotalsCountOnlyActiveItems() {
        store.enqueue(item(C1.TIER_PROXY, 0, UploadState.PENDING))
        store.enqueue(item(C1.TIER_PROXY, 1, UploadState.VERIFYING))
        store.enqueue(item(C1.TIER_PROXY, 2, UploadState.VERIFIED))
        store.enqueue(item(C1.TIER_MASTER, 0, UploadState.HELD))

        assertEquals(2, store.activeCount())
        assertEquals(201L, store.activeBytes())
    }

    @Test
    fun enqueueKeepsTheFirstRowForAKey() {
        store.enqueue(item(C1.TIER_PROXY, 0, UploadState.UPLOADING))
        store.enqueue(item(C1.TIER_PROXY, 0, UploadState.PENDING))

        assertEquals(UploadState.UPLOADING, store.item("s1/proxy/0")!!.uploadState)
    }

    @Test
    fun seqCountersStartAtMinusOne() {
        assertEquals(-1L, store.lastSeq("s1", C1.TIER_PROXY))
        store.commitSeq("s1", C1.TIER_PROXY, 4)
        assertEquals(4L, store.lastSeq("s1", C1.TIER_PROXY))
        assertEquals(-1L, store.lastSeq("s1", C1.TIER_MASTER))
    }

    @Test
    fun policyStoreKeepsTheLastSavedPolicy() {
        val policies = InMemoryUploadPolicyStore()
        assertEquals(UploadPolicy.DEFAULT, policies.load())

        val saved = UploadPolicy(maxKbps = 0, keepDays = 3)
        policies.save(saved)

        assertEquals(saved, policies.load())
    }
}
