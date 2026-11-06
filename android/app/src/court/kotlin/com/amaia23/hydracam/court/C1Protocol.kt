package com.amaia23.hydracam.court

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.net.URI
import java.net.URISyntaxException
import java.util.UUID

/** C1 v1 device ⇄ Court Cloud protocol (court-remote/01-contracts.md, C1). */
object C1 {
    const val VERSION = 1

    /**
     * The court-contracts version K1 implements, sent as `hello.contractVersion`. K2 sends 1.11 values
     * (`stream`, `masterMaxKbps`, `record.prepare.maxDurationS`) only to a device that declares 1.11+.
     */
    const val CONTRACT_VERSION = "1.11"

    const val ACK = "ack"
    const val NACK = "nack"

    // Device -> Cloud
    const val HELLO = "hello"
    const val STATE = "state"
    const val CLOCK_PING = "clock.ping"
    const val RECORDING_STARTED = "recording.started"
    const val RECORDING_SEGMENT = "recording.segment"
    const val RECORDING_STOPPED = "recording.stopped"
    const val RECORDING_GAP = "recording.gap"

    // Cloud -> Device
    const val CLOCK_PONG = "clock.pong"
    const val PREVIEW_START = "preview.start"
    const val PREVIEW_STOP = "preview.stop"
    const val RECORD_PREPARE = "record.prepare"
    const val RECORD_START = "record.start"
    const val RECORD_STOP = "record.stop"
    const val SIGNAL_EMIT = "signal.emit"
    const val SNAPSHOT = "snapshot"
    const val UPLOAD_POLICY = "upload.policy"
    const val MASTERS_UPLOAD = "masters.upload"
    const val CONFIG_SET = "config.set"
    const val APP_UPDATE = "app.update"
    const val LOGS_UPLOAD = "logs.upload"

    const val TIER_PROXY = "proxy"
    const val TIER_MASTER = "master"
    val TIERS = listOf(TIER_PROXY, TIER_MASTER)
}

/** Device-chosen `nack.code` values. C1 leaves codes free-form. */
object C1NackCode {
    const val NOT_ROOTED = "not_rooted"
    const val BUSY = "busy"
    const val BAD_REQUEST = "bad_request"
    const val UNSUPPORTED = "unsupported"
    const val NOT_ENROLLED = "not_enrolled"
    const val INTERNAL = "internal"
    const val TIMEOUT = "timeout"

    /** `record.start` for a session with no matching `record.prepare`: K2 must prepare first. */
    const val NOT_PREPARED = "not_prepared"

    /** 1.4: `masters.upload` for a range where the phone holds no masters. */
    const val GONE = "gone"

    /** 1.9: `masters.upload` whose `toServerMs` is not after `fromServerMs`. */
    const val BAD_RANGE = "bad_range"

    /** 1.11: `record.prepare`/`record.start` whose duration does not fit above the storage reserve. */
    const val STORAGE_FULL = "storage_full"
}

/** A command body K1 refuses; [code] is the `nack.code` it is answered with. */
class C1ProtocolException(message: String, cause: Throwable? = null, val code: String = C1NackCode.BAD_REQUEST) :
    Exception(message, cause)

data class C1Envelope(val id: String, val type: String, val ts: Long, val body: JSONObject) {
    fun encode(): String = JSONObject()
        .put("v", C1.VERSION)
        .put("id", id)
        .put("type", type)
        .put("ts", ts)
        .put("body", body)
        .toString()

