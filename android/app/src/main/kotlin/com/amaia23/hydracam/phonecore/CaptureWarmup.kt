package com.amaia23.hydracam.phonecore

/** Camera-agnostic 3A readiness signals mapped from a completed capture result. */
data class WarmupSignals(
    val exposureConverged: Boolean,
    val afFocused: Boolean,
    val lensStationary: Boolean = true,
    val focusDistance: Float? = null,
)

data class WarmupProgress(val exposureLocked: Boolean, val focusLocked: Boolean) {
    val complete: Boolean get() = exposureLocked && focusLocked

    fun shouldLockExposure(elapsedMs: Long, converged: Boolean, focusReady: Boolean): Boolean =
        !exposureLocked && ((converged && focusReady) || elapsedMs >= CaptureWarmupDefaults.MAX_MS)
}

sealed interface FocusLock {
    data object Fixed : FocusLock
    data object Trigger : FocusLock
    data class Manual(val distance: Float) : FocusLock
}

data class CaptureWarmupAction(val lockExposure: Boolean, val focus: FocusLock?, val exposureConverged: Boolean)

object CaptureWarmupDefaults {
    const val MIN_MS = 1_500L
    const val MAX_MS = 4_000L
}

/** Exposure/AWB have a deadline; that deadline must never freeze an unfinished autofocus scan. */
fun captureWarmupAction(
    elapsedMs: Long,
    progress: WarmupProgress,
    fixedFocus: Boolean,
    manualFocus: Boolean,
    signals: WarmupSignals,
): CaptureWarmupAction? {
    if (elapsedMs < CaptureWarmupDefaults.MIN_MS || progress.complete) return null
    val focus = if (progress.focusLocked) null else readyFocus(fixedFocus, manualFocus, signals)
    val converged = signals.exposureConverged
    val lockExposure = progress.shouldLockExposure(elapsedMs, converged, progress.focusLocked || focus != null)
    val exposureReady = progress.exposureLocked || lockExposure
    val hasChange = lockExposure || focus != null
    return if (exposureReady && hasChange) {
        CaptureWarmupAction(lockExposure, focus, converged)
    } else {
        null
    }
}

private fun readyFocus(fixedFocus: Boolean, manualFocus: Boolean, signals: WarmupSignals): FocusLock? {
    if (fixedFocus) return FocusLock.Fixed
    if (!signals.afFocused || !signals.lensStationary) return null
    val distance = signals.focusDistance?.takeIf { it.isFinite() && it >= 0f }
    return if (manualFocus && distance != null) {
        FocusLock.Manual(distance)
    } else {
        FocusLock.Trigger
    }
}
