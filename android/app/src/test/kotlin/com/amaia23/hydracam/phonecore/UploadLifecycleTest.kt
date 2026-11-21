package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UploadLifecycleTest {
    @Test
    fun uploadStateActiveAndParseCoverAllEntriesAndFallback() {
        val active = UploadState.entries.filter { it.active }
        assertEquals(listOf(UploadState.PENDING, UploadState.UPLOADING, UploadState.VERIFYING), active)
        assertFalse(UploadState.VERIFIED.active)
        assertFalse(UploadState.CONFLICT.active)
        assertFalse(UploadState.FAILED.active)
        assertFalse(UploadState.HELD.active)

        assertEquals(UploadState.HELD, UploadState.parse("HELD"))
        assertEquals(UploadState.CONFLICT, UploadState.parse("CONFLICT"))
        assertEquals(UploadState.PENDING, UploadState.parse("unknown-value"))
    }

    @Test
    fun inMemoryPolicyStoreKeepsLatestSavedPolicy() {
        val store: UploadPolicyStore = InMemoryUploadPolicyStore()
        assertEquals(UploadPolicy.DEFAULT, store.load())

        val updated = UploadPolicy(
            masterMode = UploadPolicy.MODE_STREAM,
            maxKbps = 0,
            keepDays = 3,
            masterMaxKbps = 500,
        )
        store.save(updated)
        assertEquals(updated, store.load())
    }

    @Test
    fun keyAndUrlHelpersFormatExpectedPaths() {
        assertEquals("s1/proxy/7", UploadLifecycle.segmentKey("s1", C1.TIER_PROXY, 7))
        assertEquals("https://k3.example/v2/uploads", UploadGrants.ingestUrl("https://k3.example/", "/v2/uploads"))
        assertEquals(
            "https://k3.example/v2/sessions/s1/manifest",
            UploadGrants.manifestUrl("https://k3.example", "s1"),
        )
        val grant = UploadGrant("tok", "https://k3.example/", 9_000)
        assertEquals("https://k3.example/v2/uploads/u1", grant.url("/v2/uploads/u1"))
    }

    @Test
    fun grantClaimsResolveExpiryTiersAndHeldStatus() {
        assertEquals(Long.MAX_VALUE, UploadGrants.grantExpiryMs(null))
        assertEquals(Long.MAX_VALUE, UploadGrants.grantExpiryMs(UploadGrantClaims("s1", "A", emptyList(), 0)))
        val expClaim = UploadGrantClaims("s1", "A", listOf(C1.TIER_MASTER), 5_000L)
        assertEquals(5_000L, UploadGrants.grantExpiryMs(expClaim))

        assertEquals(listOf(C1.TIER_PROXY), UploadGrants.grantedTiers(null))
        assertEquals(
            listOf(C1.TIER_PROXY),
            UploadGrants.grantedTiers(UploadGrantClaims("s1", "A", emptyList(), 5_000L)),
        )
        assertEquals(
            listOf(C1.TIER_PROXY, C1.TIER_MASTER),
            UploadGrants.grantedTiers(UploadGrantClaims("s1", "A", listOf(C1.TIER_PROXY, C1.TIER_MASTER), 5_000L)),
        )
        assertEquals(listOf("proxy", "master"), UploadGrants.parseTiersCsv("proxy,,master, "))

        assertFalse(UploadGrants.isTierHeld(C1.TIER_MASTER, null))
        assertFalse(UploadGrants.isTierHeld(C1.TIER_PROXY, listOf(C1.TIER_PROXY)))
        assertTrue(UploadGrants.isTierHeld(C1.TIER_MASTER, listOf(C1.TIER_PROXY)))
    }

    @Test
    fun masterGrantProblemValidatesTiersSessionAndExpiry() {
        val valid = UploadGrantClaims("s1", "A", listOf(C1.TIER_MASTER), 2_000_000L)
        assertNull(UploadGrants.masterGrantProblem(valid, "s1", 2_000_000L, 1_000_000L))
        assertNull(UploadGrants.masterGrantProblem(null, "s1", 2_000_000L, 1_000_000L))

        val emptyTiers = UploadGrantClaims("s1", "A", emptyList(), 2_000_000L)
        assertNull(UploadGrants.masterGrantProblem(emptyTiers, "s1", 2_000_000L, 1_000_000L))

        val proxyOnly = UploadGrantClaims("s1", "A", listOf(C1.TIER_PROXY), 2_000_000L)
        assertEquals(
            "uploadGrant does not list master.",
            UploadGrants.masterGrantProblem(proxyOnly, "s1", 2_000_000L, 1_000_000L),
        )

        val wrongSession = UploadGrantClaims("s2", "A", listOf(C1.TIER_MASTER), 2_000_000L)
        assertEquals(
            "uploadGrant is for another session.",
            UploadGrants.masterGrantProblem(wrongSession, "s1", 2_000_000L, 1_000_000L),
        )

        assertEquals(
            "uploadGrant expired.",
            UploadGrants.masterGrantProblem(valid, "s1", 2_000_000L, 2_000_000L),
        )
    }

    @Test
    fun grantsForPrefersMasterGrantThenSessionGrant() {
        val sessionGrant = UploadSessionGrant(
            uploadGrant = "session-tok",
            ingestUrl = "https://session.k3",
            grantExpMs = 5_000L,
            grantedTiers = listOf(C1.TIER_PROXY),
            masterGrant = "master-tok",
            masterIngestUrl = null,
            masterGrantExpMs = 4_000L,
        )
        assertEquals(
            listOf(UploadGrant("session-tok", "https://session.k3", 5_000L)),
            UploadGrants.grantsFor(C1.TIER_PROXY, sessionGrant),
        )
        assertEquals(
            listOf(UploadGrant("master-tok", "https://session.k3", 4_000L)),
            UploadGrants.grantsFor(C1.TIER_MASTER, sessionGrant),
        )

        val bothGrants = sessionGrant.copy(
            grantedTiers = listOf(C1.TIER_PROXY, C1.TIER_MASTER),
            masterIngestUrl = "https://master.k3",
        )
        assertEquals(
            listOf(
                UploadGrant("master-tok", "https://master.k3", 4_000L),
                UploadGrant("session-tok", "https://session.k3", 5_000L),
            ),
            UploadGrants.grantsFor(C1.TIER_MASTER, bothGrants),
        )
    }

    @Test
    fun evaluateGrantEnforcesExpiryAndFilePresence() {
        val sessionGrant = UploadSessionGrant(
            uploadGrant = "session-tok",
            ingestUrl = "https://session.k3",
            grantExpMs = 5_000L,
            grantedTiers = listOf(C1.TIER_PROXY),
            masterGrant = "master-tok",
            masterIngestUrl = null,
            masterGrantExpMs = 4_000L,
        )
        val bothGrants = sessionGrant.copy(
            grantedTiers = listOf(C1.TIER_PROXY, C1.TIER_MASTER),
            masterIngestUrl = "https://master.k3",
        )

        assertEquals(
            UploadGrantCheck.Settled(UploadState.FAILED, "no_grant"),
            UploadGrants.evaluateGrant(C1.TIER_PROXY, UploadState.PENDING, true, 1_000L, null),
        )
        assertEquals(
            UploadGrantCheck.Settled(UploadState.HELD, null),
            UploadGrants.evaluateGrant(
                C1.TIER_MASTER,
                UploadState.PENDING,
                true,
                1_000L,
                sessionGrant.copy(masterGrant = null),
            ),
        )
        assertEquals(
            UploadGrantCheck.Settled(UploadState.FAILED, "grant_expired"),
            UploadGrants.evaluateGrant(C1.TIER_PROXY, UploadState.PENDING, true, 5_000L, sessionGrant),
        )
        assertEquals(
            UploadGrantCheck.Settled(UploadState.FAILED, "file_missing"),
            UploadGrants.evaluateGrant(C1.TIER_PROXY, UploadState.PENDING, false, 1_000L, sessionGrant),
        )
        assertEquals(
            UploadGrantCheck.Ready(UploadGrant("session-tok", "https://session.k3", 5_000L)),
            UploadGrants.evaluateGrant(C1.TIER_PROXY, UploadState.VERIFYING, false, 1_000L, sessionGrant),
        )
        assertEquals(
            UploadGrantCheck.Ready(UploadGrant("session-tok", "https://session.k3", 5_000L)),
            UploadGrants.evaluateGrant(C1.TIER_MASTER, UploadState.PENDING, true, 4_000L, bothGrants),
        )
    }

    @Test
    fun backoffPriorityAndQueuePredicatesFollowContractRules() {
        assertEquals(2_000L, UploadLifecycle.backoffMs(0))
        assertEquals(2_000L, UploadLifecycle.backoffMs(1))
        assertEquals(4_000L, UploadLifecycle.backoffMs(2))
        assertEquals(300_000L, UploadLifecycle.backoffMs(20))

        assertEquals(0, UploadLifecycle.tierRank(C1.TIER_PROXY))
        assertEquals(1, UploadLifecycle.tierRank(C1.TIER_MASTER))

        val keys = listOf(
            UploadPriorityKey(C1.TIER_MASTER, priority = 10, createdAtMs = 5, seq = 0),
            UploadPriorityKey(C1.TIER_MASTER, priority = 50, createdAtMs = 20, seq = 1),
            UploadPriorityKey(C1.TIER_MASTER, priority = 50, createdAtMs = 20, seq = 0),
            UploadPriorityKey(C1.TIER_PROXY, priority = 0, createdAtMs = 100, seq = 3),
        ).sorted()
        val orderedTiers = keys.map { it.tier to it.seq }
        assertEquals(
            listOf(C1.TIER_PROXY to 3L, C1.TIER_MASTER to 0L, C1.TIER_MASTER to 1L, C1.TIER_MASTER to 0L),
            orderedTiers,
        )
        assertEquals(listOf(0L, 50L, 50L, 10L), keys.map { it.priority })

        assertTrue(UploadLifecycle.isItemDue(C1.TIER_PROXY, UploadState.PENDING, 100, 100, includeMasters = false))
        assertFalse(UploadLifecycle.isItemDue(C1.TIER_MASTER, UploadState.PENDING, 100, 100, includeMasters = false))
        assertTrue(UploadLifecycle.isItemDue(C1.TIER_MASTER, UploadState.UPLOADING, 100, 200, includeMasters = true))
        assertFalse(UploadLifecycle.isItemDue(C1.TIER_PROXY, UploadState.PENDING, 101, 100, includeMasters = true))
        assertFalse(UploadLifecycle.isItemDue(C1.TIER_PROXY, UploadState.VERIFIED, 0, 100, includeMasters = true))

        assertTrue(UploadLifecycle.isItemWakeEligible(C1.TIER_PROXY, UploadState.VERIFYING, includeMasters = false))
        assertFalse(UploadLifecycle.isItemWakeEligible(C1.TIER_MASTER, UploadState.PENDING, includeMasters = false))
        assertTrue(UploadLifecycle.isItemWakeEligible(C1.TIER_MASTER, UploadState.PENDING, includeMasters = true))
        assertFalse(UploadLifecycle.isItemWakeEligible(C1.TIER_PROXY, UploadState.HELD, includeMasters = true))
    }

    @Test
    fun itemEligibilityAndManifestPoliciesRespectTerminalAndGrantStates() {
        assertTrue(UploadLifecycle.isHeldOnPhone(UploadState.HELD, verifyRestarts = 0, fileExists = true))
        assertTrue(UploadLifecycle.isHeldOnPhone(UploadState.FAILED, verifyRestarts = 2, fileExists = true))
        assertFalse(UploadLifecycle.isHeldOnPhone(UploadState.FAILED, verifyRestarts = 3, fileExists = true))
        assertFalse(UploadLifecycle.isHeldOnPhone(UploadState.VERIFIED, verifyRestarts = 0, fileExists = true))
        assertFalse(UploadLifecycle.isHeldOnPhone(UploadState.CONFLICT, verifyRestarts = 0, fileExists = true))
        assertFalse(UploadLifecycle.isHeldOnPhone(UploadState.HELD, verifyRestarts = 0, fileExists = false))

        assertTrue(UploadLifecycle.canRefill(UploadState.FAILED, fileExists = true))
        assertFalse(UploadLifecycle.canRefill(UploadState.VERIFIED, fileExists = true))
        assertFalse(UploadLifecycle.canRefill(UploadState.CONFLICT, fileExists = true))
        assertFalse(UploadLifecycle.canRefill(UploadState.HELD, fileExists = true))
        assertFalse(UploadLifecycle.canRefill(UploadState.FAILED, fileExists = false))

        assertTrue(UploadLifecycle.isSessionManifestDue(100, UploadLifecycle.MANIFEST_PARTIAL, 200, 500, 200))
        assertFalse(UploadLifecycle.isSessionManifestDue(0, null, 200, 500, 200))
        assertFalse(UploadLifecycle.isSessionManifestDue(100, UploadLifecycle.MANIFEST_COMPLETE, 200, 500, 200))
        assertFalse(UploadLifecycle.isSessionManifestDue(100, null, 201, 500, 200))
        assertFalse(UploadLifecycle.isSessionManifestDue(100, null, 200, 500, 500))

        assertTrue(
            UploadLifecycle.isGrantedProxyBlockingManifest(
                UploadState.UPLOADING,
                C1.TIER_PROXY,
                listOf(C1.TIER_PROXY),
            ),
        )
        assertFalse(
            UploadLifecycle.isGrantedProxyBlockingManifest(
                UploadState.UPLOADING,
                C1.TIER_MASTER,
                listOf(C1.TIER_PROXY, C1.TIER_MASTER),
            ),
        )
        assertFalse(
            UploadLifecycle.isGrantedProxyBlockingManifest(
                UploadState.VERIFIED,
                C1.TIER_PROXY,
                listOf(C1.TIER_PROXY),
            ),
        )
        assertFalse(
            UploadLifecycle.isGrantedProxyBlockingManifest(
                UploadState.PENDING,
                C1.TIER_PROXY,
                listOf(C1.TIER_MASTER),
            ),
        )
    }
}