    companion object {
        fun create(type: String, body: JSONObject, nowMs: Long): C1Envelope =
            C1Envelope(id = UUID.randomUUID().toString(), type = type, ts = nowMs, body = body)

        fun ack(ref: String, nowMs: Long): C1Envelope = create(C1.ACK, JSONObject().put("ref", ref), nowMs)

        fun nack(ref: String, code: String, reason: String?, nowMs: Long): C1Envelope {
            val body = JSONObject().put("ref", ref).put("code", code)
            if (reason != null) {
                body.put("reason", reason)
            }
            return create(C1.NACK, body, nowMs)
        }

        fun decode(text: String): C1Envelope {
            val json = try {
                JSONObject(text)
            } catch (error: JSONException) {
                throw C1ProtocolException("Envelope is not a JSON object.", error)
            }
            val version = json.optInt("v", -1)
            // Strict: a numeric id would be coerced to a string the cloud never sent.
            val id = json.opt("id") as? String ?: ""
            val type = json.optString("type")
            val problem = when {
                version != C1.VERSION -> "Unsupported envelope v=$version."
                id.isEmpty() || type.isEmpty() -> "Envelope needs id and type."
                else -> null
            }
            if (problem != null) {
                throw C1ProtocolException(problem)
            }
            return C1Envelope(
                id = id,
                type = type,
                ts = json.optLong("ts"),
                body = json.optJSONObject("body") ?: JSONObject(),
            )
        }
    }
}

enum class CourtMode(val wire: String) {
    IDLE("idle"),
    PREVIEWING("previewing"),
    ARMED("armed"),
    RECORDING("recording"),
    UPLOADING("uploading"),
    UPDATING("updating"),
    DEGRADED("degraded"),
    ERROR("error"),
}

data class CourtCaps(
    val maxRes: String,
    val fps: List<Int>,
    val hevc: Boolean,
    val encoders: Int,
    val torch: Boolean,
    val speaker: Boolean,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("maxRes", maxRes)
        .put("fps", JSONArray(fps))
        .put("hevc", hevc)
        .put("encoders", encoders)
        .put("torch", torch)
        .put("speaker", speaker)
}

data class HelloBody(
    val deviceId: String,
    val appVersion: String,
    val versionCode: Long,
    val model: String,
    val androidSdk: Int,
    val rooted: Boolean,
    val courtId: String,
    val slot: String,
    val mountRev: Int,
    val caps: CourtCaps,
    val activeSessionId: String?,
    val contractVersion: String = C1.CONTRACT_VERSION,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("deviceId", deviceId)
        .put("appVersion", appVersion)
        .put("versionCode", versionCode)
        .put("model", model)
        .put("androidSdk", androidSdk)
        .put("rooted", rooted)
        .put("courtId", courtId)
        .put("slot", slot)
        .put("mountRev", mountRev)
        .put("caps", caps.toJson())
        .put("activeSessionId", activeSessionId ?: JSONObject.NULL)
        .put("contractVersion", contractVersion)
}

data class StateBody(
    val mode: CourtMode,
    val batteryPct: Int,
    val charging: Boolean,
    val chargeCapPct: Int,
    val tempC: Double,
    val thermal: Int,
    val freeBytes: Long,
    val pendingUploadBytes: Long,
    val wifiRssi: Int,
    val lastError: String?,
    /** 1.11: [BLOCKED_STORAGE_FULL] while less than ten minutes fit above the reserve; else omitted. */
    val blocked: String? = null,
) {
    fun toJson(): JSONObject {
        val json = JSONObject()
            .put("mode", mode.wire)
            .put("batteryPct", batteryPct)
            .put("charging", charging)
            .put("chargeCapPct", chargeCapPct)
            .put("tempC", tempC)
            .put("thermal", thermal)
            .put("freeBytes", freeBytes)
            .put("pendingUploadBytes", pendingUploadBytes)
            .put("wifiRssi", wifiRssi)
        if (lastError != null) {
            json.put("lastError", lastError)
        }
        if (blocked != null) {
            json.put("blocked", blocked)
        }
        return json
    }

    companion object {
        const val BLOCKED_STORAGE_FULL = "storage_full"
    }
}

