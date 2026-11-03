package com.amaia23.hydracam.court

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The verify-restart cap: a segment K3 keeps rejecting stops retrying, until K3's manifest asks for it again. */
class C2RestartCapTest : C2StoreTestBase() {
    private fun proxy() = item(C1.TIER_PROXY, 0)

    /** Enqueues proxy 0 and fails its verification until the restart cap gives up on it. */
    private fun capped(upload: C2Uploader): SegmentRecord {
        startSession(tiers = listOf(C1.TIER_PROXY))
        val record = segment(C1.TIER_PROXY, 0)
        upload.enqueue(record)
        repeat(C2Uploader.MAX_VERIFY_RESTARTS + 1) { round ->
            server.enqueue(initCreated("u$round", 1))
            server.enqueue(partOk("e1"))
            server.enqueue(json(409, JSONObject().put("state", "failed").put("reason", "sha256-mismatch")))
            assertTrue(upload.runOnce())
            clock.now += 3_600_000
        }
        return record
    }

    /** Stops s1 and answers its manifest with proxy 0 missing. */
    private fun manifestReportsItMissing(upload: C2Uploader) {
        upload.onSessionStopped("s1", lastSeqProxy = 0, lastSeqMaster = -1)
        val missing = JSONArray().put(JSONObject().put("tier", "proxy").put("seq", 0))
        server.enqueue(json(200, JSONObject().put("state", "partial").put("missing", missing)))
        assertTrue(upload.runOnce())
    }

    @Test
    fun verifyFailuresStopAfterThreeRestarts() {
        val record = capped(uploader())

        val failed = proxy()
        assertEquals(UploadState.FAILED, failed.uploadState)
        assertEquals(C2Uploader.MAX_VERIFY_RESTARTS, failed.verifyRestarts)
        assertTrue(failed.lastError!!.contains("gave up"))
        assertTrue(record.file.isFile)
        assertEquals(listOf("s1/proxy/0 verify_failed: sha256-mismatch"), alerts)
    }

    @Test
    fun cappedSegmentIsRequeuedWhenK3ReportsItMissing() {
        val upload = uploader()
        val record = capped(upload)

        // K3's manifest still lists it missing: back in the queue with a fresh restart budget.
        manifestReportsItMissing(upload)
        val requeued = proxy()
        assertEquals(UploadState.PENDING, requeued.uploadState)
        assertEquals(0, requeued.verifyRestarts)
        assertNull(requeued.uploadId)
        assertTrue(record.file.isFile)

        // Same sha check as any upload; the file goes only once K3 verifies it.
        server.enqueue(initCreated("u9", 1))
        server.enqueue(partOk("e1"))
        server.enqueue(json(200, JSONObject().put("uploadId", "u9").put("state", "verifying")))
        assertTrue(upload.runOnce())
        assertTrue(record.file.isFile)
        clock.now += 2_000
        server.enqueue(json(200, JSONObject().put("state", "verified")))
        assertTrue(upload.runOnce())
        assertEquals(UploadState.VERIFIED, proxy().uploadState)
        assertFalse(record.file.exists())
    }

    @Test
    fun cappedSegmentWithItsFileGoneIsNotRequeued() {
        val upload = uploader()
        assertTrue(capped(upload).file.delete())

        manifestReportsItMissing(upload)

        assertEquals(UploadState.FAILED, proxy().uploadState)
        assertEquals(Long.MAX_VALUE, store.session("s1")!!.nextManifestAtMs)
    }
}
