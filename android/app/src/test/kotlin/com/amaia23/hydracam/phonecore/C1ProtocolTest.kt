package com.amaia23.hydracam.phonecore

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

class C1ProtocolTest {
    private fun policyBody(): JSONObject = JSONObject()
        .put("masterMode", "on-request")
        .put("windows", JSONArray(listOf("sat 09:00-13:00")))
        .put("maxKbps", 1_500)
        .put("keepDays", 3)

    private fun recordStartBody(ingestUrl: String = "https://k3.example"): JSONObject = JSONObject()
        .put("sessionId", "s1")
        .put("leaseId", "lease-1")
        .put("requestedBy", "staff:1")
        .put("startAtServerMs", 1_700_000_002_000L)
        .put("maxDurationS", 600)
        .put("audio", true)
        .put("uploadGrant", "secret-grant")
        .put("ingestUrl", ingestUrl)
        .put("gestures", JSONArray(listOf("marker")))

    @Test
    fun envelopeRoundTripsAndRejectsBadPayloads() {
        val sent = C1Envelope.create(C1.STATE, JSONObject().put("mode", "idle"), 42)
        val decoded = C1Envelope.decode(sent.encode())
        assertEquals(sent.id, decoded.id)
        assertEquals(C1.STATE, decoded.type)
        assertEquals(42L, decoded.ts)
        assertEquals("idle", decoded.body.getString("mode"))

        val ack = C1Envelope.ack("cmd-1", 5)
        assertEquals(C1.ACK, ack.type)
        assertEquals("cmd-1", ack.body.getString("ref"))

        val nack = C1Envelope.nack("cmd-2", C1NackCode.STORAGE_FULL, "full", 5)
        assertEquals(C1.NACK, nack.type)
        assertEquals("storage_full", nack.body.getString("code"))
        assertEquals("full", nack.body.getString("reason"))

        try {
            C1Envelope.decode("""{"v":2,"id":"a","type":"ack","ts":1}""")
            fail("Expected C1ProtocolException")
        } catch (expected: C1ProtocolException) {
            assertEquals(C1NackCode.BAD_REQUEST, expected.code)
        }
    }

    @Test
    fun contractSkewAndIdsAndUrlsValidateCleanly() {
        assertEquals(ContractSkew.SAME, C1.contractSkew("1.29"))
        assertEquals(ContractSkew.SAME, C1.contractSkew("1.29.0"))
        assertEquals(ContractSkew.OLDER, C1.contractSkew("1.28"))
        assertEquals(ContractSkew.NEWER, C1.contractSkew("1.30"))
        assertEquals(ContractSkew.UNKNOWN, C1.contractSkew("bad"))

        assertTrue(CourtIds.isSafe("0b9f6a3e-4c1d-4f7e-9a51-2d8c7e6f1a00"))
        assertFalse(CourtIds.isSafe("../escape"))
        assertTrue(CourtUrls.isAllowed("https://k3.example/base"))
        assertTrue(CourtUrls.isAllowed("http://127.0.0.1:8080"))
        assertFalse(CourtUrls.isAllowed("http://10.0.0.2:8080"))
    }

