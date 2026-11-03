package com.amaia23.hydracam.court

import okio.ByteString.Companion.encodeUtf8
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.BlockingQueue
import java.util.concurrent.TimeUnit

class FakeClock(var now: Long = 1_700_000_000_000L) : CourtClock {
    override fun nowMs(): Long = now
}

/** Unsigned test JWT; the device never verifies grant signatures. */
fun testGrant(sessionId: String, tiers: List<String>, expSeconds: Long): String {
    val header = JSONObject().put("alg", "none").toString().encodeUtf8().base64Url().trimEnd('=')
    val payload = JSONObject()
        .put("aud", "court-ingest")
        .put("sid", sessionId)
        .put("slot", "A")
        .put("tiers", JSONArray(tiers))
        .put("exp", expSeconds)
        .toString()
        .encodeUtf8()
        .base64Url()
        .trimEnd('=')
    return "$header.$payload.sig"
}

fun recordStartBody(
    sessionId: String = "s1",
    grant: String = testGrant(sessionId, listOf(C1.TIER_PROXY, C1.TIER_MASTER), 4_000_000_000L),
    ingestUrl: String = "https://k3.example",
    audio: Boolean = false,
): JSONObject =
    JSONObject()
        .put("sessionId", sessionId)
        .put("leaseId", "lease-1")
        .put("requestedBy", "staff:1")
        .put("startAtServerMs", 1_700_000_002_000L)
        .put("maxDurationS", 600)
        .put("audio", audio)
        .put("uploadGrant", grant)
        .put("ingestUrl", ingestUrl)
        .put("gestures", JSONArray(listOf("marker")))

fun <T> BlockingQueue<T>.await(timeoutMs: Long = 3_000): T =
    poll(timeoutMs, TimeUnit.MILLISECONDS) ?: throw AssertionError("Timed out after $timeoutMs ms.")
