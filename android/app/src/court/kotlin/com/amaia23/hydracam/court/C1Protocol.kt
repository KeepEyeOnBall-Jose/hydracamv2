package com.amaia23.hydracam.court

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.util.UUID

/** C1 v1 device ⇄ Court Cloud protocol (court-remote/01-contracts.md, C1). */
object C1 {
    const val VERSION = 1

    const val ACK = "ack"
    const val NACK = "nack"

    // Device -> Cloud
    const val HELLO = "hello"
    const val STATE = "state"
    const val CLOCK_PING = "clock.ping"
    const val RECORDING_STARTED = "recording.started"
    const val RECORDING_SEGMENT = "recording.segment"
    const val RECORDING_STOPPED = "recording.stopped"

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
    const val CONFIG_SET = "config.set"
    const val APP_UPDATE = "app.update"
    const val LOGS_UPLOAD = "logs.upload"

    const val TIER_PROXY = "proxy"
    const val TIER_MASTER = "master"
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
}

class C1ProtocolException(message: String) : Exception(message)

data class C1Envelope(
    val id: String,
    val type: String,
    val ts: Long,
    val body: JSONObject,
) {
    fun encode(): String =
        JSONObject()
            .put("v", C1.VERSION)
            .put("id", id)
            .put("type", type)
            .put("ts", ts)
            .put("body", body)
            .toString()

    companion object {
        fun create(type: String, body: JSONObject, nowMs: Long): C1Envelope =
            C1Envelope(id = UUID.randomUUID().toString(), type = type, ts = nowMs, body = body)

        fun ack(ref: String, nowMs: Long): C1Envelope =
            create(C1.ACK, JSONObject().put("ref", ref), nowMs)

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
                throw C1ProtocolException("Envelope is not a JSON object.")
            }
            val version = json.optInt("v", -1)
            if (version != C1.VERSION) {
                throw C1ProtocolException("Unsupported envelope v=$version.")
            }
            val id = json.optString("id")
            val type = json.optString("type")
            if (id.isEmpty() || type.isEmpty()) {
                throw C1ProtocolException("Envelope needs id and type.")
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
    fun toJson(): JSONObject =
        JSONObject()
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
) {
    fun toJson(): JSONObject =
        JSONObject()
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
        return json
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
    fun toJson(): JSONObject =
        JSONObject()
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
                fps = json.optInt("fps", DEFAULT.fps),
                masterKbps = json.optInt("masterKbps", DEFAULT.masterKbps),
                proxyRes = json.optString("proxyRes", DEFAULT.proxyRes),
                proxyKbps = json.optInt("proxyKbps", DEFAULT.proxyKbps),
                segmentS = json.optInt("segmentS", DEFAULT.segmentS),
            )
        }

        /** `1080p` -> 1920x1080 landscape; unknown values fall back to 720p. */
        fun sizeFor(res: String): Pair<Int, Int> =
            when (res) {
                "2160p" -> 3840 to 2160
                "1080p" -> 1920 to 1080
                else -> 1280 to 720
            }
    }
}

data class RecordPrepare(val sessionId: String, val profile: RecordProfile) {
    companion object {
        fun fromJson(body: JSONObject): RecordPrepare =
            RecordPrepare(
                sessionId = body.requireString("sessionId"),
                profile = RecordProfile.fromJson(body.optJSONObject("profile")),
            )
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
        fun fromJson(body: JSONObject): RecordStart {
            val gestures = body.optJSONArray("gestures")
            return RecordStart(
                sessionId = body.requireString("sessionId"),
                leaseId = body.optString("leaseId"),
                requestedBy = body.optString("requestedBy"),
                startAtServerMs = body.requireLong("startAtServerMs"),
                maxDurationS = body.optInt("maxDurationS", 0),
                audio = body.optBoolean("audio", false),
                uploadGrant = body.requireString("uploadGrant"),
                ingestUrl = body.requireString("ingestUrl"),
                gestures = (0 until (gestures?.length() ?: 0)).map { gestures!!.getString(it) },
            )
        }
    }
}

data class RecordStop(val sessionId: String, val stopAtServerMs: Long) {
    companion object {
        fun fromJson(body: JSONObject): RecordStop =
            RecordStop(
                sessionId = body.requireString("sessionId"),
                stopAtServerMs = body.optLong("stopAtServerMs", 0),
            )
    }
}

data class SignalEmit(val signal: String, val atServerMs: Long, val sessionId: String?) {
    companion object {
        fun fromJson(body: JSONObject): SignalEmit =
            SignalEmit(
                signal = body.requireString("signal"),
                atServerMs = body.requireLong("atServerMs"),
                sessionId = body.optStringOrNull("sessionId"),
            )
    }
}

object C1Events {
    fun recordingStarted(
        sessionId: String,
        firstFrameServerMs: Long,
        offsetMs: Long,
        profile: RecordProfile,
    ): JSONObject =
        JSONObject()
            .put("sessionId", sessionId)
            .put("firstFrameServerMs", firstFrameServerMs)
            .put("offsetMs", offsetMs)
            .put("profile", profile.toJson())

    fun recordingSegment(segment: SegmentRecord): JSONObject =
        JSONObject()
            .put("sessionId", segment.sessionId)
            .put("tier", segment.tier)
            .put("seq", segment.seq)
            .put("bytes", segment.bytes)
            .put("sha256", segment.sha256)
            .put("mediaStartServerMs", segment.mediaStartServerMs)
            .put("durationMs", segment.durationMs)
            .put("frames", segment.frames)

    fun recordingStopped(
        sessionId: String,
        lastSeqProxy: Long,
        lastSeqMaster: Long,
        reason: String,
    ): JSONObject =
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

private fun JSONObject.requireString(name: String): String =
    optStringOrNull(name) ?: throw C1ProtocolException("Missing $name.")

private fun JSONObject.requireLong(name: String): Long {
    if (!has(name) || isNull(name)) {
        throw C1ProtocolException("Missing $name.")
    }
    return try {
        getLong(name)
    } catch (error: JSONException) {
        throw C1ProtocolException("$name must be a number.")
    }
}
