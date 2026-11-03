package com.amaia23.hydracam.court

import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.ByteString.Companion.encodeUtf8
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.util.concurrent.TimeUnit

class CourtAuthTest {
    private val server = MockWebServer()
    private val http = OkHttpClient.Builder().callTimeout(5, TimeUnit.SECONDS).build()
    private val clock = FakeClock()
    private lateinit var enrollment: CourtEnrollment

    @Before
    fun setUp() {
        server.start()
        enrollment = CourtEnrollment(server.url("/").toString(), "dev-1", "test-secret", "court-1", "A", 1)
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun tokenResponse(token: String, expiresAt: Any): MockResponse =
        MockResponse().setBody(JSONObject().put("accessToken", token).put("expiresAt", expiresAt).toString())

    @Test
    fun enrollmentUrlsAndRedaction() {
        val e = CourtEnrollment("https://k2.example/", "d", "s3cret", "c", "A", 0)
        assertEquals("wss://k2.example/device/v1", e.webSocketUrl)
        assertEquals("https://k2.example/device/v1/token", e.tokenUrl)
        assertEquals("ws://k2.lan:8080/device/v1", e.copy(k2Url = "http://k2.lan:8080").webSocketUrl)
        assertFalse(e.toString().contains("s3cret"))
        assertEquals(e, CourtEnrollment.fromJson(e.toJson()))
    }

    @Test
    fun enrollmentValidation() {
        val e = CourtEnrollment("https://k2.example", "d", "s", "c", "A", 0)
        assertNull(CourtEnrollment.validate(e))
        assertNotNull(CourtEnrollment.validate(e.copy(k2Url = "k2.example")))
        assertNotNull(CourtEnrollment.validate(e.copy(k2Url = "http://k2.lan:8080")))
        assertNull(CourtEnrollment.validate(e.copy(k2Url = "http://127.0.0.1:8080")))
        assertNotNull(CourtEnrollment.validate(e.copy(secret = " ")))
        assertNotNull(CourtEnrollment.validate(e.copy(slot = "")))
    }

    @Test
    fun tokenIsCachedUntilRefreshMargin() {
        val expiresAtS = (clock.now + 10 * 60_000) / 1_000
        server.enqueue(tokenResponse("tok-1", expiresAtS))
        server.enqueue(tokenResponse("tok-2", expiresAtS + 600))
        val client = DeviceTokenClient(http, { enrollment }, clock)

        assertEquals("tok-1", client.accessToken())
        clock.now += 8 * 60_000
        assertEquals("tok-1", client.accessToken())
        clock.now += 2 * 60_000
        assertEquals("tok-2", client.accessToken())

        val request = server.takeRequest()
        assertEquals("/device/v1/token", request.path)
        assertEquals("POST", request.method)
        val body = JSONObject(request.body.readUtf8())
        assertEquals("dev-1", body.getString("deviceId"))
        assertEquals("test-secret", body.getString("secret"))
        assertEquals(2, server.requestCount)
    }

    @Test
    fun invalidateForcesNewToken() {
        server.enqueue(tokenResponse("tok-1", "2099-01-01T00:00:00Z"))
        server.enqueue(tokenResponse("tok-2", "2099-01-01T00:00:00Z"))
        val client = DeviceTokenClient(http, { enrollment }, clock)

        assertEquals("tok-1", client.accessToken())
        client.invalidate()
        assertEquals("tok-2", client.accessToken())
    }

    @Test
    fun rejectedCredentialIsFlagged() {
        server.enqueue(MockResponse().setResponseCode(401))
        server.enqueue(MockResponse().setResponseCode(503))
        val client = DeviceTokenClient(http, { enrollment }, clock)

        expectAuthError(rejected = true) { client.accessToken() }
        expectAuthError(rejected = false) { client.accessToken() }
        expectAuthError(rejected = true) { DeviceTokenClient(http, { null }, clock).accessToken() }
    }

    @Test
    fun redirectsAreNotFollowedSoTheSecretStaysWithK2() {
        val elsewhere = MockWebServer()
        elsewhere.start()
        try {
            server.enqueue(
                MockResponse().setResponseCode(307).setHeader("Location", elsewhere.url("/steal").toString()),
            )
            val client = DeviceTokenClient(http, { enrollment }, clock)

            expectAuthError(rejected = false) { client.accessToken() }
            assertEquals(0, elsewhere.requestCount)
        } finally {
            elsewhere.shutdown()
        }
    }

    @Test
    fun replacingAnEnrollmentNeedsTheCurrentSecret() {
        assertTrue(CourtEnrollment.mayReplace(null, null))
        assertTrue(CourtEnrollment.mayReplace(enrollment, "test-secret"))
        assertFalse(CourtEnrollment.mayReplace(enrollment, null))
        assertFalse(CourtEnrollment.mayReplace(enrollment, ""))
        assertFalse(CourtEnrollment.mayReplace(enrollment, "test-secreT"))
    }

    @Test
    fun expiresAtAcceptsSecondsMillisAndIso() {
        val now = 1_700_000_000_000L
        assertEquals(1_700_000_600_000L, DeviceTokenClient.parseExpiresAtMs(1_700_000_600L, now))
        assertEquals(1_700_000_600_000L, DeviceTokenClient.parseExpiresAtMs(1_700_000_600_000L, now))
        assertEquals(1_700_000_600_000L, DeviceTokenClient.parseExpiresAtMs("1700000600", now))
        assertEquals(1_700_000_000_000L, DeviceTokenClient.parseExpiresAtMs("2023-11-14T22:13:20Z", now))
        assertEquals(1_700_000_000_250L, DeviceTokenClient.parseExpiresAtMs("2023-11-14T22:13:20.250Z", now))
        assertEquals(1_700_000_000_000L, DeviceTokenClient.parseExpiresAtMs("2023-11-15T00:13:20+02:00", now))
        assertEquals(now + 55 * 60_000L, DeviceTokenClient.parseExpiresAtMs("garbage", now))
        assertEquals(now + 55 * 60_000L, DeviceTokenClient.parseExpiresAtMs(null, now))
    }

    @Test
    fun grantClaimsDecodeBase64UrlPayload() {
        val claims = UploadGrantClaims.decode(testGrant("s1", listOf("proxy", "master"), 1_700_000_600))!!
        assertEquals("s1", claims.sessionId)
        assertEquals("A", claims.slot)
        assertEquals(listOf("proxy", "master"), claims.tiers)
        assertEquals(1_700_000_600_000L, claims.expMs)

        assertNull(UploadGrantClaims.decode("not-a-jwt"))
        assertNull(UploadGrantClaims.decode("a.%%%.c"))
    }

    @Test
    fun grantPayloadWithUrlSafeCharactersDecodes() {
        // "?>" and "~~" encode to '_' and '-' in base64url; the standard alphabet would reject them.
        val payload = JSONObject().put("sid", "?>~~?>").put("tiers", org.json.JSONArray(listOf("proxy"))).put("exp", 5)
        val encoded = payload.toString().encodeUtf8().base64Url().trimEnd('=')
        assertTrue(encoded.contains('_') || encoded.contains('-'))

        val claims = UploadGrantClaims.decode("h.$encoded.s")!!
        assertEquals("?>~~?>", claims.sessionId)
        assertEquals(listOf("proxy"), claims.tiers)
    }

    private fun expectAuthError(rejected: Boolean, block: () -> Unit) {
        try {
            block()
            fail("Expected CourtAuthException")
        } catch (error: CourtAuthException) {
            assertEquals(rejected, error.rejected)
        }
    }
}