data class RecordProfile(
    val masterRes: String = "1080p",
    val fps: Int = 30,
    val masterKbps: Int = 8_000,
    val proxyRes: String = "720p",
    val proxyKbps: Int = 2_000,
    val segmentS: Int = 6,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("masterRes", masterRes)
        .put("fps", fps)
        .put("masterKbps", masterKbps)
        .put("proxyRes", proxyRes)
        .put("proxyKbps", proxyKbps)
        .put("segmentS", segmentS)

    companion object {
        val DEFAULT = RecordProfile()

        fun fromJson(json: JSONObject?): RecordProfile {
            if (json == null) {
                return DEFAULT
            }
            return RecordProfile(
                masterRes = json.optString("masterRes", DEFAULT.masterRes),
                fps = json.intIn("fps", FPS_RANGE) ?: DEFAULT.fps,
                masterKbps = json.intIn("masterKbps", KBPS_RANGE) ?: DEFAULT.masterKbps,
                proxyRes = json.optString("proxyRes", DEFAULT.proxyRes),
                proxyKbps = json.intIn("proxyKbps", KBPS_RANGE) ?: DEFAULT.proxyKbps,
                segmentS = json.intIn("segmentS", SEGMENT_S_RANGE) ?: DEFAULT.segmentS,
            )
        }

        private val FPS_RANGE = 1L..120L
        private val KBPS_RANGE = 100L..100_000L
        private val SEGMENT_S_RANGE = 1L..60L

        /** `1080p` -> 1920x1080 landscape; unknown values fall back to 720p. */
        fun sizeFor(res: String): Pair<Int, Int> = SIZES[res] ?: SIZES.getValue(RES_720P)

        /** Widest first. */
        private val SIZES = linkedMapOf(
            "2160p" to (3840 to 2160),
            "1080p" to (1920 to 1080),
            RES_720P to (1280 to 720),
        )
        private const val RES_720P = "720p"

        /** The largest resolution whose width fits in [width]; 720p when none does. */
        fun resFor(width: Int): String = SIZES.entries.firstOrNull { width >= it.value.first }?.key ?: RES_720P
    }
}

/** C1 `record.prepare`; 1.11 [maxDurationS] lets the phone refuse a session it cannot store. */
data class RecordPrepare(val sessionId: String, val profile: RecordProfile, val maxDurationS: Int? = null) {
    companion object {
        fun fromJson(body: JSONObject): RecordPrepare = RecordPrepare(
            sessionId = body.requireSessionId(),
            profile = RecordProfile.fromJson(body.optJSONObject("profile")),
            maxDurationS = body.intIn("maxDurationS", MAX_DURATION_RANGE),
        )

        /** At least a second, at most a day. */
        private val MAX_DURATION_RANGE = 1L..86_400L
    }
}

data class RecordStart(
    val sessionId: String,
    val leaseId: String,
    val requestedBy: String,
    val startAtServerMs: Long,
    val maxDurationS: Int,
    val audio: Boolean,
    val uploadGrant: String,
    val ingestUrl: String,
    val gestures: List<String>,
) {
    override fun toString(): String =
        "RecordStart(sessionId=$sessionId, leaseId=$leaseId, startAtServerMs=$startAtServerMs, " +
            "maxDurationS=$maxDurationS, audio=$audio, ingestUrl=$ingestUrl)"

    companion object {
        fun fromJson(body: JSONObject): RecordStart = RecordStart(
            sessionId = body.requireSessionId(),
            leaseId = body.optString("leaseId"),
            requestedBy = body.optString("requestedBy"),
            startAtServerMs = body.requireLong("startAtServerMs"),
            maxDurationS = body.intIn("maxDurationS", MAX_DURATION_RANGE) ?: 0,
            audio = body.optBoolean("audio", false),
            uploadGrant = body.requireString("uploadGrant"),
            ingestUrl = body.requireIngestUrl(),
            gestures = body.stringList("gestures"),
        )

        /** 0 means no limit; at most a day. */
        private val MAX_DURATION_RANGE = 0L..86_400L
    }
}

data class RecordStop(val sessionId: String, val stopAtServerMs: Long) {
    companion object {
        fun fromJson(body: JSONObject): RecordStop = RecordStop(
            sessionId = body.requireSessionId(),
            stopAtServerMs = body.optLong("stopAtServerMs", 0),
        )
    }
}

