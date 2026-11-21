package com.amaia23.hydracam.phonecore

import kotlin.math.min

/** Upload lifecycle of one segment (H7). Files are deleted only on [VERIFIED]. */
enum class UploadState {
    PENDING,
    UPLOADING,
    VERIFYING,
    VERIFIED,

    /** K3 holds different bytes for the same key: the file is kept, lastError set. */
    CONFLICT,

    /** Terminal: grant expired or missing, or the file is gone. */
    FAILED,

    /** No grant lists this tier yet (masters before `masters.upload`): kept on the phone. */
    HELD,
    ;

    val active: Boolean get() = this == PENDING || this == UPLOADING || this == VERIFYING

    companion object {
        fun parse(value: String): UploadState = entries.firstOrNull { it.name == value } ?: PENDING
    }
}

/** Last applied `upload.policy` (R10). Android: SharedPreferences; tests: [InMemoryUploadPolicyStore]. */
interface UploadPolicyStore {
    fun load(): UploadPolicy

    fun save(policy: UploadPolicy)
}

class InMemoryUploadPolicyStore(private var policy: UploadPolicy = UploadPolicy.DEFAULT) : UploadPolicyStore {
    @Synchronized
    override fun load(): UploadPolicy = policy

    @Synchronized
    override fun save(policy: UploadPolicy) {
        this.policy = policy
    }
}

/** One resolved C2 upload grant (token, ingest base URL, and expiry timestamp in ms). */
data class UploadGrant(val token: String, val ingestUrl: String, val expMs: Long) {
    fun url(path: String): String = UploadGrants.ingestUrl(ingestUrl, path)
}

/** Session-level grant fields needed to evaluate upload eligibility for one tier. */
data class UploadSessionGrant(
    val uploadGrant: String,
    val ingestUrl: String,
    val grantExpMs: Long,
    val grantedTiers: List<String>,
    val masterGrant: String? = null,
    val masterIngestUrl: String? = null,
    val masterGrantExpMs: Long = 0,
)

/** Result of checking whether a queued segment has a valid, unexpired grant and local file. */
sealed class UploadGrantCheck {
    data class Ready(val grant: UploadGrant) : UploadGrantCheck()

    data class Settled(val state: UploadState, val error: String?) : UploadGrantCheck()
}

/**
 * Pure queue-ordering key for active upload items: proxy before master, then highest priority
 * queue jump (`masters.upload`), then oldest creation timestamp, then lowest sequence number.
 */
data class UploadPriorityKey(val tier: String, val priority: Long, val createdAtMs: Long, val seq: Long) :
    Comparable<UploadPriorityKey> {
    override fun compareTo(other: UploadPriorityKey): Int = COMPARATOR.compare(this, other)

    companion object {
        private val COMPARATOR = compareBy<UploadPriorityKey>(
            { UploadLifecycle.tierRank(it.tier) },
            { -it.priority },
            { it.createdAtMs },
            { it.seq },
        )
    }
}

/** Pure C2 grant-resolution, tier-eligibility, and ingest-URL policy helpers. */
object UploadGrants {
    fun ingestUrl(base: String, path: String): String = base.trimEnd('/') + path

    fun manifestUrl(base: String, sessionId: String): String = ingestUrl(base, "/v2/sessions/$sessionId/manifest")

    /** Returns claim expiry in ms, or [Long.MAX_VALUE] when claims have no readable positive expiry. */
    fun grantExpiryMs(claims: UploadGrantClaims?): Long = claims?.expMs?.takeIf { it > 0 } ?: Long.MAX_VALUE

    /** Unreadable/empty grant tiers fall back to proxy only so unlisted masters are never uploaded. */
    fun grantedTiers(claims: UploadGrantClaims?): List<String> =
        claims?.tiers?.takeIf { it.isNotEmpty() } ?: listOf(C1.TIER_PROXY)

    fun parseTiersCsv(tiersCsv: String): List<String> = tiersCsv.split(',').filter { it.isNotBlank() }

    /** True when a session exists with explicit [grantedTiers] that omit [tier]. */
    fun isTierHeld(tier: String, grantedTiers: List<String>?): Boolean = grantedTiers != null && tier !in grantedTiers

    /** Why a grant with [claims] cannot cover a `masters.upload` for [sessionId], or null when it can. */
    fun masterGrantProblem(claims: UploadGrantClaims?, sessionId: String, grantExpMs: Long, nowMs: Long): String? =
        when {
            claims != null && claims.tiers.isNotEmpty() && C1.TIER_MASTER !in claims.tiers ->
                "uploadGrant does not list master."
            claims?.sessionId != null && claims.sessionId != sessionId ->
                "uploadGrant is for another session."
            nowMs >= grantExpMs -> "uploadGrant expired."
            else -> null
        }

