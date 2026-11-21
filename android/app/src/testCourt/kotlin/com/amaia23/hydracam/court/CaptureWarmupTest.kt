package com.amaia23.hydracam.court

import android.hardware.camera2.CaptureResult
import com.amaia23.hydracam.phonecore.FocusLock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Protocol-state cases, not substitutes for the retained real blurred camera images. */
class CaptureWarmupTest {
    @Test
    fun convergedExposureMustNotFreezeSearchingTenDiopterFocus() {
        assertNull(decide(elapsed = 1510, afState = CaptureResult.CONTROL_AF_STATE_PASSIVE_SCAN, focus = 10f))
        val timeout = decide(elapsed = 4000, afState = CaptureResult.CONTROL_AF_STATE_PASSIVE_SCAN, focus = 10f)!!
        assertTrue(timeout.lockExposure)
        assertNull(timeout.focus)
    }

    @Test
    fun focusedButMovingLensMustRemainPending() {
        assertNull(decide(lensState = CaptureResult.LENS_STATE_MOVING))
        assertNull(decide(elapsed = 4000, lensState = CaptureResult.LENS_STATE_MOVING)!!.focus)
    }

    @Test
    fun focusLockUsesOnlyTheReadyCurrentResult() {
        assertNull(decide(elapsed = 4000, afState = CaptureResult.CONTROL_AF_STATE_PASSIVE_SCAN, focus = 10f)!!.focus)
        val ready = decide(elapsed = 4500, exposureLocked = true, focus = 0.4837024f)!!
        assertFalse(ready.lockExposure)
        assertEquals(FocusLock.Manual(0.4837024f), ready.focus)
        assertEquals(
            FocusLock.Manual(0f),
            decide(afState = CaptureResult.CONTROL_AF_STATE_FOCUSED_LOCKED, focus = 0f)!!.focus,
        )
    }

    @Test
    fun optionalLensStateDoesNotInventMovementAndUnknownAfDoesNotQualify() {
        assertEquals(FocusLock.Manual(0f), decide(lensState = null)!!.focus)
        val missingOrUnfocused = listOf(
            null,
            CaptureResult.CONTROL_AF_STATE_INACTIVE,
            CaptureResult.CONTROL_AF_STATE_ACTIVE_SCAN,
            CaptureResult.CONTROL_AF_STATE_PASSIVE_UNFOCUSED,
            CaptureResult.CONTROL_AF_STATE_NOT_FOCUSED_LOCKED,
        )
        for (state in missingOrUnfocused) {
            assertNull(decide(elapsed = 4000, afState = state)!!.focus)
        }
    }

    @Test
    fun fixedFocusIsExemptButMinimumWarmupStillApplies() {
        assertNull(decide(elapsed = 1499, fixedFocus = true, afState = null, focus = null))
        assertEquals(FocusLock.Fixed, decide(fixedFocus = true, afState = null, lensState = null, focus = null)!!.focus)
    }

    @Test
    fun readyAutofocusWithoutUsableManualDistanceUsesAfTrigger() {
        assertEquals(FocusLock.Trigger, decide(manualFocus = false)!!.focus)
        for (distance in listOf(null, Float.NaN, Float.POSITIVE_INFINITY, -1f)) {
            assertEquals(FocusLock.Trigger, decide(focus = distance)!!.focus)
        }
    }

    @Test
    fun exposureStillWaitsForConvergenceOrItsBoundedTimeout() {
        assertNull(decide(aeState = CaptureResult.CONTROL_AE_STATE_SEARCHING))
        assertNull(decide(awbState = CaptureResult.CONTROL_AWB_STATE_SEARCHING))
        assertTrue(decide(elapsed = 4000, aeState = CaptureResult.CONTROL_AE_STATE_SEARCHING)!!.lockExposure)
        assertEquals(FocusLock.Manual(0f), decide(aeState = CaptureResult.CONTROL_AE_STATE_FLASH_REQUIRED)!!.focus)
        assertTrue(decide(aeState = null, awbState = null)!!.lockExposure)
        assertNull(decide(exposureLocked = true, focusLocked = true))
        assertNull(decide(exposureLocked = true, afState = CaptureResult.CONTROL_AF_STATE_PASSIVE_SCAN))
        assertNull(decide(focusLocked = true)!!.focus)
    }

    @Test
    fun supersededCallbackCannotApplyLateFocusToRewarmedSession() {
        val readback = CaptureReadbackState()
        val previous = readback.reset()
        val current = readback.reset()
        val focused = CaptureReadback(afState = CaptureResult.CONTROL_AF_STATE_PASSIVE_FOCUSED)
        assertFalse(readback.completed(previous, focused))
        assertNull(readback.transition(previous))
        assertTrue(readback.completed(current, focused))
        val proposed = decide(exposureLocked = true, elapsed = 4500)!!
        // Rewarm may happen after completed(), before the recorder applies the proposed controls.
        readback.reset()
        assertNull(readback.transition(current))
        assertEquals(FocusLock.Manual(0f), proposed.focus)
        assertNull(readback.latest())
    }

    private fun decide(
        elapsed: Long = 1500,
        exposureLocked: Boolean = false,
        focusLocked: Boolean = false,
        fixedFocus: Boolean = false,
        manualFocus: Boolean = true,
        aeState: Int? = CaptureResult.CONTROL_AE_STATE_CONVERGED,
        awbState: Int? = CaptureResult.CONTROL_AWB_STATE_CONVERGED,
        afState: Int? = CaptureResult.CONTROL_AF_STATE_PASSIVE_FOCUSED,
        lensState: Int? = CaptureResult.LENS_STATE_STATIONARY,
        focus: Float? = 0f,
    ) = captureWarmupAction(
        elapsed,
        WarmupProgress(exposureLocked, focusLocked),
        fixedFocus,
        manualFocus,
        WarmupObservation(aeState, awbState, afState, lensState, focus),
    )
}
