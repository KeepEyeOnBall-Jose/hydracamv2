package com.amaia23.hydracam.court

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okio.ByteString.Companion.decodeBase64
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException
import java.text.ParseException
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/** H2 manual enrollment. The secret comes from staff `POST /internal/v1/devices` (C0). */
data class CourtEnrollment(
    val k2Url: String,
    val deviceId: String,
    val secret: String,
    val courtId: String,
    val slot: String,
    val mountRev: Int,
) {
    /** `https://k2` → `wss://k2/device/v1`. */
    val webSocketUrl: String
        get() = k2Base.replaceFirst(Regex("^http"), "ws") + "/device/v1"

    val tokenUrl: String
        get() = "$k2Base/device/v1/token"

    private val k2Base: String
        get() = k2Url.trim().trimEnd('/')

    fun toJson(): JSONObject = JSONObject()
        .put("k2Url", k2Url)
        .put("deviceId", deviceId)
        .put("secret", secret)
        .put("courtId", courtId)
        .put("slot", slot)
        .put("mountRev", mountRev)

    /** Never prints the secret. */
    override fun toString(): String =
        "CourtEnrollment(k2Url=$k2Url, deviceId=$deviceId, courtId=$courtId, slot=$slot, mountRev=$mountRev)"

    companion object {
        fun fromJson(json: JSONObject): CourtEnrollment = CourtEnrollment(
            k2Url = json.getString("k2Url"),
            deviceId = json.getString("deviceId"),
            secret = json.getString("secret"),
            courtId = json.getString("courtId"),
            slot = json.getString("slot"),
            mountRev = json.optInt("mountRev", 0),
        )

        fun validate(enrollment: CourtEnrollment): String? = when {
            !CourtUrls.isAllowed(enrollment.k2Url) -> "k2Url must be https://host (http:// only to loopback)"
            enrollment.deviceId.isBlank() -> "deviceId is required"
            enrollment.secret.isBlank() -> "secret is required"
            enrollment.courtId.isBlank() -> "courtId is required"
            enrollment.slot.isBlank() -> "slot is required"
            else -> null
        }
    }
}

/** Android impl keeps the enrollment encrypted with an AndroidKeyStore key (see KeystoreCredentialStore). */
interface CredentialStore {
    fun load(): CourtEnrollment?

    fun save(enrollment: CourtEnrollment)

    fun clear()
}

class CourtAuthException(message: String, val rejected: Boolean, cause: Throwable? = null) : IOException(message, cause)

interface AccessTokenProvider {
    /** Blocking; call off the main thread. */
    @Throws(IOException::class)
    fun accessToken(): String

    fun invalidate()
}

/** C0 `POST /device/v1/token {deviceId, secret}` → `{accessToken, expiresAt}`, cached until expiry − 60 s. */
class DeviceTokenClient(
    private val http: OkHttpClient,
    private val credentials: () -> CourtEnrollment?,
    private val clock: CourtClock = CourtClock.SYSTEM,
    private val refreshMarginMs: Long = 60_000,
) : AccessTokenProvider {
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
        private val JSON_MEDIA_TYPE = "application/json".toMediaType()
        private const val DEFAULT_LIFETIME_MS = 55 * 60_000L

        /** Epoch values below this are seconds (it is year 5138 in seconds, 1973 in ms). */
        private const val EPOCH_MS_FLOOR = 100_000_000_000L

        /** C0 leaves `expiresAt`'s type open: epoch s, epoch ms, or an ISO-8601 string. */
        fun parseExpiresAtMs(value: Any?, nowMs: Long): Long {
            val number = when (value) {
                is Number -> value.toLong()
                is String -> value.toLongOrNull()
                else -> null
            }
            return when {
                number != null -> if (number < EPOCH_MS_FLOOR) number * 1_000 else number
                value is String -> parseIsoMs(value)
                else -> null
            } ?: (nowMs + DEFAULT_LIFETIME_MS)
        }

        private fun parseIsoMs(value: String): Long? {
            for (pattern in ISO_PATTERNS) {
                val format = SimpleDateFormat(pattern, Locale.US)
                format.timeZone = TimeZone.getTimeZone("UTC")
                format.isLenient = false
                try {
                    return format.parse(value)?.time
                } catch (error: ParseException) {
                    continue
                }
            }
            return null
        }

        private val ISO_PATTERNS = listOf(
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXX",
        )
    }
}

/**
 * C0 upload grant (JWT, aud court-ingest). The device only reads `tiers` and `exp` to decide what to
 * upload and until when; K3 verifies the signature.
 */
data class UploadGrantClaims(val sessionId: String?, val slot: String?, val tiers: List<String>, val expMs: Long) {
    companion object {
        fun decode(token: String): UploadGrantClaims? {
            val payload = token.split('.').getOrNull(1)?.decodeBase64()?.utf8() ?: return null
            return try {
                val json = JSONObject(payload)
                val tiersJson = json.optJSONArray("tiers") ?: JSONArray()
                UploadGrantClaims(
                    sessionId = json.optStringOrNull("sid"),
                    slot = json.optStringOrNull("slot"),
                    tiers = (0 until tiersJson.length()).map { tiersJson.getString(it) },
                    expMs = json.optLong("exp", 0) * 1_000,
                )
            } catch (ignored: JSONException) {
                null
            }
        }
    }
}
