package com.amaia23.hydracam.court

import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * One back camera as Camera2 shows it, reduced to what C1 1.16 capture needs. [viewWidth] is the
 * sensor width over the shortest focal length (larger: wider view); null when the phone does not
 * report it. Null mode lists mean the control is absent, so the request leaves it unset.
 */
data class LensInfo(
    val cameraId: String,
    val viewWidth: Double?,
    val zoomRange: ClosedFloatingPointRange<Double>?,
    val aeFpsRanges: List<IntRange>,
    val videoSizes: List<Pair<Int, Int>>,
    val videoStabilizationModes: List<Int>?,
    val oisModes: List<Int>?,
    val manualSensor: Boolean,
    val exposureRangeNs: LongRange?,
    val isoRange: IntRange?,
    val fixedFocus: Boolean = false,
) {
    companion object {
        fun viewWidth(sensorWidthMm: Float?, focalLengthsMm: FloatArray?): Double? {
            val focal = focalLengthsMm?.minOrNull() ?: return null
            if (sensorWidthMm == null || focal <= 0f) {
                return null
            }
            return sensorWidthMm.toDouble() / focal
        }
    }
}

sealed interface CapturePlanResult

/** C1 1.16 `nack.code` `unsupported`; [reason] names the field first, e.g. `capture.lens: ...`. */
data class CaptureUnsupported(val field: String, val detail: String) : CapturePlanResult {
    val reason = "$field: $detail"
}

/** The Camera2 settings a `record.prepare` maps to on this phone. Null modes are left unset. */
data class CapturePlan(
    val cameraId: String,
    val lens: String,
    val zoomRatio: Double,
    val zoomControl: Boolean,
    val videoStabilizationMode: Int?,
    val oisMode: Int?,
    val fpsRange: IntRange,
    val masterSize: Pair<Int, Int>,
    val proxySize: Pair<Int, Int>,
    val shutterNs: Long?,
    val frameDurationNs: Long,
    val fixedFocus: Boolean,
    val isoRange: IntRange? = null,
) : CapturePlanResult {
    /**
     * The ISO that keeps the auto-exposure brightness at the fixed shutter: the warm-up chose
     * [autoExposureNs] at [autoIso], so a faster shutter needs proportionally more gain. Null when
     * there is no fixed shutter.
     */
    fun isoFor(autoIso: Int, autoExposureNs: Long): Int? {
        val shutter = shutterNs ?: return null
        val range = isoRange ?: return null
        return (autoIso.toDouble() * autoExposureNs / shutter).roundToInt().coerceIn(range)
    }
}

/** C1 1.16 on K1: which lens and Camera2 settings a capture target maps to, or why it cannot. */
object CapturePlanner {
    /** 1/500 s: sharp ball and racket frames at 30 fps (PRD C.1). */
    const val DEFAULT_SHUTTER_NS = 2_000_000L
    const val STABILIZATION_OFF = 0
    const val STABILIZATION_ON = 1

    /** The court fleet's main lens is camera 0; the ultrawide and tele are found by field of view. */
    const val WIDE_ID = "0"

    /** K2 compares zoom within ±0.01; a target that close to 1x is no zoom. */
    private const val ZOOM_TOLERANCE = 0.01
    private const val ULTRAWIDE_FACTOR = 1.25
    private const val TELE_FACTOR = 0.8
    private const val NANOS_PER_SECOND = 1_000_000_000L

    fun plan(
        profile: RecordProfile,
        target: CaptureTarget,
        lenses: List<LensInfo>,
        wideId: String = WIDE_ID,
    ): CapturePlanResult {
        val lens = lensFor(target.lens, lenses, wideId)
            ?: return CaptureUnsupported("capture.lens", "this phone has no ${target.lens} back lens")
        if (target.codec != CaptureTarget.CODEC_AVC) {
            return CaptureUnsupported("capture.codec", "only avc is recorded")
        }
        if (target.rotationDeg != 0) {
            return CaptureUnsupported(
                "capture.rotationDeg",
                "the encoder cannot rotate the picture; mount the phone upright",
            )
        }
        val zoom = zoomFor(target.zoomRatio, lens)
            ?: return CaptureUnsupported("capture.zoomRatio", zoomDetail(target.zoomRatio, lens))
        val stabilization = stabilizationFor(target.stabilization, lens)
            ?: return CaptureUnsupported("capture.stabilization", stabilizationDetail(target.stabilization, lens))
        val fpsRange = fpsRangeFor(profile.fps, lens.aeFpsRanges)
            ?: return CaptureUnsupported("profile.fps", fpsDetail(profile.fps, lens))
        val master = videoSize(profile.masterRes, lens)
            ?: return CaptureUnsupported("profile.masterRes", sizeDetail(profile.masterRes, lens))
        val proxy = videoSize(profile.proxyRes, lens)
            ?: return CaptureUnsupported("profile.proxyRes", sizeDetail(profile.proxyRes, lens))
        val frameDurationNs = NANOS_PER_SECOND / profile.fps
        return CapturePlan(
            cameraId = lens.cameraId,
            lens = target.lens,
            zoomRatio = zoom,
            zoomControl = lens.zoomRange != null,
            videoStabilizationMode = stabilization.video,
            oisMode = stabilization.ois,
            fpsRange = fpsRange,
            masterSize = master,
            proxySize = proxy,
            shutterNs = shutterFor(lens, frameDurationNs),
            frameDurationNs = frameDurationNs,
            fixedFocus = lens.fixedFocus,
            isoRange = lens.isoRange,
        )
    }

