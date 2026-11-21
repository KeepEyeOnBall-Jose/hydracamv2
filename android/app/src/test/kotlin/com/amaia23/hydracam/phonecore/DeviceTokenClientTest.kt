package com.amaia23.hydracam.phonecore

import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONException
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.util.concurrent.TimeUnit

class DeviceTokenClientTest {
    private val server = MockWebServer()
    private val http = OkHttpClient.Builder().callTimeout(5, TimeUnit.SECONDS).build()
    private val clock = FakePhoneClock()
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

    private fun tokenResponse(token: String, expiresAt: Any? = null): MockResponse {
        val body = JSONObject().put("accessToken", token)
        if (expiresAt != null) {
            body.put("expiresAt", expiresAt)
        }
        return MockResponse().setBody(body.toString())
    }

    private fun expectAuthError(rejected: Boolean, block: () -> Unit): CourtAuthException {
        try {
            block()
            fail("Expected CourtAuthException")
        } catch (error: CourtAuthException) {
            assertEquals(rejected, error.rejected)
            return error
        }
        error("Unreachable")
    }

    @Test
    fun fetchesPostsCredentialsCachesAndRefreshesAtMargin() {
        val expiresAtS = (clock.now + 10 * 60_000) / 1_000
        server.enqueue(tokenResponse("tok-1", expiresAtS))
        server.enqueue(tokenResponse("tok-2", expiresAtS + 600))
        val client = DeviceTokenClient(http, { enrollment }, clock)

        assertEquals("tok-1", client.accessToken())
        clock.now += 8 * 60_000
        assertEquals("tok-1", client.accessToken())
        // At exactly expiresAt - refreshMarginMs (9 min), cached token is no longer reused.
        clock.now += 60_000
        assertEquals("tok-2", client.accessToken())

        val firstRequest = server.takeRequest(3, TimeUnit.SECONDS)!!
        assertEquals("/device/v1/token", firstRequest.path)
        assertEquals("POST", firstRequest.method)
        val payload = JSONObject(firstRequest.body.readUtf8())
        assertEquals("dev-1", payload.getString("deviceId"))
        assertEquals("test-secret", payload.getString("secret"))
        assertEquals(2, server.requestCount)
    }

    @Test
    fun invalidateClearsCachedToken() {
        server.enqueue(tokenResponse("tok-1", "2099-01-01T00:00:00Z"))
        server.enqueue(tokenResponse("tok-2", "2099-01-01T00:00:00Z"))
        val client = DeviceTokenClient(http, { enrollment }, clock)

        assertEquals("tok-1", client.accessToken())
        assertEquals("tok-1", client.accessToken())
        client.invalidate()
        assertEquals("tok-2", client.accessToken())
        assertEquals(2, server.requestCount)
    }

    @Test
    fun rejects401And403AndUnenrolledAsRejectedAnd5xxAsTransient() {
        server.enqueue(MockResponse().setResponseCode(HttpStatus.UNAUTHORIZED))
        server.enqueue(MockResponse().setResponseCode(HttpStatus.FORBIDDEN))
        server.enqueue(MockResponse().setResponseCode(503))
        val client = DeviceTokenClient(http, { enrollment }, clock)

        expectAuthError(rejected = true) { client.accessToken() }
        expectAuthError(rejected = true) { client.accessToken() }
        expectAuthError(rejected = false) { client.accessToken() }
        expectAuthError(rejected = true) { DeviceTokenClient(http, { null }, clock).accessToken() }
    }

    @Test
    fun refusesRedirectsSoSecretNeverLeavesK2() {
        val elsewhere = MockWebServer()
        elsewhere.start()
        try {
            server.enqueue(
                MockResponse().setResponseCode(307).setHeader("Location", elsewhere.url("/steal").toString()),
            )
            server.enqueue(
                MockResponse().setResponseCode(308).setHeader("Location", elsewhere.url("/steal-2").toString()),
            )
            val client = DeviceTokenClient(http, { enrollment }, clock)

            expectAuthError(rejected = false) { client.accessToken() }
            expectAuthError(rejected = false) { client.accessToken() }
            assertEquals(0, elsewhere.requestCount)
        } finally {
            elsewhere.shutdown()
        }
    }

    @Test
    fun rejectsInvalidJsonAndMissingAccessToken() {
        server.enqueue(MockResponse().setBody("not-json"))
        server.enqueue(MockResponse().setBody(JSONObject().put("expiresAt", 1_700_000_600L).toString()))
        server.enqueue(MockResponse().setBody(JSONObject().put("accessToken", "").toString()))
        val client = DeviceTokenClient(http, { enrollment }, clock)

        val badJson = expectAuthError(rejected = false) { client.accessToken() }
        assertTrue(badJson.cause is JSONException)
        expectAuthError(rejected = false) { client.accessToken() }
        expectAuthError(rejected = false) { client.accessToken() }
    }

    @Test
    fun parseExpiresAtMsDelegatesToTokenExpiryParser() {
        val now = 1_700_000_000_000L
        assertEquals(1_700_000_600_000L, DeviceTokenClient.parseExpiresAtMs(1_700_000_600L, now))
        assertEquals(1_700_000_600_000L, DeviceTokenClient.parseExpiresAtMs(1_700_000_600_000L, now))
        assertEquals(1_700_000_000_000L, DeviceTokenClient.parseExpiresAtMs("2023-11-14T22:13:20Z", now))
        assertEquals(now + 55 * 60_000L, DeviceTokenClient.parseExpiresAtMs(null, now))
    }
}