    @Test
    fun captureTargetAndAppliedCaptureSerializeCleanly() {
        val wanted = """{"lens":"ultrawide","zoomRatio":1.5,"stabilization":false,"codec":"avc","rotationDeg":0}"""
        val target = CaptureTarget.fromJson(JSONObject(wanted))
        assertEquals(CaptureTarget(CaptureTarget.LENS_ULTRAWIDE, 1.5, false, CaptureTarget.CODEC_AVC, 0), target)
        assertEquals(target, CaptureTarget.fromJson(JSONObject(target.toJson().toString())))

        val applied = AppliedCapture(
            cameraId = "2",
            lens = CaptureTarget.LENS_ULTRAWIDE,
            width = 1920,
            height = 1080,
            fps = 30,
            codec = CaptureTarget.CODEC_AVC,
            masterKbps = 12_000,
            rotationDeg = 0,
            zoomRatio = null,
            stabilization = false,
            aeLocked = true,
            afLocked = false,
            awbLocked = true,
            exposureTimeNs = 2_000_000L,
            iso = 400,
            captureResult = CaptureReadback(exposureTimeNs = 2_000_000L, sensitivity = 400),
        )
        val started = C1CoreEvents.recordingStarted("s1", 10, -12, RecordProfile.DEFAULT, applied)
        assertTrue(started.getJSONObject("applied").isNull("zoomRatio"))
        assertEquals(400, started.getJSONObject("applied").getInt("iso"))

        val stopped = C1CoreEvents.recordingStopped("s1", 4, 3, "command")
        assertEquals(4L, stopped.getJSONObject("lastSeq").getLong("proxy"))
        assertEquals(3L, stopped.getJSONObject("lastSeq").getLong("master"))

        val segment = C1CoreEvents.recordingSegment(
            SegmentRecord(
                sessionId = "s1",
                slot = "A",
                tier = C1.TIER_PROXY,
                seq = 2,
                file = File("/tmp/000002.ts"),
                bytes = 188,
                sha256 = "ab".repeat(32),
                mediaStartServerMs = 1_700_000_000_000L,
                durationMs = 6_000L,
                frames = 180,
                offsetMs = -10L,
                rttMs = 12L,
            ),
        )
        assertEquals("s1", segment.getString("sessionId"))
        assertEquals(2L, segment.getLong("seq"))
        assertEquals("ab".repeat(32), segment.getString("sha256"))

        val gap = C1CoreEvents.recordingGap(SegmentGap("s1", C1.TIER_MASTER, 42L, "no-complete-frame"))
        assertEquals("s1", gap.getString("sessionId"))
        assertEquals(C1.TIER_MASTER, gap.getString("tier"))
        assertEquals(42L, gap.getLong("fromServerMs"))
        assertEquals("no-complete-frame", gap.getString("reason"))
    }

    @Test
    fun recordCommandsAndUploadPolicyParseAndValidate() {
        val prepare = RecordPrepare.fromJson(
            JSONObject().put("sessionId", "s1").put("maxDurationS", 3_600),
        )
        assertEquals(RecordProfile.DEFAULT, prepare.profile)
        assertEquals(3_600, prepare.maxDurationS)
        assertEquals(1920 to 1080, RecordProfile.sizeFor("1080p"))
        assertEquals("2160p", RecordProfile.resFor(3840))

        val start = RecordStart.fromJson(recordStartBody())
        assertEquals("s1", start.sessionId)
        assertFalse(start.toString().contains(start.uploadGrant))

        val stop = RecordStop.fromJson(JSONObject().put("sessionId", "s1"))
        assertEquals(0L, stop.stopAtServerMs)

        val signal = SignalEmit.fromJson(JSONObject().put("signal", "rec.start").put("atServerMs", 7))
        assertNull(signal.sessionId)

        val policy = UploadPolicy.fromJson(policyBody().put("masterMode", "stream").put("masterMaxKbps", 8_000))
        assertEquals(policy, UploadPolicy.fromJson(policy.toJson()))
        assertTrue(policy.mastersMayMove(idle = false))
        assertFalse(policy.copy(masterMaxKbps = 0).mastersMayMove(idle = true))

        val preview = PreviewStart.fromJson(
            JSONObject()
                .put("publishUrl", "srt://relay.example:8890")
                .put("width", 640)
                .put("height", 360)
                .put("fps", 20)
                .put("token", "a123456789012345678901")
                .put("kbps", 700)
                .put("ttlS", 60),
        )
        assertFalse(preview.toString().contains("a123456789012345678901"))

        val masters = MastersUpload.fromJson(
            JSONObject()
                .put("sessionId", "s1")
                .put("fromServerMs", 1_000)
                .put("toServerMs", 2_000)
                .put("uploadGrant", "secret-grant")
                .put("ingestUrl", "https://k3.example"),
        )
        assertTrue(masters.covers(0, 1_001))
        assertFalse(masters.covers(2_000, 6_000))
        assertFalse(masters.toString().contains("secret-grant"))
    }
}
