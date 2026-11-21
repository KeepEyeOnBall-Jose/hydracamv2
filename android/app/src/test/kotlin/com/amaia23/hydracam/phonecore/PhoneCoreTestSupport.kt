package com.amaia23.hydracam.phonecore

import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.Base64
import java.util.concurrent.BlockingQueue
import java.util.concurrent.TimeUnit

internal class FakePhoneClock(var now: Long = 1_700_000_000_000L) : PhoneClock {
    override fun nowMs(): Long = now
}

internal class RecordingPhoneLogger : PhoneLogger {
    val infos = mutableListOf<String>()
    val warnings = mutableListOf<String>()

    @Synchronized
    override fun info(tag: String, message: String) {
        infos += message
    }

    @Synchronized
    override fun warn(tag: String, message: String, error: Throwable?) {
        warnings += message
    }
}

internal fun testGrant(sessionId: String, tiers: List<String>, expSeconds: Long): String {
    val encoder = Base64.getUrlEncoder().withoutPadding()
    val header = encoder.encodeToString(JSONObject().put("alg", "none").toString().toByteArray(StandardCharsets.UTF_8))
    val payloadJson = JSONObject()
        .put("aud", "court-ingest")
        .put("sid", sessionId)
        .put("slot", "A")
        .put("tiers", JSONArray(tiers))
        .put("exp", expSeconds)
        .toString()
    val payload = encoder.encodeToString(payloadJson.toByteArray(StandardCharsets.UTF_8))
    return "$header.$payload.sig"
}

internal fun testRecordStartBody(
    sessionId: String = "s1",
    grant: String = testGrant(sessionId, listOf(C1.TIER_PROXY, C1.TIER_MASTER), 4_000_000_000L),
    ingestUrl: String = "https://k3.example",
    audio: Boolean = false,
): JSONObject = JSONObject()
    .put("sessionId", sessionId)
    .put("leaseId", "lease-1")
    .put("requestedBy", "staff:1")
    .put("startAtServerMs", 1_700_000_002_000L)
    .put("maxDurationS", 600)
    .put("audio", audio)
    .put("uploadGrant", grant)
    .put("ingestUrl", ingestUrl)
    .put("gestures", JSONArray(listOf("marker")))

internal fun <T> BlockingQueue<T>.awaitReply(timeoutMs: Long = 3_000): T =
    poll(timeoutMs, TimeUnit.MILLISECONDS) ?: throw AssertionError("Timed out after $timeoutMs ms.")
