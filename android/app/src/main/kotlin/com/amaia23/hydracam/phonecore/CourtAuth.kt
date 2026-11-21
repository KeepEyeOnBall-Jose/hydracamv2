package com.amaia23.hydracam.phonecore

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException
import java.security.MessageDigest
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
    /** `https://k2` -> `wss://k2/device/v1`. */
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

        /** Replacing or clearing an enrollment from the screen must prove the stored secret. */
        fun mayReplace(current: CourtEnrollment?, currentSecret: String?): Boolean = current == null ||
            MessageDigest.isEqual(current.secret.toByteArray(), currentSecret.orEmpty().toByteArray())
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

/** C0 leaves `expiresAt`'s type open: epoch s, epoch ms, or an ISO-8601 string. */
object TokenExpiryParser {
    private const val DEFAULT_LIFETIME_MS = 55 * 60_000L

    /** Epoch values below this are seconds (it is year 5138 in seconds, 1973 in ms). */
    private const val EPOCH_MS_FLOOR = 100_000_000_000L
    private val ISO_PATTERNS = listOf(
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXX",
    )

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
}

/**
 * C0 upload grant (JWT, aud court-ingest). The device only reads `tiers` and `exp` to decide what to
 * upload and until when; K3 verifies the signature.
 */
data class UploadGrantClaims(val sessionId: String?, val slot: String?, val tiers: List<String>, val expMs: Long) {
    companion object {
        fun decode(token: String): UploadGrantClaims? {
            val payload = token.split('.').getOrNull(1)?.let(Base64Url::decodeToUtf8) ?: return null
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

private object Base64Url {
    private const val BITS_PER_CHAR = 6
    private const val BITS_PER_BYTE = 8
    private const val LOWER_OFFSET = 26
    private const val DIGIT_OFFSET = 52
    private const val PLUS_OR_MINUS_VAL = 62
    private const val SLASH_OR_UNDERSCORE_VAL = 63
    private const val QUANTUM_CHARS = 4
    private const val MAX_PADDING = 2
    private const val BYTE_MASK = 0xFF

    fun decodeToUtf8(encoded: String): String? {
        val bytes = decode(encoded) ?: return null
        return String(bytes, Charsets.UTF_8)
    }

    fun decode(input: String): ByteArray? {
        var padding = 0
        var end = input.length
        while (end > 0 && input[end - 1] == '=') {
            padding += 1
            end -= 1
        }
        val invalidPadding = padding > MAX_PADDING || (padding > 0 && input.length % QUANTUM_CHARS != 0)
        if (invalidPadding || end % QUANTUM_CHARS == 1) {
            return null
        }
        val out = ByteArray((end * BITS_PER_CHAR) / BITS_PER_BYTE)
        var outIndex = 0
        var buffer = 0
        var bits = 0
        var valid = true
        for (i in 0 until end) {
            val value = sextet(input[i])
            if (value < 0) {
                valid = false
                break
            }
            buffer = (buffer shl BITS_PER_CHAR) or value
            bits += BITS_PER_CHAR
            if (bits >= BITS_PER_BYTE) {
                bits -= BITS_PER_BYTE
                out[outIndex++] = ((buffer ushr bits) and BYTE_MASK).toByte()
            }
        }
        return if (valid) out else null
    }

    private fun sextet(ch: Char): Int = when (ch) {
        in 'A'..'Z' -> ch - 'A'
        in 'a'..'z' -> ch - 'a' + LOWER_OFFSET
        in '0'..'9' -> ch - '0' + DIGIT_OFFSET
        '-', '+' -> PLUS_OR_MINUS_VAL
        '_', '/' -> SLASH_OR_UNDERSCORE_VAL
        else -> -1
    }
}