data class SignalEmit(val signal: String, val atServerMs: Long, val sessionId: String?) {
    companion object {
        fun fromJson(body: JSONObject): SignalEmit = SignalEmit(
            signal = body.requireString("signal"),
            atServerMs = body.requireLong("atServerMs"),
            sessionId = body.optStringOrNull("sessionId"),
        )
    }
}

/**
 * C1 1.7 `preview.start`: one 640x360 stream at 20 fps; [kbps] caps the measured on-wire rate and
 * the preview stops by itself [ttlS] seconds after the last start. [toString] hides credentials.
 */
data class PreviewStart(val publishUrl: String, val token: String, val kbps: Int, val ttlS: Long) {
    override fun toString(): String =
        "PreviewStart(publishUrl=${PreviewUrls.redact(publishUrl)}, kbps=$kbps, ttlS=$ttlS)"

    companion object {
        const val WIDTH = 640L
        const val HEIGHT = 360L
        const val FPS = 20L
        private val KBPS_RANGE = 1L..1_000L
        private val TTL_RANGE = 1L..Long.MAX_VALUE / 1_000

        /** C1 1.10.1: an opaque, URL-safe token. */
        private val TOKEN = Regex("[A-Za-z0-9_-]{22,128}")

        fun fromJson(body: JSONObject): PreviewStart {
            val publishUrl = body.requireText("publishUrl")
            expect(PreviewUrls.isAllowed(publishUrl)) {
                "publishUrl must be srt:// or rtmps:// (rtmp:// only to loopback)."
            }
            for ((name, expected) in listOf("width" to WIDTH, "height" to HEIGHT, "fps" to FPS)) {
                expect(body.requireLong(name) == expected) {
                    "preview is ${WIDTH}x$HEIGHT at $FPS fps; $name must be $expected."
                }
            }
            val token = body.requireText("token")
            expect(TOKEN.matches(token)) { "token must be 22..128 chars of [A-Za-z0-9_-]." }
            return PreviewStart(
                publishUrl = publishUrl,
                token = token,
                kbps = body.intIn("kbps", KBPS_RANGE) ?: throw C1ProtocolException("Missing kbps."),
                ttlS = body.requireLong("ttlS").also { expect(it in TTL_RANGE) { "ttlS must be positive." } },
            )
        }

        private fun expect(ok: Boolean, message: () -> String) {
            if (!ok) throw C1ProtocolException(message())
        }
    }
}

/** C1 `masters.upload` (1.4); no range means the whole session. */
data class MastersUpload(
    val sessionId: String,
    val fromServerMs: Long?,
    val toServerMs: Long?,
    val uploadGrant: String,
    val ingestUrl: String,
) {
    /** A segment is in range when it overlaps `[fromServerMs, toServerMs)`. */
    fun covers(mediaStartServerMs: Long, durationMs: Long): Boolean =
        (fromServerMs == null || mediaStartServerMs + durationMs > fromServerMs) &&
            (toServerMs == null || mediaStartServerMs < toServerMs)

    override fun toString(): String =
        "MastersUpload(sessionId=$sessionId, fromServerMs=$fromServerMs, toServerMs=$toServerMs, ingestUrl=$ingestUrl)"

    companion object {
        fun fromJson(body: JSONObject): MastersUpload {
            val request = MastersUpload(
                sessionId = body.requireSessionId(),
                fromServerMs = body.optLongOrNull("fromServerMs"),
                toServerMs = body.optLongOrNull("toServerMs"),
                uploadGrant = body.requireString("uploadGrant"),
                ingestUrl = body.requireIngestUrl(),
            )
            if (request.fromServerMs != null && request.toServerMs != null &&
                request.fromServerMs >= request.toServerMs
            ) {
                throw C1ProtocolException("fromServerMs must be before toServerMs.", code = C1NackCode.BAD_RANGE)
            }
            return request
        }
    }
}