    /** Grants that may upload [tier], preferred first: a `masters.upload` grant, then `record.start`'s. */
    fun grantsFor(tier: String, sessionGrant: UploadSessionGrant): List<UploadGrant> {
        val grants = mutableListOf<UploadGrant>()
        val masterGrant = sessionGrant.masterGrant
        if (tier == C1.TIER_MASTER && masterGrant != null) {
            grants += UploadGrant(
                masterGrant,
                sessionGrant.masterIngestUrl ?: sessionGrant.ingestUrl,
                sessionGrant.masterGrantExpMs,
            )
        }
        if (tier in sessionGrant.grantedTiers) {
            grants += UploadGrant(sessionGrant.uploadGrant, sessionGrant.ingestUrl, sessionGrant.grantExpMs)
        }
        return grants
    }

    fun evaluateGrant(
        tier: String,
        uploadState: UploadState,
        fileExists: Boolean,
        nowMs: Long,
        sessionGrant: UploadSessionGrant?,
    ): UploadGrantCheck {
        val grants = sessionGrant?.let { grantsFor(tier, it) }.orEmpty()
        val grant = grants.firstOrNull { nowMs < it.expMs }
        return when {
            sessionGrant == null -> UploadGrantCheck.Settled(UploadState.FAILED, "no_grant")
            grants.isEmpty() -> UploadGrantCheck.Settled(UploadState.HELD, null)
            grant == null -> UploadGrantCheck.Settled(UploadState.FAILED, "grant_expired")
            uploadState != UploadState.VERIFYING && !fileExists ->
                UploadGrantCheck.Settled(UploadState.FAILED, "file_missing")
            else -> UploadGrantCheck.Ready(grant)
        }
    }
}

/**
 * Pure C2 upload lifecycle, queue priority, manifest readiness, and exponential backoff policies.
 * Keeps Room entities/DAOs and OkHttp transport out of shared `phonecore`.
 */
object UploadLifecycle {
    const val MANIFEST_COMPLETE = "complete"
    const val MANIFEST_PARTIAL = "partial"
    const val MASTER_STATE_PENDING = "pending"
    const val MASTER_STATE_SENT = "sent"
    const val MASTER_STATE_REJECTED = "rejected"
    const val MASTER_STATE_GONE = "gone"
    const val DEFAULT_BASE_BACKOFF_MS = 2_000L
    const val DEFAULT_MAX_BACKOFF_MS = 300_000L
    const val MAX_BACKOFF_SHIFT = 16
    const val MAX_VERIFY_RESTARTS = 3
    const val REASON_NOT_REQUESTED = "not-requested"

    fun segmentKey(sessionId: String, tier: String, seq: Long): String = "$sessionId/$tier/$seq"

    fun backoffMs(
        attempts: Int,
        baseBackoffMs: Long = DEFAULT_BASE_BACKOFF_MS,
        maxBackoffMs: Long = DEFAULT_MAX_BACKOFF_MS,
    ): Long {
        val shift = min((attempts - 1).coerceAtLeast(0), MAX_BACKOFF_SHIFT)
        return min(maxBackoffMs, baseBackoffMs shl shift)
    }

    fun tierRank(tier: String): Int = if (tier == C1.TIER_PROXY) 0 else 1

    fun isItemDue(
        tier: String,
        state: UploadState,
        nextAttemptAtMs: Long,
        nowMs: Long,
        includeMasters: Boolean,
    ): Boolean = state.active && nextAttemptAtMs <= nowMs && (includeMasters || tier == C1.TIER_PROXY)

    fun isItemWakeEligible(tier: String, state: UploadState, includeMasters: Boolean): Boolean =
        state.active && (includeMasters || tier == C1.TIER_PROXY)

    /** On the phone, not refused by K3 (different bytes, or verification failed past the cap). */
    fun isHeldOnPhone(
        state: UploadState,
        verifyRestarts: Int,
        fileExists: Boolean,
        maxVerifyRestarts: Int = MAX_VERIFY_RESTARTS,
    ): Boolean = state != UploadState.VERIFIED &&
        state != UploadState.CONFLICT &&
        !(state == UploadState.FAILED && verifyRestarts >= maxVerifyRestarts) &&
        fileExists

    /** Can answer a K3 `missing` entry: on the phone, granted, and K3 has not refused these bytes. */
    fun canRefill(state: UploadState, fileExists: Boolean): Boolean = state != UploadState.VERIFIED &&
        state != UploadState.CONFLICT &&
        state != UploadState.HELD &&
        fileExists

    /** Stopped, not yet complete, past its retry time, and still under its grant. */
    fun isSessionManifestDue(
        stoppedAtMs: Long,
        manifestState: String?,
        nextManifestAtMs: Long,
        grantExpMs: Long,
        nowMs: Long,
    ): Boolean = stoppedAtMs > 0 &&
        manifestState != MANIFEST_COMPLETE &&
        nextManifestAtMs <= nowMs &&
        nowMs < grantExpMs

    /** Granted proxies still active hold back the session manifest; streamed/held masters do not. */
    fun isGrantedProxyBlockingManifest(state: UploadState, tier: String, grantedTiers: List<String>): Boolean =
        state.active && tier == C1.TIER_PROXY && tier in grantedTiers
}
