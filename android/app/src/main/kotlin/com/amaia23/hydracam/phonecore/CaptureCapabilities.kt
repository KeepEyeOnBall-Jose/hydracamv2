package com.amaia23.hydracam.phonecore

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
    private val FRAME_RATES = C1ContractConstants.Profile.FPS_OPTIONS
    private const val NANOS_PER_SECOND = 1_000_000_000L
    private const val PROXY_KBPS = C1ContractConstants.Profile.PROXY_KBPS
    private const val MAX_KBPS = 100_000

    fun profiles(
        lenses: List<LensInfo>,
        minFrameDurationNs: (String, Pair<Int, Int>) -> Long?,
        encoderMaxKbps: (Pair<Int, Int>, Int) -> Int?,
        hevcMaxKbps: (Pair<Int, Int>, Int) -> Int? = { _, _ -> null },
    ): List<CaptureProfileCapability> {
        val rates = FRAME_RATES.filter { fps -> lenses.any { lens -> lens.aeFpsRanges.any { it.last == fps } } }
        val encoders = mapOf(CaptureTarget.CODEC_AVC to encoderMaxKbps, CaptureTarget.CODEC_HEVC to hevcMaxKbps)
        return rates.flatMap { fps -> profilesAtRate(lenses, minFrameDurationNs, encoderMaxKbps, encoders, fps) }
    }

    /** [masterEncoders]: each recordable master codec's top bitrate for a size and fps, null when absent. */
    private fun profilesAtRate(
        lenses: List<LensInfo>,
        minFrameDurationNs: (String, Pair<Int, Int>) -> Long?,
        proxyEncoderMaxKbps: (Pair<Int, Int>, Int) -> Int?,
        masterEncoders: Map<String, (Pair<Int, Int>, Int) -> Int?>,
        fps: Int,
    ): List<CaptureProfileCapability> {
        val proxy = RecordProfile.sizeFor(C1ContractConstants.Profile.PROXY_RES)
        if ((proxyEncoderMaxKbps(proxy, fps) ?: 0) < PROXY_KBPS) return emptyList()
        // Camera2 reports integer nanoseconds; allow rounding up by less than one nanosecond.
        val frameNs = (NANOS_PER_SECOND + fps - 1) / fps
        return C1ContractConstants.Lens.ALL.flatMap { role ->
            C1ContractConstants.Profile.MASTER_RESOLUTIONS.flatMap { resolution ->
                val profile = RecordProfile(masterRes = resolution, fps = fps)
                val plan = CapturePlanner.plan(profile, CaptureTarget(lens = role), lenses) as? CapturePlan
                val timed = plan != null && listOf(plan.masterSize, proxy).all { size ->
                    val duration = minFrameDurationNs(plan.cameraId, size)
                    duration != null && duration > 0 && duration <= frameNs
                }
                if (plan == null || !timed) return@flatMap emptyList()
                masterEncoders.mapNotNull { (codec, encoderMaxKbps) ->
                    encoderMaxKbps(plan.masterSize, fps)?.coerceAtMost(MAX_KBPS)
                        ?.takeIf { it >= PROXY_KBPS }
                        ?.let { CaptureProfileCapability(resolution, fps, role, codec, it) }
                }
            }
        }
    }
}