/**
 * C1 `upload.policy` (R10). `maxKbps` 0 means unlimited. 1.11 [MODE_STREAM] moves masters during
 * and after recording, capped by [masterMaxKbps] when set (absent: no master-only cap). A
 * [masterMaxKbps] of 0 holds masters in every mode (1.11 center first: K2 holds the side slots
 * until the center slot's masters are complete, then re-sends the policy with a cap).
 * [keepDays] is kept for the wire only: the phone never deletes a segment K3 has not verified.
 */
data class UploadPolicy(
    val masterMode: String = MODE_ON_REQUEST,
    val windows: List<String> = emptyList(),
    val maxKbps: Int = 2_500,
    val keepDays: Int = 7,
    val masterMaxKbps: Int? = null,
) {
    fun toJson(): JSONObject {
        val json = JSONObject()
            .put("masterMode", masterMode)
            .put("windows", JSONArray(windows))
            .put("maxKbps", maxKbps)
            .put("keepDays", keepDays)
        if (masterMaxKbps != null) {
            json.put("masterMaxKbps", masterMaxKbps)
        }
        return json
    }

    /**
     * Masters move while idle in every mode; only [MODE_STREAM] moves them while recording. A
     * [masterMaxKbps] of 0 holds them either way.
     */
    fun mastersMayMove(idle: Boolean): Boolean = masterMaxKbps != 0 && (masterMode == MODE_STREAM || idle)

    companion object {
        const val MODE_NEVER = "never"
        const val MODE_ON_REQUEST = "on-request"
        const val MODE_WINDOW = "window"
        const val MODE_STREAM = "stream"
        private val MODES = setOf(MODE_NEVER, MODE_ON_REQUEST, MODE_WINDOW, MODE_STREAM)

        val DEFAULT = UploadPolicy()

        fun fromJson(body: JSONObject): UploadPolicy {
            val masterMode = body.requireString("masterMode")
            val windowsJson = body.optJSONArray("windows") ?: JSONArray()
            val windows = (0 until windowsJson.length()).mapNotNull { index ->
                (windowsJson.get(index) as? String)?.takeIf { it.isNotBlank() }
            }
            val maxKbps = body.requireLong("maxKbps")
            val keepDays = body.requireLong("keepDays")
            val masterMaxKbps = body.optLongOrNull("masterMaxKbps")
            val problem = when {
                masterMode !in MODES -> "Unknown masterMode $masterMode."
                windows.size != windowsJson.length() -> "windows must be non-empty strings."
                maxKbps !in 0..Int.MAX_VALUE.toLong() -> "maxKbps must be >= 0."
                keepDays !in 1..MAX_KEEP_DAYS -> "keepDays must be 1..$MAX_KEEP_DAYS."
                masterMaxKbps != null && masterMaxKbps !in 0..Int.MAX_VALUE.toLong() -> "masterMaxKbps must be >= 0."
                else -> null
            }
            if (problem != null) {
                throw C1ProtocolException(problem)
            }
            return UploadPolicy(masterMode, windows, maxKbps.toInt(), keepDays.toInt(), masterMaxKbps?.toInt())
        }

        private const val MAX_KEEP_DAYS = 365L
    }
}

object C1Events {
    fun recordingStarted(
        sessionId: String,
        firstFrameServerMs: Long,
        offsetMs: Long,
        profile: RecordProfile,
    ): JSONObject = JSONObject()
        .put("sessionId", sessionId)
        .put("firstFrameServerMs", firstFrameServerMs)
        .put("offsetMs", offsetMs)
        .put("profile", profile.toJson())

    fun recordingSegment(segment: SegmentRecord): JSONObject = JSONObject()
        .put("sessionId", segment.sessionId)
        .put("tier", segment.tier)
        .put("seq", segment.seq)
        .put("bytes", segment.bytes)
        .put("sha256", segment.sha256)
        .put("mediaStartServerMs", segment.mediaStartServerMs)
        .put("durationMs", segment.durationMs)
        .put("frames", segment.frames)

