package com.amaia23.hydracam.court

import org.json.JSONObject

/**
 * C1 1.16 `record.prepare.body.capture`: the camera K2 wants for a session. Every field is
 * required; a phone that cannot honour one nacks the prepare `unsupported` naming the field.
 */
data class CaptureTarget(
    val lens: String = LENS_WIDE,
    val zoomRatio: Double = 1.0,
    val stabilization: Boolean = false,
    val codec: String = CODEC_AVC,
    val rotationDeg: Int = 0,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("lens", lens)
        .put("zoomRatio", zoomRatio)
        .put("stabilization", stabilization)
        .put("codec", codec)
        .put("rotationDeg", rotationDeg)

    companion object {
        const val LENS_WIDE = "wide"
        const val LENS_ULTRAWIDE = "ultrawide"
        const val LENS_TELE = "tele"
        const val CODEC_AVC = "avc"
        const val CODEC_HEVC = "hevc"
        private val LENSES = setOf(LENS_WIDE, LENS_ULTRAWIDE, LENS_TELE)
        private val CODECS = setOf(CODEC_AVC, CODEC_HEVC)
        private val ROTATIONS = setOf(0, 90, 180, 270)

        /** What K2 sends when no per-court override is set: wide, 1x, unstabilized, AVC, upright. */
        val DEFAULT = CaptureTarget()

        fun fromJson(json: JSONObject): CaptureTarget = CaptureTarget(
            lens = json.captureEnum("lens", LENSES),
            zoomRatio = json.captureZoom(),
            stabilization = json.opt("stabilization") as? Boolean ?: throw bad("stabilization", "a boolean"),
            codec = json.captureEnum("codec", CODECS),
            rotationDeg = json.captureRotation(),
        )

        private fun JSONObject.captureEnum(name: String, allowed: Set<String>): String =
            (opt(name) as? String)?.takeIf { it in allowed } ?: throw bad(name, "one of $allowed")

        private fun JSONObject.captureZoom(): Double {
            val value = (opt("zoomRatio") as? Number)?.toDouble()
            if (value == null || !value.isFinite() || value <= 0.0) {
                throw bad("zoomRatio", "a positive number")
            }
            return value
        }

        private fun JSONObject.captureRotation(): Int {
            val value = (opt("rotationDeg") as? Number)?.toDouble()
            val degrees = value?.toInt()?.takeIf { it.toDouble() == value && it in ROTATIONS }
            return degrees ?: throw bad("rotationDeg", "one of $ROTATIONS")
        }

        private fun bad(field: String, expected: String) = C1ProtocolException("capture.$field must be $expected.")

        /** `record.prepare.body.capture`; absent or null means K2 predates 1.16 and sends none. */
        internal fun optional(body: JSONObject): CaptureTarget? = when (val value = body.opt("capture")) {
            null, JSONObject.NULL -> null
            is JSONObject -> fromJson(value)
            else -> throw C1ProtocolException("capture must be an object.")
        }
    }
}

/**
 * C1 1.16 `recording.started.body.applied`: what the camera and encoder actually accepted, read
 * back from the capture result and the encoder's output format. [exposureTimeNs] and [iso] are
 * sent whenever the camera reports them; contract 1.24 does not list them yet, so K2 drops them.
 */
data class AppliedCapture(
    val cameraId: String,
    val lens: String,
    val width: Int,
    val height: Int,
    val fps: Int,
    val codec: String,
    val masterKbps: Int,
    val rotationDeg: Int,
    val zoomRatio: Double,
    val stabilization: Boolean,
    val aeLocked: Boolean,
    val afLocked: Boolean,
    val awbLocked: Boolean,
    val exposureTimeNs: Long? = null,
    val iso: Int? = null,
) {
    fun toJson(): JSONObject {
        val json = JSONObject()
            .put("cameraId", cameraId)
            .put("lens", lens)
            .put("width", width)
            .put("height", height)
            .put("fps", fps)
            .put("codec", codec)
            .put("masterKbps", masterKbps)
            .put("rotationDeg", rotationDeg)
            .put("zoomRatio", zoomRatio)
            .put("stabilization", stabilization)
            .put("aeLocked", aeLocked)
            .put("afLocked", afLocked)
            .put("awbLocked", awbLocked)
        if (exposureTimeNs != null) {
            json.put("exposureTimeNs", exposureTimeNs)
        }
        if (iso != null) {
            json.put("iso", iso)
        }
        return json
    }
}
