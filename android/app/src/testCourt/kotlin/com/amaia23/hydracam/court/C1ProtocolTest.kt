package com.amaia23.hydracam.court

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class C1ProtocolTest {
    @Test
    fun envelopeRoundTrips() {
        val sent = C1Envelope.create(C1.STATE, JSONObject().put("mode", "idle"), 42)
        val decoded = C1Envelope.decode(sent.encode())

        assertEquals(sent.id, decoded.id)
        assertEquals(C1.STATE, decoded.type)
        assertEquals(42L, decoded.ts)
        assertEquals("idle", decoded.body.getString("mode"))
        assertEquals(1, JSONObject(sent.encode()).getInt("v"))
    }

    @Test
    fun decodeRejectsBadEnvelopes() {
        expectProtocolError("not json")
        expectProtocolError("""{"v":2,"id":"a","type":"ack","ts":1,"body":{}}""")
        expectProtocolError("""{"v":1,"type":"ack","ts":1,"body":{}}""")
        expectProtocolError("""{"v":1,"id":"a","ts":1,"body":{}}""")
    }

    @Test
    fun decodeDefaultsMissingBody() {
        val envelope = C1Envelope.decode("""{"v":1,"id":"a","type":"record.stop","ts":1}""")
        assertEquals(0, envelope.body.length())
    }

    @Test
    fun ackAndNackCarryRef() {
        val ack = C1Envelope.ack("cmd-1", 5)
        assertEquals(C1.ACK, ack.type)
        assertEquals("cmd-1", ack.body.getString("ref"))

        val nack = C1Envelope.nack("cmd-2", C1NackCode.NOT_ROOTED, "no root", 5)
        assertEquals(C1.NACK, nack.type)
        assertEquals("cmd-2", nack.body.getString("ref"))
        assertEquals("not_rooted", nack.body.getString("code"))
        assertEquals("no root", nack.body.getString("reason"))

        assertFalse(C1Envelope.nack("cmd-3", C1NackCode.BUSY, null, 5).body.has("reason"))
    }

    @Test
    fun recordStartParsesAllFields() {
        val command = RecordStart.fromJson(recordStartBody(audio = true))

        assertEquals("s1", command.sessionId)
        assertEquals("lease-1", command.leaseId)
        assertEquals("staff:1", command.requestedBy)
        assertEquals(1_700_000_002_000L, command.startAtServerMs)
        assertEquals(600, command.maxDurationS)
        assertTrue(command.audio)
        assertEquals("https://k3.example", command.ingestUrl)
        assertEquals(listOf("marker"), command.gestures)
    }

    @Test
    fun recordStartAudioDefaultsOff() {
        val body = recordStartBody()
        body.remove("audio")
        assertFalse(RecordStart.fromJson(body).audio)
    }

    @Test
    fun recordStartNeverPrintsTheGrant() {
        val command = RecordStart.fromJson(recordStartBody())
        assertFalse(command.toString().contains(command.uploadGrant))
    }

    @Test
    fun recordStartRequiresGrantIngestAndStartTime() {
        for (field in listOf("sessionId", "uploadGrant", "ingestUrl", "startAtServerMs")) {
            val body = recordStartBody()
            body.remove(field)
            try {
                RecordStart.fromJson(body)
                fail("Expected C1ProtocolException without $field")
            } catch (expected: C1ProtocolException) {
                assertTrue(expected.message!!.contains(field))
            }
        }
        val badTime = recordStartBody().put("startAtServerMs", "soon")
        try {
            RecordStart.fromJson(badTime)
            fail("Expected C1ProtocolException for a non-numeric time")
        } catch (expected: C1ProtocolException) {
            assertTrue(expected.message!!.contains("number"))
        }
    }

    @Test
    fun jsonNullIsMissing() {
        val body = JSONObject().put("signal", "rec.start").put("atServerMs", 7).put("sessionId", JSONObject.NULL)
        assertNull(SignalEmit.fromJson(body).sessionId)
        assertNull(JSONObject().put("x", "").optStringOrNull("x"))
        try {
            RecordStop.fromJson(JSONObject().put("sessionId", JSONObject.NULL))
            fail("Expected C1ProtocolException for a null sessionId")
        } catch (expected: C1ProtocolException) {
            assertTrue(expected.message!!.contains("sessionId"))
        }
    }

    @Test
    fun prepareFallsBackToDefaultProfile() {
        val prepare = RecordPrepare.fromJson(JSONObject().put("sessionId", "s1"))
        assertEquals(RecordProfile.DEFAULT, prepare.profile)

        val custom = RecordPrepare.fromJson(
            JSONObject().put("sessionId", "s1").put("profile", JSONObject().put("fps", 60).put("segmentS", 4)),
        )
        assertEquals(60, custom.profile.fps)
        assertEquals(4, custom.profile.segmentS)
        assertEquals(RecordProfile.DEFAULT.masterKbps, custom.profile.masterKbps)
        assertEquals(1920 to 1080, RecordProfile.sizeFor("1080p"))
        assertEquals(1280 to 720, RecordProfile.sizeFor("weird"))
    }

    @Test
    fun helloCarriesRootCapsAndActiveSession() {
        val caps = CourtCaps("1080p", listOf(30, 60), hevc = false, encoders = 2, torch = true, speaker = true)
        val hello = HelloBody(
            deviceId = "dev-1",
            appVersion = "1.4.0",
            versionCode = 19,
            model = "Pixel",
            androidSdk = 34,
            rooted = false,
            courtId = "court-1",
            slot = "A",
            mountRev = 2,
            caps = caps,
            activeSessionId = null,
        ).toJson()

        assertFalse(hello.getBoolean("rooted"))
        assertTrue(hello.getJSONObject("caps").getBoolean("torch"))
        assertTrue(hello.getJSONObject("caps").getBoolean("speaker"))
        assertEquals(2, hello.getJSONObject("caps").getInt("encoders"))
        assertTrue(hello.has("activeSessionId"))
        assertTrue(hello.isNull("activeSessionId"))

        val resumed = HelloBody("d", "v", 1, "m", 34, true, "c", "A", 0, caps, "s9").toJson()
        assertEquals("s9", resumed.getString("activeSessionId"))
    }

    @Test
    fun stateCarriesChargeCap() {
        val state = StateBody(CourtMode.UPLOADING, 80, true, 85, 31.5, 1, 10, 20, -55, null).toJson()
        assertEquals("uploading", state.getString("mode"))
        assertEquals(85, state.getInt("chargeCapPct"))
        assertFalse(state.has("lastError"))
    }

    @Test
    fun recordingStoppedListsLastSeqPerTier() {
        val body = C1Events.recordingStopped("s1", lastSeqProxy = 4, lastSeqMaster = 3, reason = "command")
        assertEquals(4L, body.getJSONObject("lastSeq").getLong("proxy"))
        assertEquals(3L, body.getJSONObject("lastSeq").getLong("master"))
    }

    private fun expectProtocolError(text: String) {
        try {
            C1Envelope.decode(text)
            fail("Expected C1ProtocolException for $text")
        } catch (expected: C1ProtocolException) {
            // expected
        }
    }

    private fun rejects(block: () -> Unit) {
        try {
            block()
            fail("Expected C1ProtocolException")
        } catch (expected: C1ProtocolException) {
            // expected
        }
    }

    private fun policyBody(): JSONObject = JSONObject()
        .put("masterMode", "on-request")
        .put("windows", JSONArray(listOf("sat 09:00-13:00")))
        .put("maxKbps", 1_500)
        .put("keepDays", 3)

    @Test
    fun uploadPolicyParsesAndRoundTrips() {
        val policy = UploadPolicy.fromJson(policyBody())

        assertEquals(UploadPolicy(UploadPolicy.MODE_ON_REQUEST, listOf("sat 09:00-13:00"), 1_500, 3), policy)
        assertEquals(policy, UploadPolicy.fromJson(policy.toJson()))
        assertEquals(emptyList<String>(), UploadPolicy.fromJson(policyBody().apply { remove("windows") }).windows)
        assertEquals(0, UploadPolicy.fromJson(policyBody().put("maxKbps", 0)).maxKbps)
        assertEquals(UploadPolicy.MODE_ON_REQUEST, UploadPolicy.DEFAULT.masterMode)
        assertEquals(2_500, UploadPolicy.DEFAULT.maxKbps)
        assertEquals(7, UploadPolicy.DEFAULT.keepDays)
    }

    @Test
    fun uploadPolicyRejectsBadValues() {
        rejects { UploadPolicy.fromJson(policyBody().put("masterMode", "always")) }
        rejects { UploadPolicy.fromJson(policyBody().apply { remove("masterMode") }) }
        rejects { UploadPolicy.fromJson(policyBody().put("maxKbps", -1)) }
        rejects { UploadPolicy.fromJson(policyBody().put("maxKbps", 1.5)) }
        rejects { UploadPolicy.fromJson(policyBody().put("maxKbps", "fast")) }
        rejects { UploadPolicy.fromJson(policyBody().put("maxKbps", 3_000_000_000L)) }
        rejects { UploadPolicy.fromJson(policyBody().apply { remove("maxKbps") }) }
        rejects { UploadPolicy.fromJson(policyBody().put("keepDays", 0)) }
        rejects { UploadPolicy.fromJson(policyBody().put("keepDays", 366)) }
        rejects { UploadPolicy.fromJson(policyBody().put("windows", JSONArray(listOf(5)))) }
        rejects { UploadPolicy.fromJson(policyBody().put("windows", JSONArray(listOf(" ")))) }
    }

    private fun mastersBody(): JSONObject = JSONObject()
        .put("sessionId", "s1")
        .put("fromServerMs", 1_000)
        .put("toServerMs", 2_000)
        .put("uploadGrant", "secret-grant")
        .put("ingestUrl", "https://k3.example")

    @Test
    fun mastersUploadParsesRangeAndHidesTheGrant() {
        val request = MastersUpload.fromJson(mastersBody())

        assertEquals(MastersUpload("s1", 1_000, 2_000, "secret-grant", "https://k3.example"), request)
        assertFalse(request.toString().contains("secret-grant"))
        val whole = MastersUpload.fromJson(
            mastersBody().apply {
                remove("fromServerMs")
                remove("toServerMs")
            },
        )
        assertNull(whole.fromServerMs)
        assertTrue(whole.covers(0, 6_000))
    }

    @Test
    fun mastersUploadRangeIsHalfOpenOverlap() {
        val request = MastersUpload("s1", 1_000, 2_000, "g", "u")

        assertFalse(request.covers(0, 1_000))
        assertTrue(request.covers(0, 1_001))
        assertTrue(request.covers(1_999, 6_000))
        assertFalse(request.covers(2_000, 6_000))
        assertTrue(MastersUpload("s1", null, 2_000, "g", "u").covers(-10_000, 1))
        assertTrue(MastersUpload("s1", 1_000, null, "g", "u").covers(9_000_000, 1))
    }

    @Test
    fun mastersUploadRejectsBadValues() {
        rejects { MastersUpload.fromJson(mastersBody().put("toServerMs", 1_000)) }
        rejects { MastersUpload.fromJson(mastersBody().put("fromServerMs", "early")) }
        rejects { MastersUpload.fromJson(mastersBody().apply { remove("uploadGrant") }) }
        rejects { MastersUpload.fromJson(mastersBody().apply { remove("ingestUrl") }) }
        rejects { MastersUpload.fromJson(mastersBody().apply { remove("sessionId") }) }
    }

    @Test
    fun profileRejectsOutOfRangeValues() {
        for ((field, value) in listOf(
            "fps" to 0,
            "fps" to 1_000,
            "segmentS" to 0,
            "segmentS" to 3_600,
            "masterKbps" to 0,
            "proxyKbps" to -1,
            "fps" to "fast",
        )) {
            rejects { RecordProfile.fromJson(JSONObject().put(field, value)) }
        }
        assertEquals(1, RecordProfile.fromJson(JSONObject().put("segmentS", 1)).segmentS)
    }

    @Test
    fun recordStartRejectsBadDurationAndGestures() {
        rejects { RecordStart.fromJson(recordStartBody().put("maxDurationS", "long")) }
        rejects { RecordStart.fromJson(recordStartBody().put("maxDurationS", -1)) }
        rejects { RecordStart.fromJson(recordStartBody().put("gestures", JSONArray(listOf(1)))) }
        rejects { RecordStart.fromJson(recordStartBody().put("gestures", "marker")) }
    }

    @Test
    fun sessionIdsMustBeSafeNames() {
        for (bad in listOf("..", ".", "a/b", "../x", "a b", "x".repeat(129), "-a")) {
            rejects { RecordStart.fromJson(recordStartBody().put("sessionId", bad)) }
            rejects { RecordStop.fromJson(JSONObject().put("sessionId", bad)) }
            rejects { MastersUpload.fromJson(mastersBody().put("sessionId", bad)) }
            rejects { RecordPrepare.fromJson(JSONObject().put("sessionId", bad)) }
        }
        val uuid = "0b9f6a3e-4c1d-4f7e-9a51-2d8c7e6f1a00"
        assertEquals(uuid, RecordStart.fromJson(recordStartBody().put("sessionId", uuid)).sessionId)
        assertEquals("mock-1.2_x", RecordStop.fromJson(JSONObject().put("sessionId", "mock-1.2_x")).sessionId)
    }

    @Test
    fun ingestUrlMustBeHttpsOrLoopback() {
        for (bad in listOf("http://k3.example", "ftp://k3.example", "k3.example", "https://", "http://10.0.0.2:8080")) {
            rejects { RecordStart.fromJson(recordStartBody().put("ingestUrl", bad)) }
            rejects { MastersUpload.fromJson(mastersBody().put("ingestUrl", bad)) }
        }
        for (good in listOf(
            "https://k3.example/base",
            "http://127.0.0.1:8080",
            "http://localhost:1",
            "http://[::1]:9",
        )) {
            assertEquals(good, RecordStart.fromJson(recordStartBody().put("ingestUrl", good)).ingestUrl)
        }
        assertTrue(CourtUrls.isAllowed("HTTPS://K3.example"))
        assertFalse(CourtUrls.isAllowed("http://127.0.0.1.evil.example"))
    }
}
