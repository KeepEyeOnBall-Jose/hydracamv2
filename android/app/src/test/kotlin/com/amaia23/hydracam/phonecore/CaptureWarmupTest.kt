package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureWarmupTest {
    @Test
    fun minimumWarmupWindowBlocksLockEvenWhenConvergedOrFixedFocus() {
        assertNull(decide(elapsedMs = CaptureWarmupDefaults.MIN_MS - 1))
        assertNull(
            decide(
                elapsedMs = CaptureWarmupDefaults.MIN_MS - 1,
                fixedFocus = true,
                afFocused = false,
                lensStationary = false,
                focusDistance = null,
            ),
        )
        val atMin = decide(elapsedMs = CaptureWarmupDefaults.MIN_MS)!!
        assertTrue(atMin.lockExposure)
        assertTrue(atMin.exposureConverged)
        assertEquals(FocusLock.Manual(0f), atMin.focus)
    }

    @Test
    fun convergedExposureAndReadyFocusLockTogether() {
        val action = decide(elapsedMs = 1_600, focusDistance = 0.4837024f)!!
        assertTrue(action.lockExposure)
        assertTrue(action.exposureConverged)
        assertEquals(FocusLock.Manual(0.4837024f), action.focus)
    }

    @Test
    fun exposureConvergenceDoesNotFreezeScanningOrMovingLensBeforeOrAtDeadline() {
        assertNull(decide(elapsedMs = 1_600, afFocused = false, focusDistance = 10f))
        assertNull(decide(elapsedMs = 1_600, lensStationary = false, focusDistance = 0.5f))

        val scanningTimeout = decide(
            elapsedMs = CaptureWarmupDefaults.MAX_MS,
            afFocused = false,
            focusDistance = 10f,
        )!!
        assertTrue(scanningTimeout.lockExposure)
        assertTrue(scanningTimeout.exposureConverged)
        assertNull(scanningTimeout.focus)

        val movingTimeout = decide(
            elapsedMs = CaptureWarmupDefaults.MAX_MS,
            lensStationary = false,
            focusDistance = 0.5f,
        )!!
        assertTrue(movingTimeout.lockExposure)
        assertNull(movingTimeout.focus)
    }

    @Test
    fun maxWarmupDeadlineLocksUnconvergedExposureAndLaterFocusLocksSeparately() {
        assertNull(decide(elapsedMs = 2_000, exposureConverged = false))

        val exposureFallback = decide(
            elapsedMs = CaptureWarmupDefaults.MAX_MS,
            exposureConverged = false,
            afFocused = false,
        )!!
        assertTrue(exposureFallback.lockExposure)
        assertFalse(exposureFallback.exposureConverged)
        assertNull(exposureFallback.focus)

        assertNull(
            decide(
                elapsedMs = 4_200,
                exposureLocked = true,
                afFocused = false,
            ),
        )

        val lateFocus = decide(
            elapsedMs = 4_500,
            exposureLocked = true,
            exposureConverged = false,
            afFocused = true,
            lensStationary = true,
            focusDistance = 0.4837024f,
        )!!
        assertFalse(lateFocus.lockExposure)
        assertFalse(lateFocus.exposureConverged)
        assertEquals(FocusLock.Manual(0.4837024f), lateFocus.focus)
    }

    @Test
    fun alreadyLockedFocusAllowsExposureToFinishSeparatelyAndCompleteProgressStops() {
        assertNull(decide(elapsedMs = 2_000, focusLocked = true, exposureConverged = false))
        val finishExposure = decide(elapsedMs = 2_000, focusLocked = true, exposureConverged = true)!!
        assertTrue(finishExposure.lockExposure)
        assertNull(finishExposure.focus)

        assertNull(decide(elapsedMs = 5_000, exposureLocked = true, focusLocked = true))
    }

    @Test
    fun manualTriggerAndFixedFocusPoliciesSelectExpectedFocusLock() {
        val fixed = decide(fixedFocus = true, afFocused = false, lensStationary = false, focusDistance = null)!!
        assertEquals(FocusLock.Fixed, fixed.focus)

        val triggerWhenManualOff = decide(manualFocus = false, focusDistance = 1.5f)!!
        assertEquals(FocusLock.Trigger, triggerWhenManualOff.focus)

        for (invalidDistance in listOf(null, Float.NaN, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY, -0.1f)) {
            val trigger = decide(manualFocus = true, focusDistance = invalidDistance)!!
            assertEquals(FocusLock.Trigger, trigger.focus)
        }

        assertEquals(FocusLock.Manual(0f), decide(manualFocus = true, focusDistance = 0f)!!.focus)
    }

    private fun decide(
        elapsedMs: Long = CaptureWarmupDefaults.MIN_MS,
        exposureLocked: Boolean = false,
        focusLocked: Boolean = false,
        fixedFocus: Boolean = false,
        manualFocus: Boolean = true,
        exposureConverged: Boolean = true,
        afFocused: Boolean = true,
        lensStationary: Boolean = true,
        focusDistance: Float? = 0f,
    ): CaptureWarmupAction? = captureWarmupAction(
        elapsedMs = elapsedMs,
        progress = WarmupProgress(exposureLocked, focusLocked),
        fixedFocus = fixedFocus,
        manualFocus = manualFocus,
        signals = WarmupSignals(
            exposureConverged = exposureConverged,
            afFocused = afFocused,
            lensStationary = lensStationary,
            focusDistance = focusDistance,
        ),
    )
}
