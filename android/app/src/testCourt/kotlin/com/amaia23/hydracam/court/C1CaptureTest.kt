package com.amaia23.hydracam.court

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** C1 1.16 `record.prepare.body.capture` and `recording.started.body.applied`. */
class C1CaptureTest {
    private val wanted = """{"lens":"ultrawide","zoomRatio":1.5,"stabilization":false,"codec":"avc","rotationDeg":0}"""

    @Test
    fun captureTargetParsesEveryField() {
        val target = CaptureTarget.fromJson(JSONObject(wanted))

        assertEquals(CaptureTarget(CaptureTarget.LENS_ULTRAWIDE, 1.5, false, CaptureTarget.CODEC_AVC, 0), target)
    }

    @Test
    fun captureTargetRoundTripsThroughJson() {
        val target = CaptureTarget(CaptureTarget.LENS_TELE, 2.0, true, CaptureTarget.CODEC_HEVC, 180)

        assertEquals(target, CaptureTarget.fromJson(JSONObject(target.toJson().toString())))
    }

    @Test
    fun theDefaultIsTheWideLensUnzoomedUnstabilizedAvcUpright() {
        val json = CaptureTarget.DEFAULT.toJson()

        assertEquals("wide", json.getString("lens"))
        assertEquals(1.0, json.getDouble("zoomRatio"), 0.0)
        assertFalse(json.getBoolean("stabilization"))
        assertEquals("avc", json.getString("codec"))
        assertEquals(0, json.getInt("rotationDeg"))
    }

    @Test
    fun anIntegralDecimalRotationIsAccepted() {
        val target = CaptureTarget.fromJson(JSONObject(wanted).put("rotationDeg", 90.0))

        assertEquals(90, target.rotationDeg)
    }

    @Test
    fun everyMissingFieldIsABadRequestNamingIt() {
        listOf("lens", "zoomRatio", "stabilization", "codec", "rotationDeg").forEach { field ->
            val body = JSONObject(wanted).apply { remove(field) }

            assertBadRequest(field, body)
        }
    }

    @Test
    fun wrongTypesAreBadRequests() {
        assertBadRequest("lens", JSONObject(wanted).put("lens", 1))
        assertBadRequest("zoomRatio", JSONObject(wanted).put("zoomRatio", "1"))
        assertBadRequest("stabilization", JSONObject(wanted).put("stabilization", "false"))
        assertBadRequest("codec", JSONObject(wanted).put("codec", true))
        assertBadRequest("rotationDeg", JSONObject(wanted).put("rotationDeg", "0"))
    }

    @Test
    fun unknownEnumValuesAreBadRequests() {
        assertBadRequest("lens", JSONObject(wanted).put("lens", "macro"))
        assertBadRequest("codec", JSONObject(wanted).put("codec", "vp9"))
        assertBadRequest("rotationDeg", JSONObject(wanted).put("rotationDeg", 45))
        assertBadRequest("rotationDeg", JSONObject(wanted).put("rotationDeg", 90.5))
    }

    @Test
    fun aZoomRatioMustBePositiveAndFinite() {
        assertBadRequest("zoomRatio", JSONObject(wanted).put("zoomRatio", 0))
        assertBadRequest("zoomRatio", JSONObject(wanted).put("zoomRatio", -1))
        assertBadRequest("zoomRatio", JSONObject(wanted).put("zoomRatio", JSONObject.NULL))
    }

    @Test
    fun appliedCaptureWritesTheContractFields() {
        val json = applied().toJson()

        assertEquals(APPLIED_KEYS, json.keyNames())
        assertEquals("2", json.getString("cameraId"))
        assertEquals("ultrawide", json.getString("lens"))
        assertEquals(1920, json.getInt("width"))
        assertEquals(1080, json.getInt("height"))
        assertEquals(30, json.getInt("fps"))
        assertEquals("avc", json.getString("codec"))
        assertEquals(12_000, json.getInt("masterKbps"))
        assertEquals(0, json.getInt("rotationDeg"))
        assertEquals(1.0, json.getDouble("zoomRatio"), 0.0)
        assertFalse(json.getBoolean("stabilization"))
        assertTrue(json.getBoolean("aeLocked"))
        assertFalse(json.getBoolean("afLocked"))
        assertTrue(json.getBoolean("awbLocked"))
    }

    @Test
    fun appliedCaptureAddsTheShutterWhenItWasSet() {
        val json = applied().copy(exposureTimeNs = 2_000_000, iso = 400).toJson()

        assertEquals(APPLIED_KEYS + setOf("exposureTimeNs", "iso"), json.keyNames())
        assertEquals(2_000_000L, json.getLong("exposureTimeNs"))
        assertEquals(400, json.getInt("iso"))
    }

    @Test
    fun recordPrepareCarriesTheCaptureWhenK2SendsOne() {
        val body = JSONObject().put("sessionId", "s1").put("capture", JSONObject(wanted))

        assertEquals(CaptureTarget.fromJson(JSONObject(wanted)), RecordPrepare.fromJson(body).capture)
        assertNull(RecordPrepare.fromJson(JSONObject().put("sessionId", "s1")).capture)
        assertNull(RecordPrepare.fromJson(JSONObject().put("sessionId", "s1").put("capture", JSONObject.NULL)).capture)
    }

    @Test
    fun aCaptureThatIsNotAnObjectIsABadRequest() {
        val body = JSONObject().put("sessionId", "s1").put("capture", "wide")

        val error = runCatching { RecordPrepare.fromJson(body) }.exceptionOrNull() as C1ProtocolException

        assertEquals(C1NackCode.BAD_REQUEST, error.code)
        assertTrue(error.message, error.message.orEmpty().contains("capture"))
    }

    @Test
    fun recordingStartedReportsWhatWasAppliedOnlyWhenKnown() {
        val profile = RecordProfile(masterKbps = 12_000)
        val bare = C1Events.recordingStarted("s1", 10, -12, profile)
        val withApplied = C1Events.recordingStarted("s1", 10, -12, profile, applied())

        assertFalse(bare.has("applied"))
        assertEquals("2", withApplied.getJSONObject("applied").getString("cameraId"))
    }

    private fun applied() = AppliedCapture(
        cameraId = "2",
        lens = CaptureTarget.LENS_ULTRAWIDE,
        width = 1920,
        height = 1080,
        fps = 30,
        codec = CaptureTarget.CODEC_AVC,
        masterKbps = 12_000,
        rotationDeg = 0,
        zoomRatio = 1.0,
        stabilization = false,
        aeLocked = true,
        afLocked = false,
        awbLocked = true,
    )

    private fun assertBadRequest(field: String, body: JSONObject) {
        val error = runCatching { CaptureTarget.fromJson(body) }.exceptionOrNull()

        assertTrue("$field: $error", error is C1ProtocolException)
        assertEquals(C1NackCode.BAD_REQUEST, (error as C1ProtocolException).code)
        assertTrue("${error.message}", error.message.orEmpty().contains("capture.$field"))
    }

    private companion object {
        val APPLIED_KEYS = setOf(
            "cameraId", "lens", "width", "height", "fps", "codec", "masterKbps", "rotationDeg",
            "zoomRatio", "stabilization", "aeLocked", "afLocked", "awbLocked",
        )
    }
}

private fun JSONObject.keyNames(): Set<String> = keys().asSequence().toSet()
