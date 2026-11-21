package com.amaia23.hydracam.phonecore

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONException
import org.json.JSONObject

/** C0 `POST /device/v1/token {deviceId, secret}` -> `{accessToken, expiresAt}`, cached until expiry - 60 s. */
class DeviceTokenClient(
    http: OkHttpClient,
    private val credentials: () -> CourtEnrollment?,
    private val clock: PhoneClock = PhoneClock.SYSTEM,
    private val refreshMarginMs: Long = DEFAULT_REFRESH_MARGIN_MS,
) : AccessTokenProvider {
    /** A 307/308 would re-POST the secret to whatever host the response names. */
    private val http = http.newBuilder().followRedirects(false).followSslRedirects(false).build()
    private var cachedToken: String? = null
    private var cachedExpiresAtMs: Long = 0

    @Synchronized
    override fun accessToken(): String {
        val now = clock.nowMs()
        val cached = cachedToken
        if (cached != null && now < cachedExpiresAtMs - refreshMarginMs) {
            return cached
        }
        val enrollment = credentials() ?: throw CourtAuthException("Device is not enrolled.", rejected = true)
        val body = JSONObject()
            .put("deviceId", enrollment.deviceId)
            .put("secret", enrollment.secret)
            .toString()
            .toRequestBody(JSON_MEDIA_TYPE)
        val request = Request.Builder().url(enrollment.tokenUrl).post(body).build()
        http.newCall(request).execute().use { response ->
            if (response.code == HttpStatus.UNAUTHORIZED || response.code == HttpStatus.FORBIDDEN) {
                throw CourtAuthException("Device credential rejected (${response.code}).", rejected = true)
            }
            if (!response.isSuccessful) {
                throw CourtAuthException("Token request failed (${response.code}).", rejected = false)
            }
            val json = try {
                JSONObject(response.body?.string().orEmpty())
            } catch (error: JSONException) {
                throw CourtAuthException("Token response is not JSON.", rejected = false, error)
            }
            val token = json.optStringOrNull("accessToken")
                ?: throw CourtAuthException("Token response has no accessToken.", rejected = false)
            cachedToken = token
            cachedExpiresAtMs = parseExpiresAtMs(json.opt("expiresAt"), now)
            return token
        }
    }

    @Synchronized
    override fun invalidate() {
        cachedToken = null
        cachedExpiresAtMs = 0
    }

    companion object {
        const val DEFAULT_REFRESH_MARGIN_MS = 60_000L
        private val JSON_MEDIA_TYPE = "application/json".toMediaType()

        fun parseExpiresAtMs(value: Any?, nowMs: Long): Long = TokenExpiryParser.parseExpiresAtMs(value, nowMs)
    }
}