    /** The [candidates] some auto-exposure range ends at: what `hello.caps.fps` may promise. */
    fun recordableFps(ranges: List<IntRange>, candidates: List<Int>): List<Int> =
        candidates.filter { fps -> ranges.any { it.last == fps } }

    private fun lensFor(role: String, lenses: List<LensInfo>, wideId: String): LensInfo? {
        val wide = lenses.firstOrNull { it.cameraId == wideId } ?: return null
        val width = wide.viewWidth
        val others = lenses.filter { it.cameraId != wideId }.mapNotNull { lens -> lens.viewWidth?.let { lens to it } }
        val chosen = when {
            role == CaptureTarget.LENS_WIDE -> wide to width
            width == null -> null
            role == CaptureTarget.LENS_ULTRAWIDE ->
                others.filter { it.second > width * ULTRAWIDE_FACTOR }.maxByOrNull { it.second }
            else -> others.filter { it.second < width * TELE_FACTOR }.minByOrNull { it.second }
        }
        return chosen?.first
    }

    /** Below 1x would quietly switch lenses on a logical camera; K2 asks for the ultrawide instead. */
    private fun zoomFor(wanted: Double, lens: LensInfo): Double? {
        val zoom = if (abs(wanted - 1.0) <= ZOOM_TOLERANCE) 1.0 else wanted
        val range = lens.zoomRange
        return when {
            zoom == 1.0 -> zoom
            zoom < 1.0 || range == null -> null
            else -> zoom.takeIf { it in range }
        }
    }

    private fun zoomDetail(wanted: Double, lens: LensInfo): String {
        val range = lens.zoomRange?.let { "${it.start}..${it.endInclusive}" } ?: "1.0 only"
        return "${wanted}x is outside camera ${lens.cameraId}'s zoom $range; below 1x ask for the ultrawide lens"
    }

    private data class Stabilization(val video: Int?, val ois: Int?)

    /** Off needs every present control to offer off; on needs at least one to offer on. */
    private fun stabilizationFor(wanted: Boolean, lens: LensInfo): Stabilization? {
        val video = lens.videoStabilizationModes
        val ois = lens.oisModes
        if (!wanted) {
            val canTurnOff = video?.contains(STABILIZATION_OFF) != false && ois?.contains(STABILIZATION_OFF) != false
            return Stabilization(video?.let { STABILIZATION_OFF }, ois?.let { STABILIZATION_OFF }).takeIf { canTurnOff }
        }
        val videoOn = video?.contains(STABILIZATION_ON) == true
        val oisOn = ois?.contains(STABILIZATION_ON) == true
        return Stabilization(video?.let { onOrOff(videoOn) }, ois?.let { onOrOff(oisOn) }).takeIf { videoOn || oisOn }
    }

    private fun onOrOff(on: Boolean) = if (on) STABILIZATION_ON else STABILIZATION_OFF

    private fun stabilizationDetail(wanted: Boolean, lens: LensInfo): String = if (wanted) {
        "camera ${lens.cameraId} offers no stabilization"
    } else {
        "camera ${lens.cameraId} cannot turn stabilization off"
    }

    /** The exact [fps, fps] range; else the narrowest range ending at [fps]. */
    private fun fpsRangeFor(fps: Int, ranges: List<IntRange>): IntRange? {
        val reaching = ranges.filter { it.last == fps }
        return reaching.firstOrNull { it.first == fps } ?: reaching.maxByOrNull { it.first }
    }

