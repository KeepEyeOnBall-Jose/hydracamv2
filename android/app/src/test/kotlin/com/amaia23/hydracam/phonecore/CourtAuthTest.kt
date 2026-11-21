package com.amaia23.hydracam.phonecore

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.charset.StandardCharsets

class CourtAuthTest {
    private fun base64Url(text: String): String =
        java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(text.toByteArray(StandardCharsets.UTF_8))

    @Test
    fun enrollmentUrlsRedactionValidationAndSecretCheck() {
        val enrollment = CourtEnrollment("https://k2.example/", "d", "s3cret", "c", "A", 1)
        assertEquals("wss://k2.example/device/v1", enrollment.webSocketUrl)
        assertEquals("https://k2.example/device/v1/token", enrollment.tokenUrl)
        assertFalse(enrollment.toString().contains("s3cret"))
        assertEquals(enrollment, CourtEnrollment.fromJson(enrollment.toJson()))

        assertNull(CourtEnrollment.validate(enrollment))
        assertNotNull(CourtEnrollment.validate(enrollment.copy(k2Url = "http://k2.lan:8080")))
        assertNull(CourtEnrollment.validate(enrollment.copy(k2Url = "http://127.0.0.1:8080")))
        assertNotNull(CourtEnrollment.validate(enrollment.copy(deviceId = " ")))
        assertNotNull(CourtEnrollment.validate(enrollment.copy(secret = "")))

        assertTrue(CourtEnrollment.mayReplace(null, null))
        assertTrue(CourtEnrollment.mayReplace(enrollment, "s3cret"))
        assertFalse(CourtEnrollment.mayReplace(enrollment, "s3creT"))
        assertFalse(CourtEnrollment.mayReplace(enrollment, null))
    }

    @Test
    fun tokenExpiryParserHandlesSecondsMillisIsoAndFallbacks() {
        val now = 1_700_000_000_000L
        assertEquals(1_700_000_600_000L, TokenExpiryParser.parseExpiresAtMs(1_700_000_600L, now))
        assertEquals(1_700_000_600_000L, TokenExpiryParser.parseExpiresAtMs(1_700_000_600_000L, now))
        assertEquals(1_700_000_600_000L, TokenExpiryParser.parseExpiresAtMs("1700000600", now))
        assertEquals(1_700_000_000_000L, TokenExpiryParser.parseExpiresAtMs("2023-11-14T22:13:20Z", now))
        assertEquals(1_700_000_000_250L, TokenExpiryParser.parseExpiresAtMs("2023-11-14T22:13:20.250Z", now))
        assertEquals(1_700_000_000_000L, TokenExpiryParser.parseExpiresAtMs("2023-11-15T00:13:20+02:00", now))
        assertEquals(now + 55 * 60_000L, TokenExpiryParser.parseExpiresAtMs("garbage", now))
        assertEquals(now + 55 * 60_000L, TokenExpiryParser.parseExpiresAtMs(null, now))
    }

    @Test
    fun uploadGrantClaimsDecodesUrlSafeJwtPayloadWithoutOkio() {
        val payload = JSONObject()
            .put("sid", "?>~~?>")
            .put("slot", "A")
            .put("tiers", JSONArray(listOf("proxy", "master")))
            .put("exp", 1_700_000_600)
        val encoded = base64Url(payload.toString())
        assertTrue(encoded.contains('_') || encoded.contains('-'))

        val claims = UploadGrantClaims.decode("${base64Url("{}")}.$encoded.sig")!!
        assertEquals("?>~~?>", claims.sessionId)
        assertEquals("A", claims.slot)
        assertEquals(listOf("proxy", "master"), claims.tiers)
        assertEquals(1_700_000_600_000L, claims.expMs)

        val payloadBytes = payload.toString().toByteArray(StandardCharsets.UTF_8)
        val padded = java.util.Base64.getUrlEncoder().encodeToString(payloadBytes)
        assertEquals(claims, UploadGrantClaims.decode("h.$padded.s"))

        assertNull(UploadGrantClaims.decode("not-a-jwt"))
        assertNull(UploadGrantClaims.decode("a.%%%.c"))
        assertNull(UploadGrantClaims.decode("a.x.c"))
        assertNull(UploadGrantClaims.decode("a.===.c"))
        assertNull(UploadGrantClaims.decode("a.ab=.c"))
        assertNull(UploadGrantClaims.decode("a.${base64Url("not-json")}.c"))
    }
}
