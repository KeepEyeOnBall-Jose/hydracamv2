package com.amaia23.hydracam.court

import android.hardware.camera2.CaptureResult
import com.amaia23.hydracam.phonecore.WarmupSignals
import com.amaia23.hydracam.phonecore.captureWarmupAction as phonecoreCaptureWarmupAction

internal typealias WarmupProgress = com.amaia23.hydracam.phonecore.WarmupProgress
internal typealias FocusLock = com.amaia23.hydracam.phonecore.FocusLock
internal typealias CaptureWarmupAction = com.amaia23.hydracam.phonecore.CaptureWarmupAction

/** Only values from the current completed Camera2 result may choose a focus distance. */
internal data class WarmupObservation(
    val aeState: Int?,
    val awbState: Int?,
    val afState: Int?,
    val lensState: Int?,
    val focusDistance: Float?,
) {
    val exposureConverged: Boolean
        get() {
            val aeReady = aeState == null ||
                aeState == CaptureResult.CONTROL_AE_STATE_CONVERGED ||
                aeState == CaptureResult.CONTROL_AE_STATE_FLASH_REQUIRED
            val awbReady = awbState == null || awbState == CaptureResult.CONTROL_AWB_STATE_CONVERGED
            return aeReady && awbReady
        }

    fun toSignals(): WarmupSignals = WarmupSignals(
        exposureConverged = exposureConverged,
        afFocused = afState == CaptureResult.CONTROL_AF_STATE_PASSIVE_FOCUSED ||
            afState == CaptureResult.CONTROL_AF_STATE_FOCUSED_LOCKED,
        lensStationary = lensState == null || lensState == CaptureResult.LENS_STATE_STATIONARY,
        focusDistance = focusDistance,
    )
}

/** Exposure/AWB have a deadline; that deadline must never freeze an unfinished autofocus scan. */
internal fun captureWarmupAction(
    elapsedMs: Long,
    progress: WarmupProgress,
    fixedFocus: Boolean,
    manualFocus: Boolean,
    observed: WarmupObservation,
    continuousAuto: Boolean = false,
): CaptureWarmupAction? {
    if (continuousAuto) return null
    return phonecoreCaptureWarmupAction(
        elapsedMs = elapsedMs,
        progress = progress,
        fixedFocus = fixedFocus,
        manualFocus = manualFocus,
        signals = observed.toSignals(),
    )
}