    private fun fpsDetail(fps: Int, lens: LensInfo): String {
        val max = lens.aeFpsRanges.maxOfOrNull { it.last } ?: 0
        return "$fps fps is not recordable on camera ${lens.cameraId}; at most $max"
    }

    private fun videoSize(res: String, lens: LensInfo): Pair<Int, Int>? =
        RecordProfile.sizeFor(res).takeIf { it in lens.videoSizes }

    private fun sizeDetail(res: String, lens: LensInfo): String {
        val (width, height) = RecordProfile.sizeFor(res)
        return "camera ${lens.cameraId} cannot encode $res (${width}x$height)"
    }

    /** [DEFAULT_SHUTTER_NS] within the sensor's range and the frame; null without manual exposure. */
    private fun shutterFor(lens: LensInfo, frameDurationNs: Long): Long? {
        val range = lens.exposureRangeNs
        if (!lens.manualSensor || range == null || lens.isoRange == null) {
            return null
        }
        return DEFAULT_SHUTTER_NS.coerceIn(range).coerceAtMost(frameDurationNs)
    }
}

/** What the camera reported in the last capture result before recording; null: not reported. */
data class CaptureReadback(
    val aeMode: Int? = null,
    val aeLock: Boolean? = null,
    val afMode: Int? = null,
    val afState: Int? = null,
    val awbMode: Int? = null,
    val awbLock: Boolean? = null,
    val zoomRatio: Double? = null,
    val videoStabilizationMode: Int? = null,
    val oisMode: Int? = null,
    val frameDurationNs: Long? = null,
    val exposureTimeNs: Long? = null,
    val sensitivity: Int? = null,
) {
    val aeLocked: Boolean get() = aeMode == MODE_OFF || aeLock == true

    val awbLocked: Boolean get() = awbMode == MODE_OFF || awbLock == true

    /** A fixed-focus lens never hunts, so it counts as locked. */
    fun afLocked(fixedFocus: Boolean): Boolean =
        fixedFocus || afMode == MODE_OFF || afState == AF_FOCUSED_LOCKED || afState == AF_NOT_FOCUSED_LOCKED

    companion object {
        /** `CONTROL_AE_MODE_OFF`, `CONTROL_AF_MODE_OFF`, `CONTROL_AWB_MODE_OFF`. */
        const val MODE_OFF = 0
        const val AF_FOCUSED_LOCKED = 4
        const val AF_NOT_FOCUSED_LOCKED = 5
    }
}

const val MIME_AVC = "video/avc"
const val MIME_HEVC = "video/hevc"

/** The master encoder's output format: the picture it actually encodes and the rate it was given. */
data class EncoderReadback(val mime: String, val width: Int, val height: Int, val kbps: Int)

/**
 * C1 1.16 `recording.started.applied` from the plan, the camera's readback and the encoder. Null
 * when the zoom could not be read back on a lens that zooms, or the codec is not a contract one:
 * K2 is then told nothing rather than something unverified.
 */
fun appliedCapture(plan: CapturePlan, readback: CaptureReadback, encoder: EncoderReadback): AppliedCapture? {
    val zoom = readback.zoomRatio ?: 1.0.takeUnless { plan.zoomControl } ?: return null
    val codec = when (encoder.mime) {
        MIME_AVC -> CaptureTarget.CODEC_AVC
        MIME_HEVC -> CaptureTarget.CODEC_HEVC
        else -> return null
    }
    val fps = readback.frameDurationNs?.takeIf { it > 0 }?.let { (NANOS_PER_SECOND_D / it).roundToInt() }
        ?: plan.fpsRange.last
    val video = readback.videoStabilizationMode ?: plan.videoStabilizationMode
    val ois = readback.oisMode ?: plan.oisMode
    return AppliedCapture(
        cameraId = plan.cameraId,
        lens = plan.lens,
        width = encoder.width,
        height = encoder.height,
        fps = fps,
        codec = codec,
        masterKbps = encoder.kbps,
        rotationDeg = 0,
        zoomRatio = zoom,
        stabilization = video == CapturePlanner.STABILIZATION_ON || ois == CapturePlanner.STABILIZATION_ON,
        aeLocked = readback.aeLocked,
        afLocked = readback.afLocked(plan.fixedFocus),
        awbLocked = readback.awbLocked,
        exposureTimeNs = readback.exposureTimeNs,
        iso = readback.sensitivity,
    )
}

private const val NANOS_PER_SECOND_D = 1e9