    /** A crash lost one tier's media from `fromServerMs` up to the next `recording.segment`. */
    fun recordingGap(gap: SegmentGap): JSONObject = JSONObject()
        .put("sessionId", gap.sessionId)
        .put("tier", gap.tier)
        .put("fromServerMs", gap.fromServerMs)
        .put("reason", gap.reason)

    fun recordingStopped(sessionId: String, lastSeqProxy: Long, lastSeqMaster: Long, reason: String): JSONObject =
        JSONObject()
            .put("sessionId", sessionId)
            .put(
                "lastSeq",
                JSONObject().put(C1.TIER_PROXY, lastSeqProxy).put(C1.TIER_MASTER, lastSeqMaster),
            )
            .put("reason", reason)
}

/** `optString` returns "null" for JSON null on Android; normalize to Kotlin null. */
internal fun JSONObject.optStringOrNull(name: String): String? {
    if (!has(name) || isNull(name)) {
        return null
    }
    return optString(name).ifEmpty { null }
}

internal fun JSONObject.optLongOrNull(name: String): Long? {
    if (!has(name) || isNull(name)) {
        return null
    }
    val value = get(name)
    if (value !is Number || value.toDouble() != value.toLong().toDouble()) {
        throw C1ProtocolException("$name must be an integer number.")
    }
    return value.toLong()
}

/** A required non-empty string; unlike [requireString], numbers are not coerced to text. */
private fun JSONObject.requireText(name: String): String =
    (opt(name) as? String)?.ifEmpty { null } ?: throw C1ProtocolException("$name must be a non-empty string.")

private fun JSONObject.requireString(name: String): String =
    optStringOrNull(name) ?: throw C1ProtocolException("Missing $name.")

private fun JSONObject.requireLong(name: String): Long =
    optLongOrNull(name) ?: throw C1ProtocolException("Missing $name.")

private fun JSONObject.requireSessionId(): String {
    val value = requireString("sessionId")
    if (!CourtIds.isSafe(value)) {
        throw C1ProtocolException("sessionId must match ${CourtIds.PATTERN}.")
    }
    return value
}

private fun JSONObject.requireIngestUrl(): String {
    val value = requireString("ingestUrl")
    if (!CourtUrls.isAllowed(value)) {
        throw C1ProtocolException("ingestUrl must be https:// (or http:// to loopback).")
    }
    return value
}

/** An optional integer field that must lie in [range] when present. */
private fun JSONObject.intIn(name: String, range: LongRange): Int? {
    val value = optLongOrNull(name) ?: return null
    if (value !in range) {
        throw C1ProtocolException("$name must be in $range.")
    }
    return value.toInt()
}

/** An optional array whose elements must all be strings. */
private fun JSONObject.stringList(name: String): List<String> {
    if (!has(name) || isNull(name)) {
        return emptyList()
    }
    val array = opt(name) as? JSONArray ?: throw C1ProtocolException("$name must be an array.")
    return (0 until array.length()).map { index ->
        array.get(index) as? String ?: throw C1ProtocolException("$name must hold strings.")
    }
}

/** K2 ids become directory names and URL path segments, so only plain names are accepted. */
object CourtIds {
    const val PATTERN = "[A-Za-z0-9][A-Za-z0-9._-]{0,127}"
    private val REGEX = Regex(PATTERN)

    fun isSafe(value: String): Boolean = REGEX.matches(value)
}

/**
 * Credentials only travel over TLS; cleartext is allowed to loopback (tests, `adb reverse`), as in
 * the network config.
 */
object CourtUrls {
    private val LOOPBACK = setOf("localhost", "127.0.0.1", "[::1]", "::1")

    fun isAllowed(url: String): Boolean {
        val uri = try {
            URI(url.trim())
        } catch (ignored: URISyntaxException) {
            null
        }
        val host = uri?.host?.lowercase() ?: return false
        return when (uri.scheme?.lowercase()) {
            "https" -> true
            "http" -> host in LOOPBACK
            else -> false
        }
    }
}
