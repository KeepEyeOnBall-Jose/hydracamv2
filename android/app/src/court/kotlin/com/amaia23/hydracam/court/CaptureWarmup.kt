package com.amaia23.hydracam.court

import android.hardware.camera2.CaptureResult

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
}

internal data class WarmupProgress(val exposureLocked: Boolean, val focusLocked: Boolean) {
    val complete: Boolean get() = exposureLocked && focusLocked

    fun shouldLockExposure(elapsedMs: Long, converged: Boolean, focusReady: Boolean): Boolean =
        !exposureLocked && ((converged && focusReady) || elapsedMs >= WARMUP_MAX_MS)
}

internal sealed interface FocusLock {
    data object Fixed : FocusLock
    data object Trigger : FocusLock
    data class Manual(val distance: Float) : FocusLock
}

internal data class CaptureWarmupAction(
    val lockExposure: Boolean,
    val focus: FocusLock?,
    val exposureConverged: Boolean,
)

/** Exposure/AWB have a deadline; that deadline must never freeze an unfinished autofocus scan. */
internal fun captureWarmupAction(
    elapsedMs: Long,
    progress: WarmupProgress,
    fixedFocus: Boolean,
    manualFocus: Boolean,
    observed: WarmupObservation,
): CaptureWarmupAction? {
    if (elapsedMs < WARMUP_MIN_MS || progress.complete) return null
    val focus = if (progress.focusLocked) null else readyFocus(fixedFocus, manualFocus, observed)
    val converged = observed.exposureConverged
    val lockExposure = progress.shouldLockExposure(elapsedMs, converged, progress.focusLocked || focus != null)
    val exposureReady = progress.exposureLocked || lockExposure
    val hasChange = lockExposure || focus != null
    return if (exposureReady && hasChange) {
        CaptureWarmupAction(lockExposure, focus, converged)
    } else {
        null
    }
}

private fun readyFocus(fixedFocus: Boolean, manualFocus: Boolean, observed: WarmupObservation): FocusLock? {
    if (fixedFocus) return FocusLock.Fixed
    val afReady = observed.afState == CaptureResult.CONTROL_AF_STATE_PASSIVE_FOCUSED ||
        observed.afState == CaptureResult.CONTROL_AF_STATE_FOCUSED_LOCKED
    val stationary = observed.lensState == null || observed.lensState == CaptureResult.LENS_STATE_STATIONARY
    if (!afReady || !stationary) return null
    val distance = observed.focusDistance?.takeIf { it.isFinite() && it >= 0f }
    return if (manualFocus && distance != null) {
        FocusLock.Manual(distance)
    } else {
        FocusLock.Trigger
    }
}

private const val WARMUP_MIN_MS = 1_500L
private const val WARMUP_MAX_MS = 4_000L
