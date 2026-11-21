package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Test

class CourtDatabaseEntityTest {
    @Test
    fun uploadItemEntityRoundTripsDomainModel() {
        val item = UploadItem(
            key = "s1/master/4",
            sessionId = "s1",
            slot = "A",
            tier = C1.TIER_MASTER,
            seq = 4L,
            filePath = "/data/user/0/app/s1/master/000004.ts",
            bytes = 4096L,
            sha256 = "abc123",
            mediaStartServerMs = 1_700_000_024_000L,
            durationMs = 6_000L,
            state = UploadState.UPLOADING.name,
            uploadId = "up-9",
            partsJson = "[{\"n\":1,\"url\":\"https://k3.example/part/1\"}]",
            etagsJson = "{\"1\":\"etag-1\"}",
            verifyRestarts = 2,
            priority = 999L,
            attempts = 3,
            nextAttemptAtMs = 1_700_000_050_000L,
            lastError = "timeout",
            createdAtMs = 100L,
            updatedAtMs = 200L,
        )
        assertEquals(item, UploadItemEntity.fromDomain(item).toDomain())
    }

    @Test
    fun uploadSessionEntityRoundTripsDomainModel() {
        val session = UploadSession(
            sessionId = "s1",
            slot = "A",
            uploadGrant = "grant-jwt",
            ingestUrl = "https://k3.example",
            grantExpMs = 2_000_000_000L,
            tiersCsv = "proxy,master",
            stoppedAtMs = 500L,
            lastSeqProxy = 10L,
            lastSeqMaster = 9L,
            manifestState = UploadSession.MANIFEST_PARTIAL,
            manifestAttempts = 1,
            nextManifestAtMs = 600L,
            createdAtMs = 50L,
            masterGrant = "master-jwt",
            masterIngestUrl = "https://m.k3.example",
            masterGrantExpMs = 2_500_000_000L,
        )
        assertEquals(session, UploadSessionEntity.fromDomain(session).toDomain())
    }

    @Test
    fun masterRequestEntityAndSeqCounterRoundTripDomainModel() {
        val request = MasterRequest(
            id = "cmd-42",
            sessionId = "s1",
            slot = "A",
            uploadGrant = "master-jwt",
            ingestUrl = "https://m.k3.example",
            grantExpMs = 2_500_000_000L,
            seqsJson = "[0,1,4]",
            state = MasterRequest.STATE_SENT,
            attempts = 2,
            nextAttemptAtMs = 700L,
            lastError = null,
            createdAtMs = 80L,
        )
        assertEquals(request, MasterRequestEntity.fromDomain(request).toDomain())

        val counter = SeqCounter("s1", C1.TIER_PROXY, 10L)
        assertEquals(10L, counter.lastSeq)
    }
}
