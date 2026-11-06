package com.amaia23.hydracam.court

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** C1 1.7 `preview.start`: 640x360 at 20 fps, kbps 1..1000 caps the on-wire rate, ttlS > 0. */
class PreviewStartTest {
    private fun body(vararg overrides: Pair<String, Any?>): JSONObject {
        val json = JSONObject()
            .put("publishUrl", "srt://relay.example.invalid:8890")
            .put("token", "fixture-token-not-real")
            .put("width", 640)
            .put("height", 360)
            .put("fps", 20)
            .put("kbps", 700)
            .put("ttlS", 300)
        for ((name, value) in overrides) {
            if (value == null) json.remove(name) else json.put(name, value)
        }
        return json
    }

    private fun refused(vararg overrides: Pair<String, Any?>): C1ProtocolException =
        assertThrows(C1ProtocolException::class.java) { PreviewStart.fromJson(body(*overrides)) }

    @Test
    fun parsesTheContractBody() {
        val start = PreviewStart.fromJson(body())

        assertEquals("srt://relay.example.invalid:8890", start.publishUrl)
        assertEquals("fixture-token-not-real", start.token)
        assertEquals(700, start.kbps)
        assertEquals(300, start.ttlS)
    }

    @Test
    fun refusesMissingEmptyOrNonStringCredentials() {
        for (name in listOf("publishUrl", "token")) {
            assertEquals(C1NackCode.BAD_REQUEST, refused(name to null).code)
            assertEquals(C1NackCode.BAD_REQUEST, refused(name to "").code)
            assertEquals(C1NackCode.BAD_REQUEST, refused(name to 12_345).code)
        }
    }

    @Test
    fun tokenIsAnOpaqueUrlSafeString() {
        // C1 1.10.1: the token is opaque, 22..128 chars of [A-Za-z0-9_-]; no JWT dots, no spaces.
        val shortest = "a".repeat(22)
        val longest = "Z9_-".repeat(32)
        assertEquals(shortest, PreviewStart.fromJson(body("token" to shortest)).token)
        assertEquals(longest, PreviewStart.fromJson(body("token" to longest)).token)

        val bads = listOf(
            "a".repeat(21),
            "a".repeat(129),
            "Not Valid!",
            "header.payload.signature-xx",
            "tok/en".repeat(5),
        )
        for (bad in bads) {
            assertEquals(bad, C1NackCode.BAD_REQUEST, refused("token" to bad).code)
        }
    }

    @Test
    fun refusesAnythingButThe360p20Stream() {
        refused("width" to 1280)
        refused("height" to 720)
        refused("fps" to 30)
        refused("fps" to null)
        refused("width" to "640")
    }

    @Test
    fun kbpsAndTtlMustBeInRange() {
        refused("kbps" to 0)
        refused("kbps" to 1_001)
        refused("kbps" to 700.5)
        refused("kbps" to null)
        refused("ttlS" to 0)
        refused("ttlS" to -5)
        refused("ttlS" to null)
        assertEquals(1, PreviewStart.fromJson(body("kbps" to 1)).kbps)
        assertEquals(1_000, PreviewStart.fromJson(body("kbps" to 1_000)).kbps)
    }

    @Test
    fun onlySrtAndRtmpsLeaveThePhoneAndRtmpOnlyToLoopback() {
        assertTrue(PreviewUrls.isAllowed("srt://relay:8890?streamid=publish:court/c/s:device:x"))
        assertTrue(PreviewUrls.isAllowed("rtmps://relay:1936/court/c/s"))
        assertTrue(PreviewUrls.isAllowed("rtmp://127.0.0.1:1935/court/c/s"))
        assertFalse(PreviewUrls.isAllowed("rtmp://relay:1935/court/c/s"))
        assertFalse(PreviewUrls.isAllowed("https://relay/court/c/s"))
        assertFalse(PreviewUrls.isAllowed("srt://"))
        assertFalse(PreviewUrls.isAllowed("not a url"))
        assertFalse(PreviewUrls.isAllowed("srt://bad host"))
        refused("publishUrl" to "https://relay.example.invalid/whip")
    }

    @Test
    fun toStringHidesTheTokenAndStreamId() {
        val start = PreviewStart.fromJson(
            body(
                "publishUrl" to "srt://relay:8890?streamid=publish:court/c/s:device:secret-jwt-token-padding",
                "token" to "secret-jwt-token-padding",
            ),
        )

        assertFalse(start.toString(), start.toString().contains("secret-jwt"))
        assertTrue(start.toString(), start.toString().contains("kbps=700"))
    }

    @Test
    fun envelopeIdMustBeAString() {
        val error = assertThrows(C1ProtocolException::class.java) {
            C1Envelope.decode("""{"v":1,"id":12345,"type":"preview.stop","ts":1,"body":{}}""")
        }
        assertEquals(C1NackCode.BAD_REQUEST, error.code)
    }
}
