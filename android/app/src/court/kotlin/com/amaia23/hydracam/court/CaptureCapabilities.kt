package com.amaia23.hydracam.court

import org.json.JSONObject

/** A master mode supported together with the court's 720p proxy and GPU-shared preview. */
data class CaptureProfileCapability(
    val masterRes: String,
    val fps: Int,
    val lens: String,
    val codec: String,
    val maxMasterKbps: Int,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("masterRes", masterRes)
        .put("fps", fps)
        .put("lens", lens)
        .put("codec", codec)
        .put("maxMasterKbps", maxMasterKbps)
}

/** Fail closed when either the camera's size-specific frame timing or encoder support is unknown. */
object CaptureCapabilities {
    private val FRAME_RATES = listOf(30, 60)
    private const val NANOS_PER_SECOND = 1_000_000_000L
    private const val PROXY_KBPS = 2_000
    private const val MAX_KBPS = 100_000

    fun profiles(
        lenses: List<LensInfo>,
        minFrameDurationNs: (String, Pair<Int, Int>) -> Long?,
        encoderMaxKbps: (Pair<Int, Int>, Int) -> Int?,
    ): List<CaptureProfileCapability> {
        val rates = FRAME_RATES.filter { fps -> lenses.any { lens -> lens.aeFpsRanges.any { it.last == fps } } }
        return rates.flatMap { fps -> profilesAtRate(lenses, minFrameDurationNs, encoderMaxKbps, fps) }
    }

    private fun profilesAtRate(
        lenses: List<LensInfo>,
        minFrameDurationNs: (String, Pair<Int, Int>) -> Long?,
        encoderMaxKbps: (Pair<Int, Int>, Int) -> Int?,
        fps: Int,
    ): List<CaptureProfileCapability> {
        val proxy = RecordProfile.sizeFor("720p")
        if ((encoderMaxKbps(proxy, fps) ?: 0) < PROXY_KBPS) return emptyList()
        // Camera2 reports integer nanoseconds; allow rounding up by less than one nanosecond.
        val frameNs = (NANOS_PER_SECOND + fps - 1) / fps
        return listOf("wide", "ultrawide", "tele").flatMap { role ->
            listOf("2160p", "1080p", "720p").mapNotNull { resolution ->
                val profile = RecordProfile(masterRes = resolution, fps = fps)
                val plan = CapturePlanner.plan(
                    profile,
                    CaptureTarget(lens = role),
                    lenses,
                    minFrameDurationNs = minFrameDurationNs,
                ) as? CapturePlan ?: return@mapNotNull null
                val sizes = listOf(plan.masterCameraSize, proxy)
                val timed = sizes.all { size ->
                    val duration = minFrameDurationNs(plan.cameraId, size)
                    duration != null && duration > 0 && duration <= frameNs
                }
                val maxKbps = encoderMaxKbps(plan.masterSize, fps)?.coerceAtMost(MAX_KBPS)
                if (!timed || maxKbps == null || maxKbps < PROXY_KBPS) return@mapNotNull null
                CaptureProfileCapability(resolution, fps, role, CaptureTarget.CODEC_AVC, maxKbps)
            }
        }
    }
}
